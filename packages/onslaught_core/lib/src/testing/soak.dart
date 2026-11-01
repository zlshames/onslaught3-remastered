import '../data/turret_def.dart';
import '../math/vec2.dart';
import '../sim/game_command.dart';
import '../sim/game_session.dart';
import 'bot.dart';

/// What a soak run saw.
class SoakStats {
  int decisions = 0;
  int built = 0;
  int upgrades = 0;
  int sold = 0;
  int maxCreeps = 0;
  int maxProjectiles = 0;
  int maxBlasts = 0;

  @override
  String toString() =>
      'decisions $decisions, built $built, upgrades $upgrades, sold $sold, '
      'max creeps $maxCreeps, projectiles $maxProjectiles, blasts $maxBlasts';
}

/// Drives a game as hard as it will go, for crash and leak soaks
/// (`docs/REMASTER_PLAN.md` §7 Phase 8: "crash-free soak test at 3× speed to
/// wave 300"). Used headless by the core soak test and on devices by the
/// app's soak integration test, so both play the same way.
///
/// The game should be a sandbox (every turret, ample cash). [setUp] opens
/// every turret, runs the clock at [speed] (3× by default, beyond the
/// player's 2× cap: larger steps are the harder case for the sim), sets the
/// shortest wave spacing with "send the next wave when clear", and builds a
/// mix of every turret type, colours grouped so combos fire. Each [decide]
/// keeps the lives and cash topped up (a soak must not end in a loss), buys
/// the cheapest upgrade, sends the next wave early when the field is quiet,
/// and every [churnEvery] waves sells and rebuilds a turret. Everything goes
/// through [GameSession.enqueue] like a player's commands, except the
/// top-ups and the speed, which are written directly.
class SoakDriver {
  SoakDriver(
    this.session, {
    this.speed = 3,
    this.targetWave = 300,
    this.coloursPerKind = 6,
    this.churnEvery = 25,
    this.quietCreeps = 150,
  });

  final GameSession session;

  /// Game-clock speed factor for the run.
  final double speed;

  /// The run is [done] once this wave has been sent.
  final int targetWave;

  /// How many of each colour turret are built (the others: one each).
  final int coloursPerKind;
  final int churnEvery;

  /// Below this many creeps on the road, with no wave still spawning, the
  /// next wave is sent at once (high, so waves overlap).
  final int quietCreeps;

  final SoakStats stats = SoakStats();
  final List<(String, Vec2)> _plan = [];
  int _next = 0;
  int _churnedAt = 0;

  /// Large enough never to run out; reset on every decision.
  static const int _plentyLives = 1 << 30;
  static const double _plentyCash = 1e15;

  bool get done => session.waves.wave >= targetWave;

  void setUp() {
    final s = session;
    for (final id in s.data.turrets.keys) {
      // A test harness shipped in lib: the sanctioned debug surface (SessionDebug).
      // ignore: invalid_use_of_visible_for_testing_member
      s.debugMakeAvailable(id);
    }
    s.clock.speed = speed;
    s.enqueue(SetWaveSettings(spacingMs: s.data.waves.spacingPrefMinS * 1000, follow: true));
    final defs = s.data.turrets.values.toList();
    final colours = [
      for (final d in defs)
        if (d.category == TurretCategory.basic) d,
    ];
    final others = [
      for (final d in defs)
        if (d.category != TurretCategory.basic) d,
    ];
    // Spots that cover the most road (the bots' ranking); around each, a
    // cluster of one turret per colour within combo range of each other, so
    // the recipes find partners; the other types fill the remaining spots.
    final spots = BotRunner.buildSpots(
      s,
      colours.first,
      BotStrategy(
        id: 'soak',
        description: '',
        mapId: s.map.id,
        turret: colours.first.id,
        maxTurrets: 1000,
      ),
    );
    final gap = s.data.world.placement.turretSpacing + 1;
    final taken = <Vec2>[];
    bool free(Vec2 p) =>
        s.placementIssueAt(p) == null && taken.every((q) => q.distanceTo(p) >= gap - 1);
    final offsets = [
      for (final (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1), (-1, 0), (0, -1), (-1, -1)])
        Vec2(dx * gap, dy * gap),
    ];
    var clusters = 0;
    for (final centre in spots) {
      if (clusters >= coloursPerKind) break;
      final cluster = <Vec2>[];
      for (final o in offsets) {
        final p = centre + o;
        if (cluster.length < colours.length &&
            free(p) &&
            cluster.every((q) => q.distanceTo(p) >= gap - 1)) {
          cluster.add(p);
        }
      }
      if (cluster.length < colours.length) continue;
      taken.addAll(cluster);
      for (var i = 0; i < colours.length; i++) {
        _plan.add((colours[i].id, cluster[i]));
      }
      clusters++;
    }
    for (final o in others) {
      final at = spots.where(free).firstOrNull;
      if (at == null) break;
      taken.add(at);
      _plan.add((o.id, at));
    }
  }

  /// One decision; call it every few steps (the bots use 30).
  void decide() {
    final s = session;
    stats.decisions++;
    // The top-up goes through the sanctioned debug surface (SessionDebug).
    // ignore: invalid_use_of_visible_for_testing_member
    s.debugLives = _plentyLives;
    // ignore: invalid_use_of_visible_for_testing_member
    s.debugCash = _plentyCash;
    if (_next < _plan.length) {
      final (id, at) = _plan[_next++];
      s.enqueue(BuildTurret(id, at.x, at.y));
      stats.built++;
    } else {
      _upgradeCheapest();
    }
    if (s.waves.spawners.isEmpty && s.creeps.length < quietCreeps && !done) {
      s.enqueue(const SendNextWave());
    }
    final wave = s.waves.wave;
    if (wave - _churnedAt >= churnEvery && s.turrets.isNotEmpty) {
      _churnedAt = wave;
      final t = s.turrets.first;
      s.enqueue(SellTurret(t.uid));
      _plan.add((t.def.id, t.position));
      stats.sold++;
    }
    if (s.creeps.length > stats.maxCreeps) stats.maxCreeps = s.creeps.length;
    if (s.projectiles.length > stats.maxProjectiles) stats.maxProjectiles = s.projectiles.length;
    if (s.blasts.length > stats.maxBlasts) stats.maxBlasts = s.blasts.length;
  }

  /// The cheapest next upgrade, damage before the others: maxed damage
  /// makes the colours combo-capable, which is where the heavy ordnance is.
  void _upgradeCheapest() {
    final s = session;
    UpgradeTurret? best;
    for (final stat in StatKind.values) {
      best = _cheapest(stat);
      if (best != null) break;
    }
    if (best != null) {
      s.enqueue(best);
      stats.upgrades++;
    }
  }

  UpgradeTurret? _cheapest(StatKind stat) {
    UpgradeTurret? best;
    var bestCost = double.infinity;
    for (final t in session.turrets) {
      {
        final track = t.def.upgrades.track(stat);
        final level = t.level(stat);
        if (level >= track.length) continue;
        if (track[level].cost < bestCost) {
          bestCost = track[level].cost;
          best = UpgradeTurret(t.uid, stat.name);
        }
      }
    }
    return best;
  }
}
