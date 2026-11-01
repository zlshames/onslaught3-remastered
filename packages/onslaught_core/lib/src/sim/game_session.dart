import 'dart:collection';
import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../data/attract_defs.dart';
import '../data/challenge_defs.dart';
import '../data/creep_wave_defs.dart';
import '../data/game_data.dart';
import '../data/map_definition.dart';
import '../data/turret_def.dart';
import '../math/geometry.dart';
import '../math/vec2.dart';
import '../rules/creep_rules.dart';
import '../rules/economy_rules.dart';
import '../rules/placement_rules.dart';
import '../rules/rules_registry.dart';
import '../rules/specials/combonly.dart';
import '../rules/specials/freakout.dart';
import '../rules/specials/targeter.dart';
import '../rules/stat_rules.dart';
import '../rules/targeting_rules.dart';
import 'entities.dart';
import 'game_clock.dart';
import 'game_command.dart';
import 'game_config.dart';
import 'game_event.dart';
import 'objective_system.dart';
import 'road.dart';
import 'sim_random.dart';
import 'stable_hash.dart';
import 'systems.dart';
import 'waves.dart';

part 'session_commands.dart';
part 'session_debug.dart';
part 'world_actions.dart';

/// One step of work run in a fixed order every tick. [GameSession.step]
/// applies the queued commands, runs the game-time systems ([classicSystems]:
/// waves → creeps → turrets → projectiles → blasts → black-hole captures),
/// then every [RealTimeSystem]'s real-time timers, then the
/// [ObjectiveSystem]'s win check, then the cleanup. Turret relations are
/// recomputed on change only (build, sell, move, upgrade), not every step.
abstract interface class SimSystem {
  /// Stable name, used in diagnostics.
  String get name;

  /// Advances this system by [dtMs] game milliseconds.
  void step(GameSession session, double dtMs);
}

/// A system that also has work on the original's real-time ("eternal")
/// clock: run every step after the game-time systems, even while paused,
/// with the real length of a step.
abstract interface class RealTimeSystem {
  void stepRealTime(GameSession session, double realMs);
}

/// One running game: config, data, clock, seeded RNG and world state.
/// Deterministic: it reads no wall clock and no platform state. Drive it with
/// [enqueue] and [step]; read [events], the world lists and [snapshot].
class GameSession {
  GameSession({
    required this.data,
    required this.config,
    RulesRegistry? registry,
    List<SimSystem>? systems,
  }) : registry = registry ?? RulesRegistry.classic(),
       random = SimRandom(config.seed),
       clock = GameClock(tickHz: data.rules.tickHz),
       _systems = List.unmodifiable(systems ?? classicSystems()) {
    final attract = config.attract ? data.attract : null;
    if (config.attract && attract == null) {
      throw ArgumentError.value(config.mapId, 'attract', 'the data has no attract demo');
    }
    this.attract = attract;
    final map = attract?.map ?? config.customMap ?? data.maps[config.mapId];
    if (map == null) {
      throw ArgumentError.value(config.mapId, 'mapId', 'unknown map');
    }
    this.map = map;
    road = Road.fromMap(map, minePointSpacing: data.world.road.minePointSpacing);
    // A challenge plays at its own difficulty (`resetGame`: `game_diff =
    // game_challenge.difficulty`), the demo at its own.
    final diffId = attract?.difficulty ?? config.challenge?.difficulty ?? config.difficulty;
    final difficulty = data.difficulty.levels.where((l) => l.id == diffId);
    if (difficulty.isEmpty) {
      throw ArgumentError.value(diffId, 'difficulty', 'unknown difficulty');
    }
    this.difficulty = difficulty.first;
    _hpRates = {for (final s in this.difficulty.hpSchedule) s.wave: s.rate};
    _cash =
        config.challenge?.cash ??
        data.difficulty.modeCash[config.mode] ??
        this.difficulty.startingCash;
    _lives = data.rules.lives;
    // The demo's `attacker_upgrade_rate = 1` until the schedule's first entry.
    waves = attract == null
        ? WaveState(creepHp: data.difficulty.baseHp, hpRate: data.difficulty.defaultHpRate)
        : WaveState(creepHp: attract.baseHp, hpRate: 1);
    _waveSpacingMs = config.waveSpacingMs ?? attract?.waveSpacingMs ?? data.waves.waveSpacingMs;
    _waveFollow = config.waveFollow;
    final objective = config.challenge?.objective;
    final tutorialLimit =
        config.mode == GameConfig.tutorialMode && config.profile.tutorialWaveLimit;
    _objectiveSystem = ObjectiveSystem(
      Objectives(
        waveLimit: objective?.type == ChallengeObjective.waves
            ? objective!.target
            : (tutorialLimit ? data.tutorial.waveLimit : null),
        killTarget: objective?.type == ChallengeObjective.kills ? objective!.target : null,
        timeLimitMs: config.challenge?.timeLimitS == null
            ? null
            : config.challenge!.timeLimitS! * 1000,
      ),
    );
    // The sandboxes open more of the rack up front (`GameManager.resetGame`).
    _available = {
      for (final def in data.turrets.values)
        if (def.availableInitially) def.id,
      ...?data.difficulty.modeRacks[config.mode],
    };
  }

  final GameData data;
  final GameConfig config;
  final RulesRegistry registry;
  final SimRandom random;
  final GameClock clock;
  late final MapDefinition map;
  late final Road road;
  late final DifficultyDef difficulty;
  late final Map<int, double> _hpRates;
  late final WaveState waves;
  final List<SimSystem> _systems;

  /// The attract demo this session plays, or null.
  late final AttractDef? attract;

  /// Game ms between waves (`AttackerManager.wave_spacing`).
  double get waveSpacingMs => _waveSpacingMs;
  late double _waveSpacingMs;

  /// Send the next wave as soon as the field is clear (`wave_follow`).
  bool get waveFollow => _waveFollow;
  late bool _waveFollow;

  /// Wave, kill and time objectives (challenges, the tutorial).
  Objectives get objectives => _objectiveSystem.objectives;

  /// Runs the objectives and owns their state; [step] runs it after the
  /// real-time timers.
  late final ObjectiveSystem _objectiveSystem;

  /// Positions in a challenge's wave-size and wave-speed lists
  /// (`wave_size_list_cur`, `attacker_speed_list_cur`).
  int _sizeCursor = 0;
  int _speedCursor = 0;

  /// The tutorial's one-off cash has been given (`cash_awarded`).
  bool _tutorialCashGiven = false;

  // The world state is read-only from outside: it changes only through
  // [enqueue]d commands and the systems and rules the step runs. Tests and
  // the soak driver set states up through [SessionDebug].

  /// Set once the game is won (the clock is stopped too, until freeplay).
  bool get won => _won;
  bool _won = false;

  /// The won game goes on in freeplay (`ContinuePlaying`): waves without
  /// end, no objectives.
  bool get freeplay => _freeplay;
  bool _freeplay = false;

  double get cash => _cash;
  double _cash = 0;

  int get lives => _lives;
  int _lives = 0;

  int get kills => _kills;
  int _kills = 0;

  /// Shots fired by every turret (`Game.weaponFired`).
  int get shots => _shots;
  int _shots = 0;

  /// Combos fired (`Game.weaponComboFired`); not counted as shots.
  int get combos => _combos;
  int _combos = 0;

  /// Cash spent minus sale refunds (`total_spent`); the score is kills × this.
  double get totalSpent => _totalSpent;
  double _totalSpent = 0;

  /// Creeps on the road, in spawn order.
  late final UnmodifiableListView<Creep> creeps = _ReadOnlyList(_creeps);
  final List<Creep> _creeps = [];

  /// Turrets, in build order.
  late final UnmodifiableListView<Turret> turrets = _ReadOnlyList(_turrets);
  final List<Turret> _turrets = [];

  /// Projectiles in flight, in launch order.
  late final UnmodifiableListView<Projectile> projectiles = _ReadOnlyList(_projectiles);
  final List<Projectile> _projectiles = [];

  /// Blasts going off, in spawn order.
  late final UnmodifiableListView<Blast> blasts = _ReadOnlyList(_blasts);
  final List<Blast> _blasts = [];

  /// Shockwave walkers on the road, in spawn order.
  late final UnmodifiableListView<ShockwaveWalker> walkers = _ReadOnlyList(_walkers);
  final List<ShockwaveWalker> _walkers = [];

  final Map<int, Creep> _creepsByUid = {};
  int _nextUid = 1;

  /// Turret ids the player may buy (`GameManager.turrets_available`).
  late final Set<String> _available;

  /// Turrets unlocked by kills this game, in unlock order.
  late final UnmodifiableListView<String> unlocked = _ReadOnlyList(_unlocked);
  final List<String> _unlocked = [];

  final List<GameCommand> _pending = [];
  final List<ScheduledCommand> _log = [];
  final List<GameEvent> _events = [];
  bool _started = false;

  /// Events emitted by the most recent [step].
  List<GameEvent> get events => List.unmodifiable(_events);

  /// Fixed steps taken so far (= the index of the next step).
  int get tick => clock.ticks;

  /// 0-based index of the step being run (or last run); every event of a
  /// step carries it.
  int get stepIndex => _stepIndex;
  int _stepIndex = 0;

  bool get gameOver => clock.stopped;

  /// Game ms until the wave clock sends the next wave; 0 once no more waves
  /// come (`WaveClock.clockSet(0)`).
  double get msUntilNextWave =>
      objectives.noMoreWaves ? 0 : waves.msUntilNextWave(clock.nowMs, waveSpacingMs);

  /// Whole seconds left of the time limit as the original's badge shows it
  /// (`timeLimitUpdate`: rounded, never below 0), or null with no limit.
  int? get timeLimitSecondsLeft {
    final limit = objectives.timeLimitMs;
    if (limit == null) return null;
    return math.max(0, roundHalfUp((limit - clock.nowMs) / 1000).toInt());
  }

  /// No creep on the road and no wave still sending
  /// (`attackerCount() == 0 && waveCount() == 0`).
  bool get fieldClear => _creeps.every((c) => c.gone) && waves.spawners.every((w) => w.done);

  /// Queues [command] to be applied at the start of the next step, and logs
  /// it against that step ([commandLog]).
  void enqueue(GameCommand command) {
    _pending.add(command);
    _log.add(ScheduledCommand(tick, command));
  }

  /// Every command sent to this session, with the step it applies at, in
  /// order: with [config] and the game data, all it takes to rebuild the
  /// game exactly ([SessionReplay]). Rejected commands stay in: replaying
  /// them is exact and harmless.
  List<ScheduledCommand> get commandLog => UnmodifiableListView(_log);

  /// Emits [event] during the current step (systems call this).
  @internal
  void emit(GameEvent event) => _events.add(event);

  /// Advances one fixed step and returns the events it produced.
  List<GameEvent> step() {
    _events.clear();
    _stepIndex = clock.ticks;
    if (!_started) {
      _started = true;
      emit(
        SessionStarted(
          stepIndex,
          map: config.mapId,
          mode: config.mode,
          difficulty: config.difficulty,
          profile: config.profile.id,
          seed: config.seed,
          cash: cash,
          lives: lives,
        ),
      );
      _placeAttractTurrets();
    }
    final commands = List.of(_pending);
    _pending.clear();
    commands.forEach(_apply);
    final dt = clock.tick();
    if (dt > 0) {
      for (final s in _systems) {
        if (clock.stopped) break;
        s.step(this, dt);
      }
    }
    // Timers on the original's real-time clock run paused or not.
    if (!clock.stopped) {
      for (final s in _systems) {
        if (s is RealTimeSystem) (s as RealTimeSystem).stepRealTime(this, clock.stepMs);
      }
    }
    // The objectives step: the win check, also on real time.
    _objectiveSystem.stepRealTime(this, clock.stepMs);
    removeFinished();
    return events;
  }

  /// Steps [n] times and returns every event produced, in order.
  List<GameEvent> run(int n) => [for (var i = 0; i < n; i++) ...step()];

  // ------------------------------------------------------------ lookups

  /// The creep with [uid], or null when there is none (or [uid] is null).
  Creep? creepByUid(int? uid) => uid == null ? null : _creepsByUid[uid];

  Turret? turretByUid(int uid) {
    for (final t in _turrets) {
      if (t.uid == uid) return t;
    }
    return null;
  }

  /// The other turrets within [range] of [t] (centre to centre, the edge
  /// included) that pass [where], in build order. Only active ones unless
  /// [includeInactive] (modifier auras also cover turrets being consumed
  /// and a Combonly plate still arming).
  Iterable<Turret> turretsNear(
    Turret t,
    double range, {
    bool Function(Turret)? where,
    bool includeInactive = false,
  }) => _turrets.where(
    (o) =>
        o != t &&
        (includeInactive || o.active) &&
        t.position.distanceTo(o.position) <= range &&
        (where == null || where(o)),
  );

  /// Whether turrets of type [def] can be built under the current rules:
  /// it has a weapon or a special, every projectile it fires has
  /// implemented rules and so has every special it needs. A registry
  /// without one of them (a trimmed test registry, or data from a pack that
  /// adds a kind this build lacks) leaves the turret unbuildable rather than
  /// placing a turret that cannot fire.
  bool isBuildable(TurretDef def) {
    if (def.projectiles.isEmpty && def.specials.isEmpty) return false;
    for (final id in def.projectiles.toSet()) {
      final spec = data.projectiles[id];
      if (spec == null || !registry.implementsProjectileKind(spec.kind)) return false;
    }
    return def.specials.every(registry.allowsTurretSpecial);
  }

  /// Whether the player may buy turrets of type [def] yet (available from
  /// the start or unlocked by kills).
  bool isAvailable(TurretDef def) => _available.contains(def.id);

  /// The specials of [t], in data order.
  Iterable<TurretSpecial> specialsOf(Turret t) => t.def.specials.map(registry.turretSpecial);

  Projectile? projectileByUid(int uid) {
    for (final p in _projectiles) {
      if (p.uid == uid) return p;
    }
    return null;
  }

  /// A fresh entity uid (projectiles, blasts, walkers).
  @internal
  int nextUid() => _nextUid++;

  /// Whether [t] has reloaded (`Turret.turretCanFire`: strictly more than
  /// `60000 / rate` ms since its last shot).
  bool canFire(Turret t) =>
      clock.nowMs - t.firedAtMs > fireIntervalMs(turretStat(t, StatKind.rate, data.rules));

  /// The looser reload test combos use (`Turret.comboCanFire`: at least
  /// `60000 / rate` ms since the last shot).
  bool reloadedForCombo(Turret t) =>
      clock.nowMs - t.firedAtMs >= fireIntervalMs(turretStat(t, StatKind.rate, data.rules));

  /// Why a turret of [def] cannot be placed at [at] (excluding the turret
  /// [moving] when moving one), or null.
  PlacementIssue? placementIssueAt(Vec2 at, {Turret? moving}) => placementIssue(
    world: data.world,
    road: road,
    base: map.base,
    at: at,
    others: [
      for (final t in _turrets)
        if (t != moving) t.position,
    ],
    turretLimit: moving == null ? config.challenge?.turretLimit : null,
  );

  // ---------------------------------------------------- world changes

  /// `AttackerManager.waveSend` past its pause and game-over checks: no
  /// wave once the waves have ended (wave limit, kill target, time limit);
  /// the first attempt past the wave limit reaches it. Returns whether a
  /// wave was sent.
  @internal
  bool waveSend({required bool early}) {
    if (freeplay) {
      sendWave(early: early);
      return true;
    }
    if (!_objectiveSystem.allowsWave(this)) return false;
    sendWave(early: early);
    return true;
  }

  /// Sends the next wave (`AttackerManager._waveNext` and the rest of
  /// `waveSend`); [early] when the player asked for it before the clock ran
  /// out. A challenge's size and speed lists are cycled, one entry a wave.
  @internal
  void sendWave({required bool early}) {
    final sizes = config.challenge?.waveSizes;
    final speeds = config.challenge?.waveSpeeds;
    int? size;
    if (sizes != null) {
      size = sizes[_sizeCursor];
      _sizeCursor = (_sizeCursor + 1) % sizes.length;
    }
    var speed = difficulty.creepSpeed;
    if (speeds != null) {
      speed = speeds[_speedCursor];
      _speedCursor = (_speedCursor + 1) % speeds.length;
    }
    final spawner = waves.next(
      defs: data.waves,
      rates: _hpRates,
      speed: speed,
      creepTypes: attract?.creepTypes ?? data.creeps.types.length,
      nowMs: clock.nowMs,
      size: size ?? attract?.waveSize,
      sizeChange: attract?.sizeChange,
    );
    emit(
      WaveStarted(
        stepIndex,
        wave: spawner.wave,
        size: spawner.size,
        creepType: spawner.creepType,
        hp: spawner.hp,
        bounty: spawner.bounty,
        speed: spawner.speed,
        early: early,
      ),
    );
  }

  /// Spawns the next creep of [wave] at the road's first point plus a
  /// jitter offset (`AttackerEngine` ctor) and starts its first leg.
  @internal
  void spawnCreep(WaveSpawner wave) {
    final jitter = data.creeps.movement.number('waypointJitter') ?? 0;
    final dx = jitterOffset(random, jitter);
    final dy = jitterOffset(random, jitter);
    final creep = Creep(
      uid: _nextUid++,
      wave: wave.wave,
      typeIndex: wave.creepType,
      behaviour: _walker,
      position: road.points.first + Vec2(dx, dy),
      hpStart: wave.hp,
      baseSpeed: wave.speed,
      bounty: wave.bounty,
      scaleBump: wave.scaleBump,
      createdAtMs: clock.nowMs,
    );
    wave.sent++;
    _creeps.add(creep);
    _creepsByUid[creep.uid] = creep;
    emit(
      CreepSpawned(
        stepIndex,
        uid: creep.uid,
        wave: wave.wave,
        x: creep.position.x,
        y: creep.position.y,
      ),
    );
    registry.creepBehaviour(creep.behaviour).start(this, creep);
  }

  static const String _walker = 'walker';

  /// Recomputes every turret's modifier-aura terms (`TurretModify`
  /// assert/unassert on build, sell, move and upgrade). The original adds and
  /// removes terms incrementally; the sums are the same.
  @internal
  void refreshRelations() {
    for (final t in _turrets) {
      t.aura = StatTerms.identity;
    }
    for (final t in _turrets) {
      for (final sp in specialsOf(t)) {
        sp.applyRelations(this, t);
      }
    }
  }

  /// A Combonly plate [into] takes [t]: it stops (`active = false`) and its
  /// value goes into the plate's, with no refund. [removeConsumed] takes it
  /// off the map later.
  @internal
  void consumeTurret(Turret t, Turret into) {
    t
      ..active = false
      ..targetUid = null;
    into.cashValue += t.cashValue;
  }

  /// [t], consumed by plate [into], is removed (`TurretManager.turretSold`
  /// with no refund; its own `onSell` is not called, its specials'
  /// [TurretSpecial.onConsumed] is).
  @internal
  void removeConsumed(Turret t, Turret into) {
    if (!_turrets.remove(t)) return;
    for (final sp in specialsOf(t)) {
      sp.onConsumed(this, t);
    }
    refreshRelations();
    emit(TurretConsumed(stepIndex, uid: t.uid, into: into.uid));
    _notifyGone(t);
  }

  /// Tells every other turret's specials that [t] is gone (`notifyGone`).
  void _notifyGone(Turret t) {
    for (final o in List.of(_turrets)) {
      if (o == t) continue;
      for (final sp in specialsOf(o)) {
        sp.onTurretGone(this, o, t);
      }
    }
  }

  /// Tells every other turret's specials that [t] is new here (`notifyNew`).
  void _notifyAdded(Turret t) {
    for (final o in List.of(_turrets)) {
      if (o == t) continue;
      for (final sp in specialsOf(o)) {
        sp.onTurretAdded(this, o, t);
      }
    }
  }

  /// [creep] walked past the last waypoint (`GameManager.roadBaseHit`): one
  /// life lost; at zero lives the game is over and the clock stops.
  @internal
  void creepReachedBase(Creep creep) {
    creep.gone = true;
    // The demo never loses a life (`roadBaseHit` checks `game_demo`).
    if (!config.attract) _lives--;
    emit(BaseHit(stepIndex, uid: creep.uid, lives: lives));
    if (lives == 0) endGame(GameOver.livesReason);
  }

  /// `GameManager.timeLimitUpdate`, on the wave manager's check (the
  /// objectives decide).
  @internal
  void checkTimeLimit() => _objectiveSystem.checkTimeLimit(this);

  /// The game is won (`gameWinCheck`): the clock stops until freeplay.
  @internal
  void winGame() {
    _won = true;
    clock.stopped = true;
    final r = _summary();
    emit(
      GameWon(
        stepIndex,
        wave: r.wave,
        kills: r.kills,
        shots: r.shots,
        spent: r.spent,
        score: r.score,
      ),
    );
  }

  /// The game is lost: the clock stops (`GameManager.gameOver`).
  @internal
  void endGame(String reason) {
    clock.stopped = true;
    final r = _summary();
    emit(
      GameOver(
        stepIndex,
        wave: r.wave,
        kills: r.kills,
        shots: r.shots,
        spent: r.spent,
        score: r.score,
        reason: reason,
      ),
    );
  }

  /// The end-of-game figures [GameWon] and [GameOver] both report.
  ({int wave, int kills, int shots, double spent, double score}) _summary() => (
    wave: waves.wave,
    kills: kills,
    shots: shots,
    spent: totalSpent,
    score: score(kills: kills, spent: totalSpent),
  );

  /// Removes dead or arrived creeps and spent projectiles, blasts and
  /// walkers (the cleanup step).
  @internal
  void removeFinished() {
    _creeps.removeWhere((c) {
      if (!c.gone) return false;
      _creepsByUid.remove(c.uid);
      return true;
    });
    _projectiles.removeWhere((p) => p.done);
    _blasts.removeWhere((b) => b.done);
    _walkers.removeWhere((w) => w.done);
  }

  // --------------------------------------------------------- snapshot

  /// A JSON view of the whole session state; [stateHash] hashes it.
  Map<String, Object?> snapshot() => {
    'tick': clock.ticks,
    'timeMs': clock.nowMs,
    'paused': clock.paused,
    'stopped': clock.stopped,
    'speed': clock.speed,
    'cash': cash,
    'lives': lives,
    'kills': kills,
    'shots': shots,
    'totalSpent': totalSpent,
    'nextUid': _nextUid,
    'rng': {'state': random.state, 'draws': random.draws},
    'waves': waves.toJson(),
    'creeps': [for (final c in _creeps) c.toJson()],
    'turrets': [for (final t in _turrets) t.toJson()],
    'projectiles': [for (final p in _projectiles) p.toJson()],
    if (_blasts.isNotEmpty) 'blasts': [for (final b in _blasts) b.toJson()],
    if (_walkers.isNotEmpty) 'walkers': [for (final w in _walkers) w.toJson()],
    if (combos > 0) 'combos': combos,
    if (_unlocked.isNotEmpty) 'unlocked': unlocked,
    // Only games that use them carry these, so other games' hashes are
    // unchanged.
    if (objectives.any) 'objectives': objectives.toJson(),
    if (won) 'won': true,
    if (freeplay) 'freeplay': true,
    if (waveSpacingMs != data.waves.waveSpacingMs) 'waveSpacingMs': waveSpacingMs,
    if (waveFollow) 'waveFollow': true,
    if (config.challenge != null) 'waveCursors': [_sizeCursor, _speedCursor],
    if (_tutorialCashGiven) 'tutorialCashGiven': true,
  };

  /// Platform-stable hash of [snapshot], recorded in regression fixtures.
  int stateHash() => fnv1a32(canonicalJson(snapshot()));

  /// Effective stats of [t] (damage, range, rate) for views and tests.
  double statOf(Turret t, StatKind stat) => turretStat(t, stat, data.rules);
}

/// A read-only view of one of the session's world lists. Reads go straight
/// to the backing list (the plain [UnmodifiableListView] reads through
/// `Iterable.elementAt`, which the systems' per-step scans feel); every
/// mutator still throws.
final class _ReadOnlyList<E> extends UnmodifiableListView<E> {
  _ReadOnlyList(this._list) : super(_list);

  final List<E> _list;

  @override
  int get length => _list.length;

  @override
  E operator [](int index) => _list[index];

  @override
  Iterator<E> get iterator => _list.iterator;
}
