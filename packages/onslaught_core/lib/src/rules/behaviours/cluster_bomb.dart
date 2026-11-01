import '../../math/geometry.dart';
import '../../sim/entities.dart';

import '../../sim/game_session.dart';
import '../rules_registry.dart';
import '../targeting_rules.dart';
import 'ordnance.dart';

/// The Blue combos' cluster bomb (`ClusterBombEngine`): flies at `speed`
/// px/s with perfect homing (heading snapped onto the target every step).
///
/// * Closer than `impactRadius` at the start of a step, it deals its damage
///   directly and stays: it does it again every step while that close (the
///   original's quirk; only the step-sized hit below explodes).
/// * Closer than this step's travel, it deals its damage and explodes:
///   its blast and cluster go off where it is (not snapped onto the
///   target).
/// * When its target is gone it explodes in place.
class ClusterBombKind implements ProjectileKind {
  const ClusterBombKind();

  @override
  String get id => 'cluster-bomb';

  @override
  Set<String>? get paramKeys => const {'speed', 'impactRadius', 'homing'};

  @override
  void launch(GameSession session, Projectile p) {}

  @override
  void step(GameSession session, Projectile p, double dtMs) {
    final target = session.creepByUid(p.targetUid);
    if (target == null || target.gone) {
      _explode(session, p);
      return;
    }
    final params = session.data.projectiles[p.specId]!.params;
    final distance = p.position.distanceTo(target.position);
    if (distance < params.number('impactRadius')!) {
      session.hitCreep(target, p.damage, by: p.turretUid);
      return;
    }
    p.heading = bearingDeg(p.position, target.position);
    final travel = dtMs / 1000 * (p.load?.speed ?? params.number('speed')!);
    if (distance < travel) {
      session.hitCreep(target, p.damage, by: p.turretUid);
      _explode(session, p);
      return;
    }
    p.position = forwardFrom(p.position, p.heading, travel);
  }

  static void _explode(GameSession session, Projectile p) {
    detonate(session, p);
    p.done = true;
  }
}
