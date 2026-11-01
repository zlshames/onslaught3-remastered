import '../../math/geometry.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';

class RailState extends KindState {
  /// Real ms since it was fired.
  double sinceMs = 0;

  /// Whether its one damage pass has run.
  bool hurt = false;

  @override
  Map<String, Object?> toJson() => {'ms': sinceMs, 'hurt': hurt};
}

/// The Railgun's beam (`RailLaser.as:laserFire/railHurt`).
///
/// * Fired at a creep, it is drawn from the fire point toward the creep and
///   on to `length` px in all; at no creep it is not drawn.
/// * One damage pass `hurtDelayMs` after it is fired: every creep whose
///   centre lies on the drawn beam (within `halfWidth` of the line, round
///   ends included) takes the full damage once, credited to the turret.
/// * It is removed `visualMs` after it was fired.
///
/// The damage pass runs on the original's real-time interval (also while
/// paused, whatever the game speed); the removal is a pausable effect.
class RailKind implements RealTimeProjectileKind {
  const RailKind();

  @override
  String get id => 'rail';

  @override
  Set<String>? get paramKeys => const {
    'instant',
    'length',
    'halfWidth',
    'hurtDelayMs',
    'visualMs',
    'blackHoleImmune',
  };

  @override
  void launch(GameSession session, Projectile p) {
    p.state = RailState();
    final target = session.creepByUid(p.targetUid);
    if (target == null || !target.targetable) return;
    final length = session.data.projectiles[p.specId]!.params.number('length')!;
    final d = target.position - p.position;
    final distance = d.length;
    if (distance <= 0) return;
    p.lineTo = p.position + d * (length / distance);
  }

  @override
  void step(GameSession session, Projectile p, double dtMs) {
    final ms = session.data.projectiles[p.specId]!.params.number('visualMs') ?? 0;
    if (session.clock.nowMs - p.createdAtMs >= ms) p.done = true;
  }

  @override
  void stepRealTime(GameSession session, Projectile p, double realMs) {
    final st = p.state as RailState?;
    if (st == null || st.hurt) return;
    st.sinceMs += realMs;
    final params = session.data.projectiles[p.specId]!.params;
    if (st.sinceMs < params.number('hurtDelayMs')!) return;
    st.hurt = true;
    final end = p.lineTo;
    if (end == null) return;
    final halfWidth = params.number('halfWidth')!;
    for (final c in List.of(session.creeps)) {
      if (!c.targetable) continue;
      if (distanceToSegment(c.position, p.position, end) <= halfWidth) {
        session.hitCreep(c, p.damage, by: p.turretUid);
      }
    }
  }
}
