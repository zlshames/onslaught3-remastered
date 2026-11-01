import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import 'rocket_state.dart';

/// `Projectile.projectileBlast` then `projectileCluster`: the blast and the
/// cluster that [p] carries go off where it is, with its heading as the
/// blast angle and its target as the blast's target.
void detonate(GameSession s, Projectile p) {
  final load = p.load;
  if (load == null) return;
  final blast = load.blast;
  if (blast != null) {
    s.spawnBlast(
      specId: blast.type,
      at: p.position,
      damage: blast.damage,
      poison: blast.poison,
      turretUid: p.turretUid,
      angle: p.heading,
      targetUid: p.targetUid,
      sound: blast.sound,
      load: load.copy(),
    );
  }
  final cluster = load.cluster;
  if (cluster != null) {
    s.spawnBlast(
      specId: cluster.type,
      at: p.position,
      damage: cluster.damage,
      poison: 1,
      turretUid: p.turretUid,
      angle: p.heading,
      load: load.copy(),
    );
  }
}

/// Launches an instant shot or a rocket [specId] from [at] (`bulletNew` from
/// a projectile: on-board lasers and rockets, cluster children) and returns
/// it.
Projectile launchChild(
  GameSession s, {
  required String specId,
  required Vec2 at,
  required double heading,
  required double damage,
  required int? targetUid,
  required int? turretUid,
  double poison = 1,
  bool holdingCapable = false,
}) {
  final spec = s.data.projectiles[specId]!;
  final p = s.addProjectile(
    specId: specId,
    kind: spec.kind,
    position: at,
    heading: heading,
    damage: damage,
    targetUid: targetUid,
    turretUid: turretUid,
    poison: poison,
  );
  if (holdingCapable) RocketState.of(p).holdingCapable = true;
  s.launchProjectile(p);
  return p;
}

/// Whether [p] lies in the square `±range` box around [centre], edges
/// included (`targetAcquireBySlice`).
bool inBox(Vec2 p, Vec2 centre, double range) =>
    (p.x - centre.x).abs() <= range && (p.y - centre.y).abs() <= range;
