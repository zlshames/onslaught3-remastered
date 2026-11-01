import 'package:onslaught_core/onslaught_core.dart';

/// Builds a [turretId] at [at] in one step and returns it; fails the test
/// if the build is rejected.
Turret build(GameSession s, String turretId, Vec2 at) {
  s.enqueue(BuildTurret(turretId, at.x, at.y));
  final events = s.step();
  final built = events.whereType<TurretBuilt>().toList();
  if (built.isEmpty) {
    throw StateError('build $turretId at $at rejected: ${events.whereType<CommandRejected>()}');
  }
  return s.turretByUid(built.single.uid)!;
}

/// Buys [n] upgrades of [stat] for [t] in one step.
void upgrade(GameSession s, Turret t, StatKind stat, [int n = 1]) {
  for (var i = 0; i < n; i++) {
    s.enqueue(UpgradeTurret(t.uid, stat.name));
  }
  final rejected = s.step().whereType<CommandRejected>().toList();
  if (rejected.isNotEmpty) throw StateError('upgrade rejected: $rejected');
}

/// Makes every turret type available (as the sandbox does).
void unlockAll(GameSession s) {
  for (final id in s.data.turrets.keys) {
    s.debugMakeAvailable(id);
  }
}

/// Steps until [test] holds for an event (returns it) or [maxSteps] pass.
T? stepUntil<T extends GameEvent>(GameSession s, {bool Function(T)? test, int maxSteps = 6000}) {
  for (var i = 0; i < maxSteps; i++) {
    for (final e in s.step().whereType<T>()) {
      if (test == null || test(e)) return e;
    }
  }
  return null;
}

/// Gives every creep that has not been hit yet [hp] hit points, so tests
/// can measure damage without kills.
void toughen(GameSession s, [double hp = 1e9]) {
  for (final c in s.creeps) {
    if (c.hp == c.hpStart) c.hp = hp;
  }
}

/// Sends the next wave and steps until its first creep is on the road.
Creep firstCreep(GameSession s) {
  s.enqueue(const SendNextWave());
  for (var i = 0; i < 600; i++) {
    s.step();
    if (s.creeps.isNotEmpty) return s.creeps.first;
  }
  throw StateError('no creep spawned');
}
