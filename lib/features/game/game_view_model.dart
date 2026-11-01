import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

import 'fixed_step_driver.dart';
import 'game_snapshots.dart';
import 'placement_preview.dart';
import 'turret_panel_builder.dart';

export 'game_snapshots.dart';

/// Read-only access to the entities, for the Flame layer only (it draws
/// them every frame). Widgets never read this (rule R2).
abstract interface class WorldView {
  List<Creep> get creeps;
  List<Turret> get turrets;
  List<Projectile> get projectiles;
  List<Blast> get blasts;
  List<ShockwaveWalker> get walkers;

  /// Game time in ms (frozen while paused), for effects timed on it.
  double get nowMs;
}

/// An empty world (tests, goldens).
class EmptyWorldView implements WorldView {
  const EmptyWorldView();
  @override
  List<Creep> get creeps => const [];
  @override
  List<Turret> get turrets => const [];
  @override
  List<Projectile> get projectiles => const [];
  @override
  List<Blast> get blasts => const [];
  @override
  List<ShockwaveWalker> get walkers => const [];
  @override
  double get nowMs => 0;
}

/// The UI's only window onto a game (tenet 4): typed listenable snapshots
/// plus a command sink. HUD widgets depend on this, never on the simulation
/// or on Flame; tests use `FakeGameViewModel`.
abstract interface class GameViewModel {
  /// The data the game runs on (names, costs, strings for the HUD).
  GameData get data;

  /// The map being played.
  MapDefinition get map;

  /// The rule set of this game (decides HUD conveniences such as the speed
  /// button and tap-to-deselect).
  RulesProfile get profile;

  ValueListenable<HudState> get hud;

  /// Buildable turrets, in tray order.
  ValueListenable<List<TrayItem>> get tray;

  /// The selected turret, or null.
  ValueListenable<TurretPanel?> get selection;

  /// The ghost while building or moving, or null.
  ValueListenable<PlacementPreview?> get placement;

  /// Set once the game is lost or won (a challenge passed, the tutorial
  /// beaten); cleared when a won game goes on in freeplay.
  ValueListenable<GameOverSummary?> get gameOver;

  /// A challenge's target badges, in the original's order (time, waves,
  /// kills); empty for other games.
  ValueListenable<List<ObjectiveBadge>> get objectives;

  /// Messages so far, oldest first (the original's message window).
  ValueListenable<List<GameMessage>> get messages;

  /// The Targeter whose joins the player is editing (the joiner), or null.
  /// While set, a tap on a turret joins it or lets it go.
  ValueListenable<int?> get joining;

  /// Starts editing Targeter [uid]'s joins (null stops). UI state.
  void joinFrom(int? uid);

  /// Entities for the Flame layer.
  WorldView get world;

  /// Simulation events, for audio, effects and toasts.
  Stream<GameEvent> get events;

  /// Sends [command] to the game.
  void dispatch(GameCommand command);

  /// Selects turret [uid] (null deselects). UI state, not a game command.
  void select(int? uid);

  /// The turret whose footprint contains world point [at], if any; with
  /// [minRadius] (world px) a tap that close also picks it, nearest first
  /// (the Enhanced skin's screen-space hit zone; 0 = the footprint only).
  int? turretAt(Vec2 at, {double minRadius = 0});

  /// Starts or moves the ghost of [turretId] to [at] (null = off the map);
  /// [moving] is the uid of a turret being moved; [locked] drops and locks
  /// it there (drop and lock; ignored off the map).
  void previewPlacement(String turretId, Vec2? at, {int? moving, bool locked = false});

  /// Places the ghost if it is valid (builds or moves) and clears it.
  /// Returns whether a command was sent.
  bool commitPlacement();

  /// Drops the ghost without placing.
  void cancelPlacement();
}

/// [GameViewModel] over a live [GameSession]. The presentation layer calls
/// [advance] with real frame time; a fixed-step accumulator keeps the
/// simulation deterministic regardless of frame rate.
class SessionGameViewModel implements GameViewModel {
  /// [locale] is the interface language its messages and names are in.
  SessionGameViewModel(this.session, {this._locale = 'en'})
    : _driver = FixedStepDriver(
        stepSeconds: 1 / session.data.rules.tickHz,
        maxStepsPerFrame: maxStepsPerFrame,
      ) {
    _world = _SessionWorld(session);
    if (session.config.mode == GameConfig.tutorialMode) {
      // `GameManagerTutorial.onLoad` clears the welcome lines for its own.
      _message(_text('flow.tutorialStart'));
    } else {
      // `GameManager.setupGame`: the welcome lines, without the alert.
      _message(_text('message.welcome'), alert: false);
      _message(_text('message.attackersComing'), alert: false);
    }
    _refresh();
  }

  final GameSession session;

  /// The interface language (a `strings/<locale>.json` code). Messages
  /// already shown keep the language they were made in; names follow.
  String get locale => _locale;
  set locale(String value) {
    if (value == _locale) return;
    _locale = value;
    _refresh();
  }

  String _locale;
  final FixedStepDriver _driver;
  late final _SessionWorld _world;
  final ValueNotifier<HudState> _hud = ValueNotifier(
    const HudState(cash: 0, lives: 0, kills: 0, wave: 0, paused: false, speed: 1),
  );
  final ValueNotifier<List<TrayItem>> _tray = ValueNotifier(const []);
  final ValueNotifier<TurretPanel?> _selection = ValueNotifier(null);
  final ValueNotifier<PlacementPreview?> _placement = ValueNotifier(null);
  final ValueNotifier<GameOverSummary?> _gameOver = ValueNotifier(null);
  final ValueNotifier<List<GameMessage>> _messages = ValueNotifier(const []);
  final ValueNotifier<int?> _joining = ValueNotifier(null);
  final ValueNotifier<List<ObjectiveBadge>> _objectives = ValueNotifier(const []);
  final Map<String, BadgeState> _badgeStates = {};
  final StreamController<GameEvent> _events = StreamController.broadcast();
  int? _selectedUid;

  /// Upper bound on steps per frame so a long stall cannot freeze the UI.
  static const int maxStepsPerFrame = 8;

  @override
  GameData get data => session.data;

  @override
  MapDefinition get map => session.map;

  @override
  RulesProfile get profile => session.config.profile;

  @override
  ValueListenable<HudState> get hud => _hud;

  @override
  ValueListenable<List<TrayItem>> get tray => _tray;

  @override
  ValueListenable<TurretPanel?> get selection => _selection;

  @override
  ValueListenable<PlacementPreview?> get placement => _placement;

  @override
  ValueListenable<GameOverSummary?> get gameOver => _gameOver;

  @override
  ValueListenable<List<GameMessage>> get messages => _messages;

  @override
  ValueListenable<int?> get joining => _joining;

  @override
  ValueListenable<List<ObjectiveBadge>> get objectives => _objectives;

  bool get _challenge => session.config.mode == GameConfig.challengeMode;

  /// Posts a message to the log and as a toast (progress announcements
  /// from outside the game, e.g. a mode unlocked).
  void notify(String text) => _message(text);

  @override
  void joinFrom(int? uid) {
    final t = uid == null ? null : session.turretByUid(uid);
    final ok = t != null && t.active && t.def.specials.contains(TargeterSpecial.specialId);
    _joining.value = ok ? uid : null;
    _selection.value = _panel();
  }

  @override
  WorldView get world => _world;

  @override
  Stream<GameEvent> get events => _events.stream;

  @override
  void dispatch(GameCommand command) => session.enqueue(command);

  /// Pauses the game at once: sends [SetPaused] and runs the step that
  /// applies it (no game time passes), for a game about to be saved and
  /// left. Nothing happens when it is already paused or over.
  void pauseNow() {
    if (session.clock.paused || session.gameOver) return;
    dispatch(const SetPaused(true));
    for (final e in session.step()) {
      _onEvent(e);
      _events.add(e);
    }
    _refresh();
  }

  /// Advances the simulation by [dtSeconds] of real time.
  void advance(double dtSeconds) {
    final steps = _driver.advance(dtSeconds, () {
      for (final e in session.step()) {
        _onEvent(e);
        _events.add(e);
      }
    });
    if (steps > 0) _refresh();
  }

  /// What event [e] changes in the HUD beyond what [_refresh] reads from the
  /// session after the step: the end dialog, badge states, messages and
  /// the selection or joiner when their turret goes away. Every event is
  /// named so a new one has to be decided on here.
  void _onEvent(GameEvent e) {
    switch (e) {
      case GameOver():
        _gameOver.value = GameOverSummary(
          wave: e.wave,
          kills: e.kills,
          shots: e.shots,
          spent: e.spent,
          score: e.score,
          // A challenge played on in freeplay ends as a plain game.
          end: _challenge && !session.freeplay ? GameEnd.challengeFailed : GameEnd.gameOver,
          seconds: session.clock.nowMs ~/ 1000,
        );
      case GameWon():
        _won(e);
      case FreeplayStarted():
        _gameOver.value = null;
      case ObjectiveReached(:final kind):
        _badgeStates[kind] = BadgeState.reached;
        if (kind == ChallengeObjective.waves) _message(_text('flow.waveLimitHit'));
        if (kind == ChallengeObjective.kills) _message(_text('flow.killTargetHit'));
      case ObjectiveMissed(:final kind):
        _badgeStates[kind] = BadgeState.missed;
      case TurretSold(:final uid):
        if (uid == _selectedUid) _selectedUid = null;
        if (uid == _joining.value) _joining.value = null;
      case TurretConsumed(:final uid):
        if (uid == _selectedUid) _selectedUid = null;
      case CombonlyChanged(:final consumed):
        if (consumed.contains(_joining.value)) _joining.value = null;
        if (consumed.contains(_selectedUid)) _selectedUid = null;
      case WeaponUnlocked(:final turret):
        final name = data.turretName(turret, locale: _locale);
        _message(_text('message.weaponAvailable', {'name': name}));
      // Nothing beyond the refresh: the HUD reads cash, lives, kills, waves,
      // the clock and turret stats from the session after the step, and
      // audio, haptics and the Flame layer listen to [events] themselves.
      case SessionStarted() ||
          PausedChanged() ||
          SpeedChanged() ||
          CommandRejected() ||
          WaveStarted() ||
          CreepSpawned() ||
          CreepKilled() ||
          BaseHit() ||
          TutorialCashSet() ||
          WaveSettingsChanged() ||
          TurretBuilt() ||
          TurretUpgraded() ||
          TurretMoved() ||
          TargetModeChanged() ||
          TurretFired() ||
          TurretJoined() ||
          FreakoutChanged() ||
          ComboFired() ||
          BlastStarted() ||
          BlackHoleOpened() ||
          CreepSwallowed():
        break;
    }
  }

  @override
  void select(int? uid) {
    final t = uid == null ? null : session.turretByUid(uid);
    // Turrets being consumed (and a plate taking on its weapon) cannot be
    // clicked (`Turret.onPress` checks `active`).
    _selectedUid = t != null && t.active ? uid : null;
    if (_joining.value != null && _joining.value != _selectedUid) _joining.value = null;
    _selection.value = _panel();
  }

  @override
  int? turretAt(Vec2 at, {double minRadius = 0}) {
    final r = math.max(data.world.placement.turretSpacing / 2, minRadius);
    int? best;
    var bestD = double.infinity;
    for (final t in session.turrets) {
      if (!t.active) continue;
      final d = t.position.distanceTo(at);
      if (d <= r && d < bestD) {
        bestD = d;
        best = t.uid;
      }
    }
    return best;
  }

  @override
  void previewPlacement(String turretId, Vec2? at, {int? moving, bool locked = false}) {
    final preview = placementPreview(session, turretId, at, moving: moving, locked: locked);
    if (preview != null) _placement.value = preview;
  }

  @override
  bool commitPlacement() {
    final command = placementCommand(_placement.value);
    _placement.value = null;
    if (command == null) return false;
    dispatch(command);
    return true;
  }

  @override
  void cancelPlacement() => _placement.value = null;

  /// `GameManager.gameWin`: a challenge is passed (its message) or the
  /// tutorial beaten (its unlock is announced by the profile); either shows
  /// the win dialog.
  void _won(GameWon e) {
    final summary = GameOverSummary(
      wave: e.wave,
      kills: e.kills,
      shots: e.shots,
      spent: e.spent,
      score: e.score,
      end: _challenge ? GameEnd.challengePassed : GameEnd.tutorialComplete,
      seconds: session.clock.nowMs ~/ 1000,
      canContinue: profile.continueAfterWin,
    );
    if (!_challenge) {
      _gameOver.value = summary;
      return;
    }
    final o = session.objectives;
    final text = StringBuffer(_text('flow.challengeBeaten'));
    if (o.killTarget != null) {
      text.write(_text('flow.challengeBeatenKills'));
    } else if (o.waveLimit != null) {
      text.write(_text('flow.challengeBeatenWaves'));
    }
    if (o.timeLimitMs != null) text.write(_text('flow.challengeBeatenTime'));
    text.write(_text('flow.challengeBeatenEnd'));
    _message(text.toString());
    _gameOver.value = summary;
  }

  /// The string [key] in [locale] with each `{name}` in [args] filled in.
  String _text(String key, [Map<String, Object?> args = const {}]) {
    var out = data.text(key, locale: _locale);
    args.forEach((k, v) => out = out.replaceAll('{$k}', '$v'));
    return out;
  }

  void _message(String text, {bool alert = true}) {
    final list = _messages.value;
    _messages.value = [...list, GameMessage(seq: list.length, text: text, alert: alert)];
  }

  void dispose() {
    _joining.dispose();
    _messages.dispose();
    _hud.dispose();
    _tray.dispose();
    _selection.dispose();
    _placement.dispose();
    _gameOver.dispose();
    _objectives.dispose();
    unawaited(_events.close());
  }

  void _refresh() {
    final s = session;
    _hud.value = HudState(
      cash: s.cash,
      lives: s.lives,
      kills: s.kills,
      wave: s.waves.wave,
      paused: s.clock.paused,
      speed: s.clock.speed,
      nextWaveSeconds: waveClockSeconds(s.msUntilNextWave.clamp(0, double.infinity)),
      waveSpacingSeconds: s.waveSpacingMs / 1000,
      gameOver: s.gameOver,
    );
    final tray = [
      for (final def in data.turrets.values)
        if (s.isBuildable(def))
          TrayItem(
            id: def.id,
            name: data.turretName(def.id, locale: _locale),
            cost: def.cost,
            icon: def.art.icon,
            affordable: s.cash >= def.cost,
            locked: !s.isAvailable(def),
            unlockKills: def.unlockKills,
            killsToUnlock: s.isAvailable(def) ? 0 : math.max(0, def.unlockKills - s.kills),
          ),
    ];
    // A list compares by identity, so a fresh one would notify (and rebuild
    // the whole tray) on every frame; the items compare by value.
    if (!listEquals(tray, _tray.value)) _tray.value = tray;
    _selection.value = _panel();
    final p = _placement.value;
    if (p != null) previewPlacement(p.turretId, p.at, moving: p.moving, locked: p.locked);
    if (_challenge) {
      final badges = _badges();
      if (!listEquals(badges, _objectives.value)) _objectives.value = badges;
    }
  }

  /// The challenge badges (`timeLimitUpdate`, `waveLimitUpdate`,
  /// `killTargetUpdate`).
  List<ObjectiveBadge> _badges() {
    final s = session;
    final o = s.objectives;
    String two(int v) => v.toString().padLeft(2, '0');
    final left = s.timeLimitSecondsLeft;
    return [
      if (left != null)
        ObjectiveBadge(
          kind: ChallengeObjective.time,
          text: '${two(left ~/ 60)}:${two(left % 60)}',
          state: _badgeStates[ChallengeObjective.time] ?? BadgeState.pending,
        ),
      if (o.waveLimit case final limit?)
        ObjectiveBadge(
          kind: ChallengeObjective.waves,
          text: '${s.waves.wave}/$limit',
          state:
              _badgeStates[ChallengeObjective.waves] ??
              (s.waves.wave >= limit ? BadgeState.reached : BadgeState.pending),
          milestone: s.waves.wave ~/ _waveFlashEvery,
        ),
      if (o.killTarget case final target?)
        ObjectiveBadge(
          kind: ChallengeObjective.kills,
          text: '${s.kills}/$target',
          state:
              _badgeStates[ChallengeObjective.kills] ??
              (s.kills >= target ? BadgeState.reached : BadgeState.pending),
          milestone: s.kills ~/ _killFlashEvery,
        ),
    ];
  }

  TurretPanel? _panel() =>
      buildTurretPanel(session, _selectedUid, locale: _locale, joining: _joining.value);

  /// The badges flash every 50 waves and every 100 kills (presentation).
  static const int _waveFlashEvery = 50;
  static const int _killFlashEvery = 100;
}

class _SessionWorld implements WorldView {
  _SessionWorld(this.session);
  final GameSession session;
  @override
  List<Creep> get creeps => session.creeps;
  @override
  List<Turret> get turrets => session.turrets;
  @override
  List<Projectile> get projectiles => session.projectiles;
  @override
  List<Blast> get blasts => session.blasts;
  @override
  List<ShockwaveWalker> get walkers => session.walkers;
  @override
  double get nowMs => session.clock.nowMs;
}
