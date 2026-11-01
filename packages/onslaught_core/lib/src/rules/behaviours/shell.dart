import '../../math/geometry.dart';

import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import '../targeting_rules.dart';

/// Blue's shell (`ShellEngine`): flies at `speed` px/s with perfect homing
/// (heading snapped onto the target every step) and hits when the target is
/// closer than `impactRadius` or than this step's travel. It deals its
/// damage only (no slow, no blast). If the target is gone it vanishes
/// without retargeting.
class ShellKind implements ProjectileKind {
  const ShellKind();

  @override
  String get id => 'shell';

  @override
  Set<String>? get paramKeys => const {'speed', 'impactRadius', 'homing', 'tickMs'};

  @override
  void launch(GameSession session, Projectile p) {}

  @override
  void step(GameSession session, Projectile p, double dtMs) {
    final target = session.creepByUid(p.targetUid);
    if (target == null || !target.targetable) {
      p.done = true;
      return;
    }
    final params = session.data.projectiles[p.specId]!.params;
    final distance = p.position.distanceTo(target.position);
    if (distance < params.number('impactRadius')!) {
      _hit(session, p, target);
      return;
    }
    p.heading = bearingDeg(p.position, target.position);
    final travel = dtMs / 1000 * params.number('speed')!;
    if (distance < travel) {
      _hit(session, p, target);
      return;
    }
    p.position = forwardFrom(p.position, p.heading, travel);
  }

  void _hit(GameSession session, Projectile p, Creep target) {
    session.hitCreep(target, p.damage, by: p.turretUid);
    p.done = true;
  }
}
