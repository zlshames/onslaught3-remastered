import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import 'ordnance.dart';

/// Green's laser (`LaserEngine`): hits its target the moment it is fired
/// (direct damage only, its poison is ignored) and then stays as a straight
/// line that fades over `fadeMs` of game time. Fired at no creep (a link
/// helper shooting its leader) it is only the line; fired into a turret (a
/// Fusion cannon) the turret absorbs its damage.
class BeamKind implements ProjectileKind {
  const BeamKind();

  @override
  String get id => 'beam';

  @override
  Set<String>? get paramKeys => const {'instant', 'fadeMs', 'startAlpha', 'blackHoleImmune'};

  @override
  void launch(GameSession session, Projectile p) {
    final into = p.intoTurretUid;
    if (into != null) return session.feedTurret(into, damage: p.damage, poison: 0);
    final target = instantTarget(session, p);
    if (target == null) return;
    session.hitCreep(target, p.damage, by: p.turretUid);
  }

  @override
  void step(GameSession session, Projectile p, double dtMs) => fade(session, p);
}

/// Yellow's tazer (`SparkEngine`): instant like the laser, but it first
/// slows its target by its poison, subtracted (`attackerPoison(p, true)`),
/// then deals its damage. A spark carrying a blast (the shockwave) sets it
/// off first. Drawn as jagged lightning that fades over `fadeMs`. Fired into
/// a turret (a Fusion cannon) the turret absorbs its poison and damage.
class SparkKind implements ProjectileKind {
  const SparkKind();

  @override
  String get id => 'spark';

  @override
  Set<String>? get paramKeys => const {
    'instant',
    'defaultPoison',
    'segmentLength',
    'minSegments',
    'extraSegmentsMax',
    'jitter',
    'fadeMs',
    'alpha',
    'blackHoleImmune',
  };

  @override
  void launch(GameSession session, Projectile p) {
    final into = p.intoTurretUid;
    if (into != null) return session.feedTurret(into, damage: p.damage, poison: p.poison);
    final target = instantTarget(session, p);
    if (target == null) return;
    detonate(session, p);
    session
      ..slowCreep(target, p.poison, subtract: true)
      ..hitCreep(target, p.damage, by: p.turretUid);
  }

  @override
  void step(GameSession session, Projectile p, double dtMs) => fade(session, p);
}

/// Points an instant shot's line at its creep and returns the creep. With
/// no creep it keeps the line it was given (a shot at a turret) or, with
/// none, is spent at once (`removeMyself` when the target is gone).
Creep? instantTarget(GameSession session, Projectile p) {
  final target = session.creepByUid(p.targetUid);
  if (target != null && target.targetable) {
    p.lineTo = target.position;
    return target;
  }
  if (p.lineTo == null) p.done = true;
  return null;
}

/// Removes an instant shot once its line has faded (a pausable game-time
/// effect in the original).
void fade(GameSession session, Projectile p) {
  final fadeMs = session.data.projectiles[p.specId]!.params.number('fadeMs') ?? 0;
  if (session.clock.nowMs - p.createdAtMs >= fadeMs) p.done = true;
}
