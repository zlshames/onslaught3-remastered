import '../../math/geometry.dart';
import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import '../targeting_rules.dart';
import 'ordnance.dart';
import 'rocket_state.dart';

/// Red's rocket and every rocket-engine projectile (`RocketEngine`). Each
/// step, in the original's order:
///
/// 1. if it is marked for off-screen removal and has left the 720 × 535
///    stage (plus its width), it is removed;
/// 2. it keeps its target while it is within `acquireRange`, else takes the
///    nearest creep in that range (`targetAvailableOrAcquire`, "near");
/// 3. a held rocket (`holding_initially`) circles regardless, until the
///    turret dispatches it;
/// 4. with a target it turns toward it at `turnRate` (shortest way, the
///    unwrapped difference as the turrets use) and hits when the target is
///    closer than this step's travel or than `impactRadius` (it snaps onto
///    the target first); otherwise it moves along its heading from before
///    the turn;
/// 5. with no target, a holding-capable rocket circles (radius
///    speed / turn rate ≈ 53 px, through the point where it began), any
///    other flies straight and is marked for off-screen removal.
///
/// The original lets a rocket circle with no target until a creep comes
/// within range, and every shipped profile does the same. Under
/// `RulesProfile.holdingRocketLifetime` (off in both; kept for a future
/// profile) it is removed after `holdingLifetimeMs` instead.
///
/// Combo rockets ([Projectile.load]) may fly at their own speed, set off a
/// blast and a cluster on impact before the hit (`targetHit`:
/// `projectileBlast`, `projectileCluster`, `attackerHit`), and carry
/// on-board weapons that work only while they have a target: a laser that
/// fires at it while it is within the laser range (measured before this
/// step's move) and its interval has passed since the last one (or the
/// launch), and rockets that fire at it every interval whatever the range,
/// heading straight at it and inheriting holding. These are checked even on
/// the step the rocket hits, as the original's update carries on after
/// `removeMyself`. Under `RulesProfile.laserRocketLaserBlast` a laser
/// rocket's impact also fires its laser blast: one laser beam with the
/// laser-blast damage at each of the nearest creeps within the laser-blast
/// range, up to the laser-blast count.
class RocketKind implements ProjectileKind {
  const RocketKind();

  @override
  String get id => 'rocket';

  @override
  Set<String>? get paramKeys => const {
    'speed',
    'turnRate',
    'impactRadius',
    'acquireRange',
    'tickMs',
    'tickJitterMs',
    'smokeMax',
    'noRotate',
    'offscreenLock',
    'laserRange',
    'laserRate',
    'subRocketIntervalMs',
    'screenWidth',
    'screenHeight',
    'offscreenMargin',
    'holdingLifetimeMs',
  };

  /// The orbit direction is drawn at launch (`holding_dir`, 50/50).
  @override
  void launch(GameSession session, Projectile p) {
    RocketState.of(p).holdingDir = session.random.nextDouble() >= 1 / 2 ? -1 : 1;
  }

  @override
  void step(GameSession session, Projectile p, double dtMs) {
    final params = session.data.projectiles[p.specId]!.params;
    final rs = RocketState.of(p);
    if ((rs.offscreenRemove || (params.boolean('offscreenLock') ?? false)) &&
        _offStage(
          p.position,
          params.number('screenWidth')!,
          params.number('screenHeight')!,
          params.number('offscreenMargin')!,
        )) {
      p.done = true;
      return;
    }
    final now = session.clock.nowMs;
    final load = p.load;
    final travel = dtMs / 1000 * (load?.speed ?? params.number('speed')!);
    final turnRate = params.number('turnRate')!;
    final turn = dtMs / 1000 * turnRate;
    final forward = headingVector(p.heading, travel);
    final noRotate = params.boolean('noRotate') ?? false;

    final target = keepOrAcquireTarget(
      current: session.creepByUid(p.targetUid),
      creeps: session.creeps,
      from: p.position,
      range: params.number('acquireRange')!,
      mode: _nearest,
      nowMs: now,
    );
    p.targetUid = target?.uid;

    if (rs.holdingInitially) {
      p
        ..position = p.position + forward
        ..heading = normalizeRotation(p.heading + turn * rs.holdingDir);
      return;
    }
    if (target != null) {
      rs.orbitSinceMs = null;
      if (!noRotate) {
        p.heading = bearTowards(
          rotation: p.heading,
          bearing: bearingDeg(p.position, target.position),
          rotateDegPerS: turnRate,
          dtMs: dtMs,
          toleranceDeg: 0,
        ).rotation;
      }
      final d = target.position - p.position;
      final d2 = d.x * d.x + d.y * d.y;
      final impact = params.number('impactRadius')!;
      if (d2 < travel * travel || d2 < impact * impact) {
        p.position = target.position;
        _hit(session, p, target);
      } else {
        p.position = p.position + forward;
      }
      if (load != null) _onboard(session, p, load, target, d2, now);
      return;
    }
    if (rs.holdingCapable) {
      rs.offscreenRemove = false;
      p.position = p.position + forward;
      if (!noRotate) p.heading = normalizeRotation(p.heading + turn * rs.holdingDir);
      final since = rs.orbitSinceMs ??= now;
      final lifetime = params.number('holdingLifetimeMs');
      if (session.config.profile.holdingRocketLifetime &&
          lifetime != null &&
          now - since >= lifetime) {
        p.done = true;
      }
      return;
    }
    p.position = p.position + forward;
    rs.offscreenRemove = true;
  }

  /// `RocketEngine.targetHit`: blast, cluster, hit, gone.
  static void _hit(GameSession s, Projectile p, Creep target) {
    detonate(s, p);
    s.hitCreep(target, p.damage, by: p.turretUid);
    final load = p.load;
    final laserBlast = load?.laserBlast;
    if (laserBlast != null && laserBlast.qty > 0) _laserBlast(s, p, load!.laser, laserBlast);
    p.done = true;
  }

  /// `RocketEngine.laserFire` / `rocketFire`.
  static void _onboard(
    GameSession s,
    Projectile p,
    Ordnance load,
    Creep target,
    double d2,
    double now,
  ) {
    final laser = load.laser;
    if (laser != null &&
        d2 <= laser.range * laser.range &&
        now - load.laserFiredAtMs >= laser.intervalMs) {
      load.laserFiredAtMs = now;
      launchChild(
        s,
        specId: laser.projectile,
        at: p.position,
        heading: 0,
        damage: laser.damage,
        targetUid: target.uid,
        turretUid: p.turretUid,
        poison: p.poison,
      );
    }
    final rocket = load.subRocket;
    if (rocket != null && now - load.subRocketFiredAtMs >= rocket.intervalMs) {
      load.subRocketFiredAtMs = now;
      launchChild(
        s,
        specId: rocket.projectile,
        at: p.position,
        heading: bearingDeg(p.position, target.position),
        damage: rocket.damage,
        targetUid: target.uid,
        turretUid: p.turretUid,
        holdingCapable: RocketState.of(p).holdingCapable,
      );
    }
  }

  /// The `laserRocketLaserBlast` fix's reading of the `laserblast_*` data.
  static void _laserBlast(GameSession s, Projectile p, OnboardWeapon? laser, LaserBlastLoad blast) {
    final range = blast.range;
    // Nearest first; equal distances in uid order, so the order is the same
    // on every platform (`List.sort` is not stable).
    final near =
        [
          for (final c in s.creeps)
            if (c.targetable && p.position.distanceTo(c.position) <= range) c,
        ]..sort((a, b) {
          final byDistance = p.position
              .distanceTo(a.position)
              .compareTo(p.position.distanceTo(b.position));
          return byDistance != 0 ? byDistance : a.uid.compareTo(b.uid);
        });
    for (final c in near.take(blast.qty)) {
      launchChild(
        s,
        specId: laser?.projectile ?? s.data.comboDefaults.string('laserType')!,
        at: p.position,
        heading: 0,
        damage: blast.damage,
        targetUid: c.uid,
        turretUid: p.turretUid,
      );
    }
  }

  static const String _nearest = 'near';

  static bool _offStage(Vec2 at, double width, double height, double margin) =>
      at.x < -margin || at.x > width + margin || at.y < -margin || at.y > height + margin;
}
