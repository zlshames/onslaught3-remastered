import 'dart:async';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../app/menu_scaffold.dart';
import '../../app/providers.dart';
import '../../app/settings_form.dart';
import '../../app/strings.dart';
import '../../app/ui_skin.dart';
import '../../services/assets/asset_pack.dart';
import '../../services/logging/logging.dart';
import '../../services/persistence/game_in_progress.dart';
import '../../services/persistence/map_library.dart';
import '../../services/persistence/settings.dart';
import 'effect_settings.dart';
import 'flame/onslaught_flame_game.dart';
import 'game_runtime.dart';
import 'game_view_model.dart';
import 'hud/camera_debug_overlay.dart';
import 'hud/game_over_panel.dart';
import 'hud/hud_keys.dart';
import 'hud/message_toasts.dart';
import 'hud/objective_badges.dart';
import 'hud/placement_hint.dart';
import 'hud/stats_bar.dart';
import 'hud/tower_tray.dart';
import 'hud/turret_sheet.dart';
import 'hud/tutorial_panel.dart';
import 'hud/unsupported_shape.dart';
import 'layout/hud_layout.dart';

export 'game_runtime.dart' show GameSetup;

const Logger _log = Logger('game');

/// Overlay keys of the game screen.
abstract final class GameOverlays {
  static const String stats = 'stats';
  static const String tray = 'tray';
  static const String sheet = 'sheet';
  static const String placementHint = 'placementHint';
  static const String gameOver = 'gameOver';
  static const String messages = 'messages';
  static const String objectives = 'objectives';
  static const String tutorial = 'tutorial';
  static const String cameraDebug = 'cameraDebug';
  static const String customLabel = 'customLabel';
  static const String unsupported = 'unsupported';
}

/// The game: the Flame world behind Flutter HUD overlays.
class GameScreen extends ConsumerWidget {
  GameScreen({
    super.key,
    required String mapId,
    String mode = defaultMode,
    String difficulty = defaultDifficulty,
    String? challengeKey,
  }) : setup = GameSetup(
         mapId: mapId,
         mode: mode,
         difficulty: difficulty,
         challengeKey: challengeKey,
       ),
       resume = false;

  /// The tutorial (`/tutorial`).
  const GameScreen.tutorial({super.key}) : setup = const GameSetup.tutorial(), resume = false;

  /// The stored game in progress, rebuilt where the player left it
  /// (`/resume`); the menu when there is none.
  const GameScreen.resume({super.key}) : setup = null, resume = true;

  /// What to play; null for [resume], which plays the stored game's.
  final GameSetup? setup;

  /// Play the stored game in progress.
  final bool resume;

  static const String defaultMode = GameSetup.defaultMode;
  static const String defaultDifficulty = GameSetup.defaultDifficulty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (resume) return _resumeBuild(context, ref);
    final setup = this.setup!;
    final data = ref.watch(gameDataProvider);
    // The active mod (applied to the data) is fixed when the game starts.
    final mod = ref.watch(activeModProvider);
    final pack = ref.watch(assetPackProvider);
    // Wait for the stored settings and progress so the game starts with them.
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileProvider);
    // A player map is read from the library before the game starts.
    final custom = setup.mapId != null && MapLibrary.isCustomId(setup.mapId!);
    final maps = custom ? ref.watch(mapLibraryProvider) : const AsyncData(MapLibrary());
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch ((data, pack, settings, profile, maps, mod)) {
        (AsyncError(:final error), _, _, _, _, _) ||
        (_, AsyncError(:final error), _, _, _, _) ||
        (_, _, AsyncError(:final error), _, _, _) ||
        (_, _, _, AsyncError(:final error), _, _) ||
        (_, _, _, _, AsyncError(:final error), _) ||
        (_, _, _, _, _, AsyncError(:final error)) => Center(
          child: Text(
            // The error text alone when the data itself failed to load.
            data.value?.tr(context, 'ui.game.loadError', {'error': error}) ?? '$error',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        (
          AsyncData(value: final d),
          AsyncData(value: final p),
          AsyncData(),
          AsyncData(),
          AsyncData(value: final l),
          AsyncData(value: final m),
        ) =>
          _GameRoot(
            key: ValueKey(setup),
            data: m?.data ?? d,
            pack: p,
            setup: setup,
            customMap: custom ? l.byId(setup.mapId!) : null,
            mod: m,
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

extension on GameScreen {
  /// [GameScreen.resume]: waits for the stored game, then plays it as the
  /// game of its own setup, rebuilt first ([_GameRoot.resume]).
  Widget _resumeBuild(BuildContext context, WidgetRef ref) {
    final stored = ref.watch(gameInProgressProvider);
    final game = stored.value;
    if (stored.hasValue && game == null) {
      // Nothing to resume (discarded elsewhere): back to choosing a game.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/mode');
      });
    }
    if (game == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _ResumedGame(game: game);
  }
}

/// The game of a stored game in progress: its setup, data and player map,
/// with the stored game to rebuild before the first round.
class _ResumedGame extends ConsumerWidget {
  const _ResumedGame({required this.game});

  final GameInProgress game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(gameDataProvider);
    final mod = ref.watch(activeModProvider);
    final pack = ref.watch(assetPackProvider);
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileProvider);
    final setup = setupOf(game);
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch ((data, pack, settings, profile, mod)) {
        (AsyncError(:final error), _, _, _, _) ||
        (_, AsyncError(:final error), _, _, _) ||
        (_, _, AsyncError(:final error), _, _) ||
        (_, _, _, AsyncError(:final error), _) ||
        (_, _, _, _, AsyncError(:final error)) => Center(
          child: Text(
            data.value?.tr(context, 'ui.game.loadError', {'error': error}) ?? '$error',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        (
          AsyncData(value: final d),
          AsyncData(value: final p),
          AsyncData(),
          AsyncData(),
          AsyncData(value: final m),
        ) =>
          _GameRoot(
            key: ValueKey(setup),
            data: m?.data ?? d,
            pack: p,
            setup: setup,
            customMap: game.customMap,
            mod: m,
            resume: game,
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// Holds the game number so Restart can start a fresh session.
class _GameRoot extends StatefulWidget {
  const _GameRoot({
    super.key,
    required this.data,
    required this.pack,
    required this.setup,
    this.customMap,
    this.mod,
    this.resume,
  });

  final GameData data;
  final AssetPack pack;
  final GameSetup setup;
  final MapDefinition? customMap;
  final ActiveMod? mod;

  /// The stored game the first game rebuilds; a restart plays [setup] anew.
  final GameInProgress? resume;

  @override
  State<_GameRoot> createState() => _GameRootState();
}

class _GameRootState extends State<_GameRoot> {
  int _game = 0;

  @override
  Widget build(BuildContext context) {
    Widget view({GameSession? resumed}) => _GameView(
      key: ValueKey(_game),
      locale: uiLocale(context),
      data: widget.data,
      pack: widget.pack,
      setup: widget.setup,
      customMap: widget.customMap,
      mod: widget.mod,
      resumed: resumed,
      onRestart: () => setState(() => _game++),
    );
    final stored = widget.resume;
    if (stored == null || _game > 0) return view();
    return _ResumeLoader(
      data: widget.data,
      game: stored,
      builder: (session) => view(resumed: session),
    );
  }
}

/// Rebuilds a stored game in progress by replaying its commands on a fresh
/// session ([SessionReplay]), a slice per frame with a progress bar, then
/// hands the session to [builder]. When the rebuilt game does not match the
/// stored one (the app or its data changed since), or cannot be rebuilt at
/// all, it says so and offers to resume anyway (when it can) or discard.
class _ResumeLoader extends ConsumerStatefulWidget {
  const _ResumeLoader({required this.data, required this.game, required this.builder});

  final GameData data;
  final GameInProgress game;
  final Widget Function(GameSession session) builder;

  /// Steps replayed per frame.
  static const int stepsPerSlice = 4000;

  @override
  ConsumerState<_ResumeLoader> createState() => _ResumeLoaderState();
}

class _ResumeLoaderState extends ConsumerState<_ResumeLoader> {
  GameSession? _session;
  double _progress = 0;
  bool _ready = false;
  bool _mismatch = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_rebuild());
  }

  Future<void> _rebuild() async {
    final game = widget.game;
    final GameSession session;
    try {
      session = GameSession(
        data: widget.data,
        config: savedGameConfig(widget.data, game),
        registry: ref.read(rulesRegistryProvider),
      );
      final replay = SessionReplay(session, game.commands, game.tick);
      while (!replay.advance(_ResumeLoader.stepsPerSlice)) {
        if (!mounted) return;
        setState(() => _progress = game.tick == 0 ? 1 : replay.done / game.tick);
        await Future<void>.delayed(Duration.zero);
      }
    } on Object catch (e, st) {
      _log.error('resuming the game in progress failed', error: e, stackTrace: st);
      if (mounted) setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _mismatch = session.stateHash() != game.stateHash;
      _ready = !_mismatch;
    });
  }

  Future<void> _discard() async {
    await ref.read(gameInProgressProvider.notifier).clear();
    if (mounted) context.go('/mode');
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (_ready && session != null) return widget.builder(session);
    final data = widget.data;
    final text = Theme.of(context).textTheme;
    final Widget body;
    if (_failed || _mismatch) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.tr(context, _failed ? 'ui.resume.failed' : 'ui.resume.mismatch'),
            textAlign: TextAlign.center,
            style: text.bodyLarge?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: _discard,
                child: Text(data.tr(context, 'ui.resume.discard')),
              ),
              if (!_failed)
                FilledButton(
                  onPressed: () => setState(() => _ready = true),
                  child: Text(data.tr(context, 'ui.resume.anyway')),
                ),
            ],
          ),
        ],
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            data.tr(context, 'ui.resume.loading'),
            style: text.titleMedium?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 12),
          SizedBox(width: 220, child: LinearProgressIndicator(value: _progress)),
        ],
      );
    }
    return Center(
      child: Padding(padding: const EdgeInsets.all(24), child: body),
    );
  }
}

class _GameView extends ConsumerStatefulWidget {
  const _GameView({
    super.key,
    required this.data,
    required this.pack,
    required this.setup,
    required this.onRestart,
    required this.locale,
    this.customMap,
    this.mod,
    this.resumed,
  });

  final GameData data;
  final AssetPack pack;
  final GameSetup setup;
  final VoidCallback onRestart;

  /// A stored game in progress, rebuilt: played on instead of a new game.
  final GameSession? resumed;

  /// The interface language ([uiLocale]): the view model's messages and
  /// names are made in it.
  final String locale;

  /// The player map [setup] names, read from the library.
  final MapDefinition? customMap;

  /// The mod [data] has applied, if any.
  final ActiveMod? mod;

  @override
  ConsumerState<_GameView> createState() => _GameViewState();
}

class _GameViewState extends ConsumerState<_GameView> implements PlacementInput {
  /// The running game: session, view model, Flame game, sound, haptics,
  /// effects and progress.
  late final GameRuntime _runtime;
  SessionGameViewModel get _viewModel => _runtime.viewModel;
  OnslaughtFlameGame get _game => _runtime.game;
  ValueNotifier<EffectSettings> get _effects => _runtime.effects;

  /// A custom game: it records no progress and is labelled so.
  bool get _custom => _runtime.custom;
  final GlobalKey _gameKey = GlobalKey();
  final HudKeys _keys = HudKeys();

  /// The game's skin ([uiSkinProvider]: its rule set, or the
  /// `ENHANCED_SKIN` flag).
  UiSkin get _skin => _runtime.skin;

  /// The HUD layout for the current screen; resolved when the screen's
  /// size, safe area or language changes ([didChangeDependencies]).
  HudLayout? _layout;

  /// A tray drag is in progress.
  bool _dragging = false;

  /// The drag in progress was cancelled by a rotation: ignore it until it
  /// ends, so its end cannot build a turret.
  bool _dragIgnored = false;

  /// The game paused itself for an unsupported window shape.
  bool _autoPaused = false;

  /// Where on screen the selected turret was when its panel opened (the
  /// panel opens away from it); null until a turret is selected. It keeps
  /// its last place after the turret is deselected, so the closing panel
  /// fades out against the edge it opened on rather than jumping to the
  /// default (bottom) one.
  final ValueNotifier<Offset?> _sheetAt = ValueNotifier(null);
  int? _sheetUid;

  GameData get _data => widget.data;
  GameConfig get _config => _runtime.config;
  bool get _tutorial => _config.mode == GameConfig.tutorialMode;

  @override
  void initState() {
    super.initState();
    _runtime = GameRuntime(
      data: _data,
      pack: widget.pack,
      setup: widget.setup,
      settings: ref.read(settingsProvider).value ?? const Settings(),
      profile: ref.read(rulesProfileProvider),
      registry: ref.read(rulesRegistryProvider),
      skin: ref.read(uiSkinProvider),
      audioSink: ref.read(audioSinkProvider),
      hapticSink: ref.read(hapticSinkProvider),
      locale: widget.locale,
      readProfile: () => ref.read(profileProvider).value,
      saveProfile: (edit) => unawaited(ref.read(profileProvider.notifier).change(edit)),
      customMap: widget.customMap,
      mod: widget.mod,
      resumed: widget.resumed,
    );
    _viewModel.selection.addListener(_onSelection);
    _endSub = _viewModel.events.listen(_onGameEvent);
    // A game the app is hidden from is saved where it is: the system may
    // end the app before it comes back.
    _lifecycle = AppLifecycleListener(
      onHide: () => _storeProgress(pause: false),
      onDetach: () => _storeProgress(pause: false),
    );
  }

  late final StreamSubscription<GameEvent> _endSub;
  late final AppLifecycleListener _lifecycle;

  /// A game that ends (lost, or won) is no longer one to come back to.
  void _onGameEvent(GameEvent e) {
    if (e is GameOver || e is GameWon) _storeProgress(pause: false);
  }

  /// Stores this game as the game in progress, paused first when [pause]; or,
  /// when it is over and was the stored one, forgets that. A tutorial (not
  /// resumable) leaves the stored game alone.
  void _storeProgress({required bool pause}) {
    if (!_runtime.resumable) return;
    if (pause) _viewModel.pauseNow();
    final game = _runtime.inProgress();
    final stored = ref.read(gameInProgressProvider.notifier);
    if (game != null) {
      _runtime.saved = true;
      unawaited(stored.save(game));
    } else if (_runtime.saved) {
      _runtime.saved = false;
      unawaited(stored.clear());
    }
  }

  /// Leaves for the main menu. A game that is not over is paused and stored
  /// first, so Play offers to resume it.
  void _leave() {
    _storeProgress(pause: true);
    context.go('/');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveLayout();
  }

  @override
  void didUpdateWidget(_GameView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _viewModel.locale = widget.locale;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_endSub.cancel());
    _viewModel.selection.removeListener(_onSelection);
    _sheetAt.dispose();
    _runtime.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ settings

  /// The in-game settings (`GameSettings`): the game pauses while they are
  /// open; closing applies the wave settings to this game
  /// (`settingsApply`) and saves them.
  Future<void> _openSettings() async {
    final wasPaused = _viewModel.hud.value.paused;
    if (!wasPaused) _viewModel.dispatch(const SetPaused(true));
    var edited = ref.read(settingsProvider).value ?? const Settings();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_data.tr(context, 'ui.game.settings')),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        // 420 wide, or the dialog's width on a narrow phone.
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: StatefulBuilder(
              builder: (context, setDialogState) => SettingsForm(
                settings: edited,
                data: _data,
                showSpeed: false,
                showGround: _skin.sharpGroundOffered,
                onChanged: (s) => setDialogState(() => edited = s),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_data.tr(context, 'ui.common.done')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    _runtime.applySettings(edited);
    _viewModel.dispatch(
      SetWaveSettings(
        spacingMs: (edited.waveSpacingS ?? _data.waves.waveSpacingMs / 1000) * 1000,
        follow: edited.waveFollow,
      ),
    );
    if (!wasPaused) _viewModel.dispatch(const SetPaused(false));
    await ref.read(settingsProvider.notifier).save(edited);
  }

  // ------------------------------------------------------------ tutorial

  /// "Show me" on tutorial page [page]: runs its action and, when its arrow
  /// points into the map, pans a filled (portrait) view so the point shows.
  void _tutorialShow(int page) {
    _viewModel.dispatch(TutorialShow(page));
    final pointer = _data.tutorialPages()[page].pointer;
    final at = pointer == null ? null : _tutorialWorldPoint(pointer);
    if (at != null && _game.rig.panToShow(Offset(at.x, at.y))) _game.cameraChanged();
  }

  /// The world point a tutorial pointer names, if it names one.
  Vec2? _tutorialWorldPoint(String pointer) {
    final turrets = _viewModel.world.turrets;
    return switch (pointer) {
      'RoadManager.Waypoint1' => _viewModel.map.road.first,
      'TurretManager.turrets[0]' => turrets.isEmpty ? null : turrets.first.position,
      _ => null,
    };
  }

  /// Where a tutorial page's arrow points (`GameTutorial.tutorialBuild`
  /// `show` targets, mapped to this HUD).
  Rect? _tutorialTarget(String pointer) {
    Rect? keyed(GlobalKey key) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return null;
      return box.localToGlobal(Offset.zero) & box.size;
    }

    Rect? world(Vec2? p) {
      final box = _gameKey.currentContext?.findRenderObject() as RenderBox?;
      if (p == null || box == null) return null;
      final at = box.localToGlobal(_game.rig.worldToScreen(Offset(p.x, p.y)));
      return Rect.fromCenter(center: at, width: 24, height: 24);
    }

    return switch (pointer) {
      'RoadManager.Waypoint1' || 'TurretManager.turrets[0]' => world(_tutorialWorldPoint(pointer)),
      'GamePause' => keyed(_keys.pause),
      'WaveClock' => keyed(_keys.waveClock),
      'BuildPanel.WeaponRack' => keyed(_keys.tray),
      'Cash' => keyed(_keys.cash),
      'UpgradePanel.DamageCost' || 'UpgradePanel.RangeCost' => keyed(_keys.sheet),
      'TurretInfoPoint' => keyed(_keys.messages),
      'TurretInfo.ButtonGame' => keyed(_keys.exit),
      _ => null,
    };
  }

  /// A tray drag: over the map the ghost follows the finger (on touch, the
  /// skin's lift above it); over the tray or the stats it hides (releasing
  /// there cancels).
  @override
  void dragTo(String turretId, Offset globalPosition, {bool touch = false, bool start = false}) {
    if (start) {
      _dragging = true;
      _dragIgnored = false;
    }
    if (_dragIgnored) return;
    final box = _gameKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final local = box.globalToLocal(globalPosition);
    final overHud = _layout?.isOverHud(local) ?? false;
    final at = touch ? local - Offset(0, _skin.ghostLiftPt) : local;
    _viewModel.select(null);
    _viewModel.previewPlacement(turretId, overHud ? null : _game.screenToWorld(at));
  }

  /// The finger lifted: over the map, builds a valid ghost, or with drop
  /// and lock drops and locks the ghost there for Place; elsewhere cancels.
  @override
  void dragEnd() {
    _dragging = false;
    if (_dragIgnored) {
      _dragIgnored = false;
      return;
    }
    final p = _viewModel.placement.value;
    if (p?.at == null) {
      _viewModel.cancelPlacement();
    } else if (_runtime.placementMode.value == PlacementMode.dropAndLock) {
      _viewModel.previewPlacement(p!.turretId, p.at, moving: p.moving, locked: true);
    } else {
      _viewModel.commitPlacement();
    }
  }

  // ------------------------------------------------------------ layout

  /// The screen turned (or a window changed shape) into another layout: a
  /// tray drag in progress is cancelled (its end must not build); an armed
  /// tap-to-build stays armed, a locked ghost stays locked (the camera
  /// panning just enough to show it) and a selection stays selected, the camera
  /// panning just enough to show its turret and its panel placed again in
  /// the new layout. An unsupported shape pauses the game until the window
  /// is playable again, unless the player had paused it.
  void _onLayoutChanged(HudLayout previous, HudLayout next) {
    if (_dragging) {
      _dragIgnored = true;
      _dragging = false;
    }
    final cancel = _dragIgnored;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (cancel) _viewModel.cancelPlacement();
      final hud = _viewModel.hud.value;
      if (next.kind == HudLayoutKind.unsupported) {
        if (!hud.paused && !hud.gameOver) {
          _autoPaused = true;
          _viewModel.dispatch(const SetPaused(true));
        }
      } else if (_autoPaused) {
        _autoPaused = false;
        if (hud.paused) _viewModel.dispatch(const SetPaused(false));
      }
      _placeSheet(reveal: true);
      _revealLockedGhost();
    });
  }

  /// Pans just enough that a dropped-and-locked ghost shows in the map area.
  void _revealLockedGhost() {
    final p = _viewModel.placement.value;
    final at = p?.at;
    if (p == null || !p.locked || at == null) return;
    final pad = _layout!.turretWorldPx / 2 * _game.rig.zoom + 16;
    if (_game.rig.panToShow(Offset(at.x, at.y), pad: pad)) _game.cameraChanged();
  }

  void _onSelection() {
    final uid = _viewModel.selection.value?.uid;
    if (uid == _sheetUid) return;
    _sheetUid = uid;
    if (uid != null) _placeSheet();
  }

  /// Opens the selected turret's panel away from where the turret shows;
  /// with the Enhanced skin, once it is laid out, pans just enough that the
  /// panel does not cover the turret. With [reveal] (after a turn, which
  /// can leave the turret off screen) it first pans just enough that the
  /// turret shows in the map area.
  void _placeSheet({bool reveal = false}) {
    final uid = _sheetUid;
    final turret = uid == null
        ? null
        : _viewModel.world.turrets.where((t) => t.uid == uid).firstOrNull;
    if (turret == null) return;
    final world = Offset(turret.position.x, turret.position.y);
    final rig = _game.rig;
    final pad = _layout!.turretWorldPx / 2 * rig.zoom + 16;
    if (reveal && rig.panToShow(world, pad: pad)) _game.cameraChanged();
    _sheetAt.value = rig.worldToScreen(world);
    if (_skin != UiSkin.enhanced) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sheet = _keys.sheet.currentContext?.findRenderObject() as RenderBox?;
      final game = _gameKey.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || sheet == null || game == null || !sheet.hasSize) return;
      final rect = game.globalToLocal(sheet.localToGlobal(Offset.zero)) & sheet.size;
      if (_game.rig.ensureVisible(world, rect)) _game.cameraChanged();
    });
  }

  // The system back leaves for the menu, like the stats bar's exit: the game
  // is paused and stored, to resume from Play.
  @override
  Widget build(BuildContext context) => SystemBack(onBack: _leave, child: _buildGame(context));

  /// Resolves the HUD layout for the screen as it is now, fitting the data's
  /// play area, and hands it (and the interface language) to the Flame
  /// game; a change of layout kind goes to [_onLayoutChanged].
  void _resolveLayout() {
    final previous = _layout;
    final world = _data.world;
    final layout = _layout = HudLayout.resolve(
      MediaQuery.sizeOf(context),
      MediaQuery.paddingOf(context),
      skin: _skin,
      previous: previous,
      world: Size(world.playWidth, world.playHeight),
      turretWorldPx: world.placement.turretSpacing,
    );
    _game
      ..locale = uiLocale(context)
      ..setLayout(layout);
    if (previous != null && previous.kind != layout.kind) {
      _onLayoutChanged(previous, layout);
    }
  }

  Widget _buildGame(BuildContext context) {
    final flags = ref.watch(featureFlagsProvider);
    final layout = _layout!;
    final screen = layout.screen;
    final portrait = layout.kind == HudLayoutKind.portrait;
    final rails = layout.kind == HudLayoutKind.rails;
    final map = layout.map;
    final toasts = layout.toasts(tutorial: _tutorial);
    return GameWidget<OnslaughtFlameGame>(
      key: _gameKey,
      game: _game,
      loadingBuilder: (context) => Center(
        child: CircularProgressIndicator(semanticsLabel: _data.tr(context, 'ui.game.loading')),
      ),
      overlayBuilderMap: {
        GameOverlays.stats: (context, game) => Positioned.fromRect(
          rect: layout.stats,
          child: StatsBar(
            viewModel: _viewModel,
            onExit: _leave,
            onSettings: _openSettings,
            keys: _keys,
            axis: layout.statsAxis,
            inset: layout.statsInset,
          ),
        ),
        GameOverlays.tray: (context, game) => Positioned.fromRect(
          rect: layout.tray,
          child: KeyedSubtree(
            key: _keys.tray,
            child: TowerTray(
              viewModel: _viewModel,
              input: this,
              pack: widget.pack,
              effects: _effects,
              axis: layout.trayAxis,
              inset: layout.trayInset,
            ),
          ),
        ),
        GameOverlays.sheet: (context, game) => ValueListenableBuilder<Offset?>(
          valueListenable: _sheetAt,
          builder: (context, at, _) {
            final edge = layout.sheetEdgeFor(at);
            final area = layout.panelFor(at);
            final sheet = KeyedSubtree(
              key: _keys.sheet,
              child: TurretSheet(
                viewModel: _viewModel,
                pack: widget.pack,
                effects: _effects,
                edge: edge,
                inset: layout.panelInset(edge),
              ),
            );
            return switch (edge) {
              SheetEdge.bottom => Positioned(
                left: area.left,
                right: screen.width - area.right,
                bottom: 0,
                child: sheet,
              ),
              SheetEdge.top => Positioned(
                left: area.left,
                right: screen.width - area.right,
                top: area.top,
                child: sheet,
              ),
              SheetEdge.left || SheetEdge.right => Positioned.fromRect(
                rect: area,
                child: Align(
                  alignment: edge == SheetEdge.left ? Alignment.topLeft : Alignment.topRight,
                  child: sheet,
                ),
              ),
            };
          },
        ),
        GameOverlays.placementHint: (context, game) => Positioned(
          left: portrait || rails ? map.left : 0,
          right: screen.width - (portrait || rails ? map.right : layout.tray.left),
          bottom: portrait ? screen.height - map.bottom + 8 : 8,
          child: Center(
            child: PlacementHint(viewModel: _viewModel, mode: _runtime.placementMode),
          ),
        ),
        GameOverlays.messages: (context, game) => Positioned(
          top: toasts.top,
          left: _tutorial || portrait || rails ? toasts.left : 0,
          right: screen.width - toasts.right,
          child: Center(
            child: KeyedSubtree(
              key: _keys.messages,
              child: MessageToasts(viewModel: _viewModel),
            ),
          ),
        ),
        GameOverlays.objectives: (context, game) => Positioned(
          top: map.top + 6,
          left: map.left + 8,
          child: ObjectiveBadges(viewModel: _viewModel),
        ),
        GameOverlays.tutorial: (context, game) => Positioned.fill(
          child: TutorialPanel(
            pages: _data.tutorialPages(locale: uiLocale(context)),
            window: layout.tutorialWindow,
            resolve: _tutorialTarget,
            onShow: _tutorialShow,
            onClose: () => context.go('/'),
          ),
        ),
        GameOverlays.gameOver: (context, game) =>
            GameOverPanel(viewModel: _viewModel, onRestart: widget.onRestart, onMenu: _leave),
        // In the map area's bottom-left corner: clear of the tray strip in
        // portrait and of the stats rail in rails.
        GameOverlays.cameraDebug: (context, game) => Positioned.fromRect(
          rect: map,
          child: CameraDebugOverlay(controls: game),
        ),
        GameOverlays.customLabel: (context, game) => Positioned(
          left: map.left + 8,
          bottom: screen.height - map.bottom + 4,
          child: _CustomLabel(data: _data, mod: widget.mod),
        ),
        GameOverlays.unsupported: (context, game) => layout.kind == HudLayoutKind.unsupported
            ? Positioned.fill(child: UnsupportedShape(data: _data))
            : const SizedBox.shrink(),
      },
      initialActiveOverlays: [
        // First, so every other overlay draws over it.
        if (widget.mod != null || _custom) GameOverlays.customLabel,
        GameOverlays.stats,
        GameOverlays.tray,
        GameOverlays.sheet,
        GameOverlays.placementHint,
        GameOverlays.messages,
        if (_config.mode == GameConfig.challengeMode) GameOverlays.objectives,
        GameOverlays.gameOver,
        if (_tutorial) GameOverlays.tutorial,
        if (flags.debugOverlay) GameOverlays.cameraDebug,
        GameOverlays.unsupported,
      ],
    );
  }
}

/// Marks a custom game ("Custom game"), with the active mod's name and
/// signature when there is one (`GameManager.watermarkUpdate`: `"Mod: " +
/// name + ", signature: " + md5`), so a modded or home-made game is never
/// mistaken for a standard one.
class _CustomLabel extends StatelessWidget {
  const _CustomLabel({required this.data, this.mod});

  final GameData data;
  final ActiveMod? mod;

  @override
  Widget build(BuildContext context) {
    final m = mod;
    final text = m == null
        ? data.tr(context, 'ui.game.custom')
        : data.tr(context, 'ui.game.customMod', {
            'name': data.modName(context, m.name),
            'signature': m.signature,
          });
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ),
    );
  }
}
