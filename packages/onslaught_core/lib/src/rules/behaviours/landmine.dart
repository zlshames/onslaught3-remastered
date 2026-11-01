import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import 'ordnance.dart';

class LandmineState extends KindState {
  LandmineState(this.from, this.to);

  /// The throw: from the turret's centre to the mine point plus jitter.
  final Vec2 from;
  final Vec2 to;
  double elapsedMs = 0;

  /// Landed and armed (`mine_planted`).
  bool planted = false;

  /// Game ms since the last trigger check.
  double sinceCheckMs = 0;

  @override
  Map<String, Object?> toJson() => {
    'to': to.toJson(),
    'ms': elapsedMs,
    'planted': planted,
    'check': sinceCheckMs,
  };
}

/// The Blue combos' landmines (`LandmineEngine`).
///
/// * It is thrown from the leader's centre to its mine point moved by a
///   whole-pixel jitter in `[−jitter, jitter)` on each axis, in a fixed
///   `throwMs` whatever the distance (the combo's 220 px/s is never read),
///   and is armed when it lands.
/// * Every `checkIntervalMs` from its launch, once armed, any creep inside
///   the `±triggerBox` square sets it off: its blast and cluster go off and
///   it is removed. It deals no direct damage (`landmineBulletDamage` adds
///   its damage to the creep that set it off) and never expires.
/// * A combo that found no mine point in range throws nothing: the mine is
///   removed at once (the original makes an inert mine at an undefined
///   point, which can never go off).
class LandmineKind implements ProjectileKind {
  const LandmineKind();

  @override
  String get id => 'landmine';

  @override
  Set<String>? get paramKeys => const {'throwMs', 'jitter', 'checkIntervalMs', 'triggerBox'};

  @override
  void launch(GameSession session, Projectile p) {
    final place = p.load?.place;
    if (place == null) {
      p.done = true;
      return;
    }
    final jitter = session.data.projectiles[p.specId]!.params.number('jitter')!;
    double offset() => (session.random.nextDouble() * 2 * jitter - jitter).floorToDouble();
    final dx = offset();
    final dy = offset();
    p.state = LandmineState(p.position, place + Vec2(dx, dy));
  }

  @override
  void step(GameSession session, Projectile p, double dtMs) {
    final st = p.state! as LandmineState;
    final params = session.data.projectiles[p.specId]!.params;
    final throwMs = params.number('throwMs')!;
    if (!st.planted) {
      st.elapsedMs += dtMs;
      if (st.elapsedMs >= throwMs) {
        st.planted = true;
        p.position = st.to;
      } else {
        p.position = st.from.lerp(st.to, st.elapsedMs / throwMs);
      }
    }
    final interval = params.number('checkIntervalMs')!;
    final box = params.number('triggerBox')!;
    st.sinceCheckMs += dtMs;
    while (st.sinceCheckMs >= interval) {
      st.sinceCheckMs -= interval;
      if (!st.planted) continue;
      final trigger = session.creeps.where((c) => !c.gone && inBox(c.position, p.position, box));
      if (trigger.isEmpty) continue;
      detonate(session, p);
      if (session.config.profile.landmineBulletDamage) {
        session.hitCreep(trigger.first, p.damage, by: p.turretUid);
      }
      p.done = true;
      return;
    }
  }
}
