import 'package:onslaught_core/onslaught_core.dart';
import 'package:onslaught_core/testing.dart';

import 'sim_helpers.dart';

/// A bench for firing one combo recipe and measuring what it does: a
/// sandbox game on Lyne (map9, road (0, 0) → (590, 410)) with a leader 48 px
/// from the road, its helpers on a 45 px ring on the far side, every turret
/// with its damage track maxed, and a single toughened creep. Turrets hold
/// their fire (their reload is reset every step), so the only damage is the
/// combo's.
class ComboBench {
  ComboBench(GameData data, {RulesProfile profile = RulesProfile.classic, int seed = 4})
    : s = SimTestHarness(data).session(
        GameConfig(mapId: 'map9', mode: 'sandbox', seed: seed, profile: profile),
      )..debugCash = 1e12 {
    unlockAll(s);
  }

  final GameSession s;
  late final Turret leader;
  final List<Turret> helpers = [];
  Creep get creep => _creep!;
  Creep? _creep;

  /// HP the creep is given, so nothing kills it.
  static const double toughHp = 1e12;

  static const Vec2 leaderAt = Vec2(300, 150);

  /// Along the road and away from it, unit vectors.
  static const Vec2 _along = Vec2(0.8211, 0.5708);
  static const Vec2 _away = Vec2(0.5708, -0.8211);

  /// Helper spots 45 px from the leader at 0°, 60°, 120°, 180° from the road
  /// direction, all ≥ 45 px apart and off the road.
  static final List<Vec2> ring = [
    for (final deg in [0, 60, 120, 180])
      leaderAt + _along * (45 * _cos(deg)) + _away * (45 * _sin(deg)),
  ];

  static double _cos(int deg) => const {0: 1.0, 60: 0.5, 120: -0.5, 180: -1.0}[deg]!;
  static double _sin(int deg) => const {0: 0.0, 60: 0.8660254, 120: 0.8660254, 180: 0.0}[deg]!;

  /// Builds [leaderId] and [helperIds] with maxed damage.
  void place(String leaderId, List<String> helperIds) {
    leader = maxed(s, leaderId, leaderAt);
    for (var i = 0; i < helperIds.length; i++) {
      helpers.add(maxed(s, helperIds[i], ring[i]));
    }
  }

  /// Sends a wave and keeps only its first creep, toughened.
  void spawnCreep() {
    s.enqueue(const SendNextWave());
    while (s.creeps.isEmpty) {
      step();
    }
    s.waves.spawners.clear();
    _creep = s.creeps.single..hp = toughHp;
  }

  /// Steps until the creep is within the leader's range.
  void waitInRange() {
    final range = s.statOf(leader, StatKind.range);
    for (var i = 0; i < 6000; i++) {
      if (creep.position.distanceTo(leader.position) < range) return;
      step();
    }
    throw StateError('creep never came within range');
  }

  /// The helpers by colour, as `readyHelpers` would give them.
  Map<String, List<Turret>> get ready {
    final out = <String, List<Turret>>{};
    for (final h in helpers) {
      out.putIfAbsent(h.def.id, () => []).add(h);
    }
    return out;
  }

  /// Every event so far.
  final List<GameEvent> events = [];

  /// Uid → spec of every projectile seen after a step.
  final Map<int, String> seen = {};

  /// Fires recipe [id] from the leader at the creep and returns its
  /// projectile.
  Projectile fire(String id) {
    final recipe = s.data.combos[id]!;
    final p = ComboSpecial.fireRecipe(s, leader, recipe, creep, ready);
    events.addAll(s.events);
    _see();
    return p;
  }

  /// The creep's lowest speed so far.
  double minSpeed = double.infinity;

  /// One step with every turret holding fire.
  void step() {
    events.addAll(s.step());
    final c = _creep;
    if (c != null && !c.gone && c.speed < minSpeed) minSpeed = c.speed;
    for (final t in s.turrets) {
      t.firedAtMs = s.clock.nowMs;
    }
    _see();
  }

  /// Steps until no projectile, blast or walker is left (or [maxSteps]).
  void resolve({int maxSteps = 3000}) {
    for (var i = 0; i < maxSteps; i++) {
      if (s.projectiles.isEmpty && s.blasts.isEmpty && s.walkers.isEmpty) return;
      step();
    }
  }

  void _see() {
    for (final p in s.projectiles) {
      seen[p.uid] = p.specId;
    }
  }

  /// Damage the creep has taken.
  double get damage => toughHp - creep.hp;

  /// How many projectiles of [spec] were seen.
  int count(String spec) => seen.values.where((v) => v == spec).length;

  Iterable<T> eventsOf<T extends GameEvent>() => events.whereType<T>();

  /// The blasts that went off, by spec.
  List<BlastStarted> blastsOf(String spec) => [
    for (final b in eventsOf<BlastStarted>())
      if (b.blast == spec) b,
  ];
}

/// Builds [id] at [at] and buys its whole damage track.
Turret maxed(GameSession s, String id, Vec2 at) {
  final t = build(s, id, at);
  upgrade(s, t, StatKind.damage, t.def.upgrades.damage.length);
  return t;
}
