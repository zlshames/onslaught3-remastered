import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/providers.dart';
import '../../app/ui_skin.dart';
import '../../services/assets/asset_pack.dart';
import '../../services/assets/procedural_ground_pack.dart';
import '../../services/audio/audio_service.dart';
import '../../services/haptics/haptics.dart';
import '../../services/logging/logging.dart';
import '../../services/persistence/game_in_progress.dart';
import '../../services/persistence/profile.dart';
import '../../services/persistence/settings.dart';
import 'effect_settings.dart';
import 'flame/onslaught_flame_game.dart';
import 'game_audio.dart';
import 'game_event_log.dart';
import 'game_haptics.dart';
import 'game_view_model.dart';
import 'progress_recorder.dart';

const Logger _log = Logger('game');

/// What to play: a map in a mode, at a difficulty, or a challenge.
@immutable
class GameSetup {
  const GameSetup({
    required this.mapId,
    this.mode = defaultMode,
    this.difficulty = defaultDifficulty,
    this.challengeKey,
  });

  /// The tutorial on its own map.
  const GameSetup.tutorial()
    : mapId = null,
      mode = GameConfig.tutorialMode,
      difficulty = defaultDifficulty,
      challengeKey = null;

  /// The mode and difficulty played when none (or an unknown one) is named.
  static const String defaultMode = 'normal';
  static const String defaultDifficulty = 'easy';

  /// A built-in map id or a player map's id (`MapLibrary`); null = the
  /// tutorial's map.
  final String? mapId;

  /// A `progression.json` mode (`normal`, `sandbox`, `sandbox2`, `tutorial`,
  /// `challenge`).
  final String mode;

  /// A `difficulty.json` level (a challenge plays at its own).
  final String difficulty;

  /// The challenge to play ([challengeKey]), for the challenge mode.
  final String? challengeKey;

  @override
  bool operator ==(Object other) =>
      other is GameSetup &&
      other.mapId == mapId &&
      other.mode == mode &&
      other.difficulty == difficulty &&
      other.challengeKey == challengeKey;

  @override
  int get hashCode => Object.hash(mapId, mode, difficulty, challengeKey);
}

/// The session config for [setup] in [data]: the map (the player map
/// [customMap], the tutorial's own, or the first map if unknown), the mode
/// (normal if unknown, or a challenge without a known key), the challenge
/// from its key (at its own difficulty), the difficulty (easy if unknown),
/// the rule set [profile], and the wave settings when [settings] remember
/// them. Pure: the same inputs give the same config.
GameConfig gameConfigFor(
  GameData data,
  GameSetup setup, {
  required Settings settings,
  required RulesProfile profile,
  MapDefinition? customMap,
}) {
  final modes = data.progression.modes;
  final mode = modes.contains(setup.mode) ? setup.mode : GameSetup.defaultMode;
  final mapId = setup.mapId ?? data.tutorial.map;
  final challenge = mode == GameConfig.challengeMode && setup.challengeKey != null
      ? challengeFromKey(setup.challengeKey!, data.challenges)
      : null;
  final levels = {for (final l in data.difficulty.levels) l.id};
  return GameConfig(
    mapId: customMap?.id ?? (data.maps.containsKey(mapId) ? mapId : data.maps.keys.first),
    customMap: customMap,
    mode: challenge == null && mode == GameConfig.challengeMode ? GameSetup.defaultMode : mode,
    difficulty:
        challenge?.difficulty ??
        (levels.contains(setup.difficulty) ? setup.difficulty : GameSetup.defaultDifficulty),
    challenge: challenge,
    profile: profile,
    waveSpacingMs: settings.waveRemember && settings.waveSpacingS != null
        ? settings.waveSpacingS! * 1000
        : null,
    waveFollow: settings.waveRemember && settings.waveFollow,
  );
}

/// The setup [game] was started with, so a resumed game restarts as the
/// same game.
GameSetup setupOf(GameInProgress game) => GameSetup(
  mapId: game.mapId,
  mode: game.mode,
  difficulty: game.difficulty,
  challengeKey: game.challengeKey,
);

/// The session config [game] was played with, exactly (its seed, profile,
/// wave settings and player map), to rebuild it on. Throws an
/// [ArgumentError] for a rule set this version does not have.
GameConfig savedGameConfig(GameData data, GameInProgress game) {
  final challenge = game.mode == GameConfig.challengeMode && game.challengeKey != null
      ? challengeFromKey(game.challengeKey!, data.challenges)
      : null;
  final profile = RulesProfile.byId(game.profileId);
  final map = game.customMap;
  return map != null
      ? GameConfig.custom(
          map: map,
          mode: game.mode,
          difficulty: game.difficulty,
          profile: profile,
          seed: game.seed,
          challenge: challenge,
          waveSpacingMs: game.waveSpacingMs,
          waveFollow: game.waveFollow,
        )
      : GameConfig(
          mapId: game.mapId,
          mode: game.mode,
          difficulty: game.difficulty,
          profile: profile,
          seed: game.seed,
          challenge: challenge,
          waveSpacingMs: game.waveSpacingMs,
          waveFollow: game.waveFollow,
        );
}

/// One running game and everything that lives exactly as long as it: the
/// session and its view model, the Flame game, sound, haptics, the effect
/// settings and the progress recorder. Made when a game screen opens (or
/// restarts) and disposed when it closes; widgets only read it.
class GameRuntime {
  /// Starts a game of [setup] on [data] with the stored [settings]. [pack]
  /// is the screen's art; [skin] the game's presentation. [readProfile] and
  /// [saveProfile] reach the stored progress; [locale] is the interface
  /// language messages are made in. [resumed] is a game in progress already
  /// rebuilt to where it was left ([SessionReplay]): it is played on, paused,
  /// instead of a new game of [setup].
  GameRuntime({
    required GameData data,
    required AssetPack pack,
    required GameSetup setup,
    required Settings settings,
    required RulesProfile profile,
    required RulesRegistry registry,
    required this.skin,
    required AudioSink audioSink,
    required HapticSink hapticSink,
    required String locale,
    required Profile? Function() readProfile,
    required void Function(Profile Function(Profile)) saveProfile,
    MapDefinition? customMap,
    ActiveMod? mod,
    GameSession? resumed,
  }) : _setup = setup,
       saved = resumed != null,
       viewModel = SessionGameViewModel(
         resumed ??
             GameSession(
               data: data,
               config: gameConfigFor(
                 data,
                 setup,
                 settings: settings,
                 profile: profile,
                 customMap: customMap,
               ),
               registry: registry,
             ),
         locale: locale,
       ) {
    final config = viewModel.session.config;
    if (resumed != null) {
      // A resumed game opens paused, so the player can get their bearings;
      // its speed is in its command log.
      if (!resumed.clock.paused) viewModel.dispatch(const SetPaused(true));
    } else {
      // The tutorial starts paused (`GameTutorial` ctor: `pauseOn`).
      if (config.mode == GameConfig.tutorialMode) viewModel.dispatch(const SetPaused(true));
      if (settings.timeScale != 1) viewModel.dispatch(SetSpeed(settings.timeScale));
    }
    effects = ValueNotifier(effectsFor(data, settings));
    // The sharp ground (Enhanced skin) is fixed when the game starts.
    final gamePack = skin.sharpGroundOffered && settings.sharpGround
        ? AssetPackChain([const ProceduralGroundPack(), pack])
        : pack;
    placementMode = ValueNotifier(settings.placement);
    game = OnslaughtFlameGame(
      viewModel: viewModel,
      pack: gamePack,
      effects: effects,
      placementMode: placementMode,
      skin: skin,
    );
    sound = AudioService(data: data, pack: pack, sink: audioSink)
      ..muted = !settings.soundOn
      ..volumeOverride = settings.volume;
    _audio = GameAudio(viewModel: viewModel, audio: sound);
    _haptics = GameHaptics(viewModel: viewModel, sink: hapticSink, enabled: settings.haptics);
    final modded = mod != null;
    final reasons = customGameReasons(config, modded: modded);
    custom = config.profile.customGamesSeparate && reasons.isNotEmpty;
    if (custom) viewModel.notify(data.text('message.customGame', locale: locale));
    final progress = ProgressRecorder(
      data: data,
      config: config,
      records: recordsProgress(config, modded: modded),
      custom: reasons.isEmpty
          ? null
          : CustomGameIdentity(
              mapId: config.mapId,
              mapName: viewModel.map.name,
              mapVersion: customMap == null ? null : mapVersionHash(customMap),
              mod: mod?.signature,
              modName: mod?.name,
            ),
      difficulty: viewModel.session.difficulty.id,
      read: readProfile,
      save: saveProfile,
      announce: viewModel.notify,
      locale: () => viewModel.locale,
    );
    _progressSub = viewModel.events.listen((e) {
      progress.onEvent(e);
      if (!config.attract) logGameEvent(e);
    });
    if (!config.attract) {
      _log.info(
        resumed != null ? 'game resumed' : 'game started',
        fields: {
          'mode': config.mode,
          'map': config.mapId,
          'difficulty': viewModel.session.difficulty.id,
          'challenge': _setup.challengeKey,
          'seed': config.seed,
          'custom': custom,
          'modName': mod == null ? null : Pii(mod.name),
          'skin': skin.name,
        },
      );
    }
  }

  final SessionGameViewModel viewModel;

  final GameSetup _setup;

  /// This game is the stored game in progress: it was resumed, or saved
  /// when the player left or the app was hidden. Only then does its end
  /// forget the stored one.
  bool saved;

  /// Whether this kind of game can be left and resumed: not the tutorial
  /// (its pages and arrows live outside the simulation) or the attract demo.
  bool get resumable => !config.attract && config.mode != GameConfig.tutorialMode;

  /// The game to store if the player leaves now: null when it is over (lost,
  /// or won and not played on) or not [resumable].
  GameInProgress? inProgress() {
    final s = viewModel.session;
    if (!resumable || s.gameOver) return null;
    return GameInProgress.of(s, challengeKey: _setup.challengeKey);
  }

  /// The game's presentation.
  final UiSkin skin;

  late final OnslaughtFlameGame game;

  /// The game's sounds (muted and turned up or down by the settings).
  late final AudioService sound;

  /// The effects the settings switch (smoke, colour badges).
  late final ValueNotifier<EffectSettings> effects;

  /// How turrets are put down (drag and drop, or drop and lock).
  late final ValueNotifier<PlacementMode> placementMode;

  /// A custom game: it records no progress and is labelled so.
  late final bool custom;

  late final GameAudio _audio;
  late final GameHaptics _haptics;
  late final StreamSubscription<GameEvent> _progressSub;

  GameConfig get config => viewModel.session.config;

  /// The effect settings [settings] choose.
  static EffectSettings effectsFor(GameData data, Settings settings) => EffectSettings(
    rocketSmoke: settings.smokeOn(data),
    smokeMax: settings.smokeLimit(data),
    colourBadges: settings.colourBadges,
  );

  /// Applies edited [settings] that take effect mid-game: sound, volume,
  /// haptics, effects and tower placement.
  void applySettings(Settings settings) {
    placementMode.value = settings.placement;
    sound
      ..muted = !settings.soundOn
      ..volumeOverride = settings.volume;
    _haptics.enabled = settings.haptics;
    effects.value = effectsFor(viewModel.data, settings);
  }

  /// Ends the game: stops recording, sound and haptics and frees the view
  /// model. The Flame game is disposed by its widget.
  void dispose() {
    if (!config.attract) _log.debug('game closed', fields: {'tick': viewModel.session.tick});
    unawaited(_progressSub.cancel());
    unawaited(_audio.dispose());
    unawaited(_haptics.dispose());
    effects.dispose();
    placementMode.dispose();
    viewModel.dispose();
  }
}
