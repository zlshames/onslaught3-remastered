import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/app/providers.dart';
import 'package:onslaught3_remastered/app/ui_skin.dart';
import 'package:onslaught3_remastered/features/game/game_runtime.dart';
import 'package:onslaught3_remastered/services/persistence/profile.dart';
import 'package:onslaught3_remastered/services/persistence/settings.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/fakes.dart';
import '../../support/test_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  group('gameConfigFor', () {
    GameConfig config(GameSetup setup, {Settings settings = const Settings()}) =>
        gameConfigFor(data, setup, settings: settings, profile: RulesProfile.classicFixed);

    test('a known map, mode and difficulty pass through', () {
      final c = config(const GameSetup(mapId: 'map9', mode: 'sandbox', difficulty: 'hard'));
      expect((c.mapId, c.mode, c.difficulty), ('map9', 'sandbox', 'hard'));
      expect(c.challenge, isNull);
      expect(c.customMap, isNull);
      expect(c.profile, RulesProfile.classicFixed);
      expect((c.waveSpacingMs, c.waveFollow), (null, false));
    });

    test('unknown names fall back to the first map, normal and easy', () {
      final c = config(const GameSetup(mapId: 'nope', mode: 'nope', difficulty: 'nope'));
      expect(
        (c.mapId, c.mode, c.difficulty),
        (data.maps.keys.first, GameSetup.defaultMode, GameSetup.defaultDifficulty),
      );
    });

    test("the tutorial plays on the tutorial's own map", () {
      final c = config(const GameSetup.tutorial());
      expect((c.mapId, c.mode), (data.tutorial.map, GameConfig.tutorialMode));
    });

    test('a challenge comes from its key at its own difficulty; no key plays normal', () {
      final warmup = data.challenges.presets.firstWhere((c) => c.id == 'warmup');
      final c = config(
        GameSetup(
          mapId: 'map1',
          mode: GameConfig.challengeMode,
          difficulty: 'nope',
          challengeKey: challengeKey(warmup),
        ),
      );
      expect(c.mode, GameConfig.challengeMode);
      expect(c.challenge?.id, 'warmup');
      expect(c.difficulty, warmup.difficulty);

      final none = config(const GameSetup(mapId: 'map1', mode: GameConfig.challengeMode));
      expect((none.mode, none.challenge), (GameSetup.defaultMode, null));
      final bad = config(
        const GameSetup(mapId: 'map1', mode: GameConfig.challengeMode, challengeKey: 'nope'),
      );
      expect((bad.mode, bad.challenge), (GameSetup.defaultMode, null));
    });

    test('a player map is played as itself', () {
      final map = data.maps['map9']!;
      final c = gameConfigFor(
        data,
        const GameSetup(mapId: 'player-map'),
        settings: const Settings(),
        profile: RulesProfile.classicFixed,
        customMap: map,
      );
      expect(c.customMap, same(map));
      expect(c.mapId, map.id);
    });

    test('wave settings apply only when remembered', () {
      const remembered = Settings(waveRemember: true, waveSpacingS: 12, waveFollow: true);
      final c = config(const GameSetup(mapId: 'map1'), settings: remembered);
      expect((c.waveSpacingMs, c.waveFollow), (12000.0, true));
      const forgotten = Settings(waveSpacingS: 12, waveFollow: true);
      final d = config(const GameSetup(mapId: 'map1'), settings: forgotten);
      expect((d.waveSpacingMs, d.waveFollow), (null, false));
      const noSpacing = Settings(waveRemember: true, waveFollow: true);
      final e = config(const GameSetup(mapId: 'map1'), settings: noSpacing);
      expect((e.waveSpacingMs, e.waveFollow), (null, true));
    });
  });

  group('GameRuntime', () {
    GameRuntime runtime(
      GameSetup setup, {
      Settings settings = const Settings(),
      ActiveMod? mod,
      void Function(Profile Function(Profile))? save,
    }) => GameRuntime(
      data: data,
      pack: EmptyAssetPack(),
      setup: setup,
      settings: settings,
      profile: RulesProfile.classicFixed,
      registry: RulesRegistry.classic(),
      skin: UiSkin.classic,
      audioSink: SilentAudioSink(),
      hapticSink: NoHaptics(),
      locale: 'en',
      readProfile: () => null,
      saveProfile: save ?? (_) {},
      mod: mod,
    );

    void step(GameRuntime r) => r.viewModel.advance(1 / data.rules.tickHz);

    test('starts the configured game with the stored speed', () {
      final r = runtime(
        const GameSetup(mapId: 'map9', mode: 'sandbox'),
        settings: const Settings(timeScale: 2),
      );
      expect((r.config.mapId, r.config.mode), ('map9', 'sandbox'));
      expect(r.game.viewModel, same(r.viewModel));
      step(r);
      expect(r.viewModel.hud.value.speed, 2);
      expect(r.viewModel.hud.value.paused, isFalse);
      expect(r.custom, isFalse);
      r.dispose();
    });

    test('the tutorial starts paused', () {
      final r = runtime(const GameSetup.tutorial());
      step(r);
      expect(r.viewModel.hud.value.paused, isTrue);
      r.dispose();
    });

    test('a modded game is a custom game and says so', () {
      final r = runtime(
        const GameSetup(mapId: 'map9'),
        mod: ActiveMod(name: 'm', signature: 'sig', data: data),
      );
      expect(r.custom, isTrue);
      expect(r.viewModel.messages.value.last.text, data.text('message.customGame'));
      r.dispose();
    });

    test('settings edited mid-game reach sound, effects and haptics', () {
      final r = runtime(const GameSetup(mapId: 'map9'));
      expect(r.sound.muted, isFalse);
      expect(r.effects.value.colourBadges, isFalse);
      r.applySettings(const Settings(soundOn: false, colourBadges: true, volume: 0.5));
      expect(r.sound.muted, isTrue);
      expect(r.sound.volumeOverride, 0.5);
      expect(r.effects.value.colourBadges, isTrue);
      r.dispose();
    });
  });
}
