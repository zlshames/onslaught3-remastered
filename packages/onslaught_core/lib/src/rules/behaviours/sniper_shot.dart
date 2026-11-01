import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import 'beam.dart';

/// The Sniper's shot (`BulletSniper.as:onLoad`): it hits its target the
/// moment it is fired (direct damage, no slow) and leaves a short tracer on
/// the line to it for `tracerMs`. With no target it does nothing. The
/// tracer's random segment and the ejected brass casing are drawn by the
/// views (`TurretSniper.brassFire`), not simulated.
class SniperShotKind implements ProjectileKind {
  const SniperShotKind();

  @override
  String get id => 'sniper-shot';

  @override
  Set<String>? get paramKeys => const {'instant', 'tracerColor', 'tracerAlpha', 'tracerMs'};

  @override
  void launch(GameSession session, Projectile p) {
    final target = instantTarget(session, p);
    if (target == null) return;
    session.hitCreep(target, p.damage, by: p.turretUid);
  }

  @override
  void step(GameSession session, Projectile p, double dtMs) {
    final ms = session.data.projectiles[p.specId]!.params.number('tracerMs') ?? 0;
    if (session.clock.nowMs - p.createdAtMs >= ms) p.done = true;
  }
}
