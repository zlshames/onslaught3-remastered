import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import '../targeting_rules.dart';
import 'blasts.dart';
import 'ordnance.dart';

/// The Yellow shockwave blast (`blasts/BlastShockwave`, `Shockwave`).
///
/// It moves onto its target's position (`preBlast`), sends its road
/// walkers, then grows, deals its damage and fades like a plain blast (its
/// poison, 75 from the combo, divides the speed).
///
/// Two walkers start where it went off: one walks the road toward the base
/// (from the waypoint the target was heading for), one toward the spawn
/// (from the waypoint before it). In the original the spawn-ward one
/// removes itself while it is being made, so only the base-ward walker
/// runs; `RulesProfile.shockwaveBothWalkers` sends both. See [stepWalker].
///
/// Its 15 decorative sparks are left to the view.
class ShockwaveKind implements BlastKind {
  const ShockwaveKind();

  @override
  String get id => 'shockwave';

  @override
  Set<String>? get paramKeys => const {
    ...PlainBlastKind.blastParamKeys,
    'defaultPoison',
    'walkerSpeed',
    'walkerDurationMs',
    'walkerTickMs',
    'walkerHitBox',
    'decorativeSparks',
  };

  @override
  void start(GameSession session, Blast blast) {
    final target = session.creepByUid(blast.targetUid);
    if (target != null) {
      blast.position = target.position;
      _walker(session, blast, direction: 1, waypoint: target.waypoint);
      if (session.config.profile.shockwaveBothWalkers) {
        _walker(session, blast, direction: -1, waypoint: target.waypoint - 1);
      }
    }
    startGrowth(session, blast);
  }

  @override
  void step(GameSession session, Blast blast, double dtMs) => advanceGrowth(session, blast, dtMs);

  static void _walker(GameSession s, Blast b, {required int direction, required int waypoint}) {
    if (waypoint < 0 || waypoint >= s.road.points.length) return;
    final w = ShockwaveWalker(
      uid: s.nextUid(),
      specId: b.specId,
      position: b.position,
      direction: direction,
      waypoint: waypoint,
      damage: b.damage,
      poison: b.poison,
      turretUid: b.turretUid,
      startedAtMs: s.clock.nowMs,
    );
    s.addWalker(w);
    _leg(s, w);
  }

  /// `Shockwave.updateMove`: a straight leg to the next road point at the
  /// walker speed, no jitter.
  static void _leg(GameSession s, ShockwaveWalker w) {
    final speed = s.data.blasts[w.specId]!.params.number('walkerSpeed')!;
    final point = s.road.points[w.waypoint];
    w
      ..legFrom = w.position
      ..legTo = point
      ..legDurationMs = w.position.distanceTo(point) / speed * Duration.millisecondsPerSecond
      ..legElapsedMs = 0
      ..heading = bearingDeg(w.position, point);
  }
}

/// Moves shockwave walker [w] by [dtMs] game ms (`Shockwave.update`,
/// `shockWaveSpark`).
///
/// * It walks the road point to point at `walkerSpeed`; past the last
///   point (toward the base) or the first (toward the spawn) it is gone.
/// * Every `walkerTickMs` from its start it zaps every creep inside the
///   `±walkerHitBox` square: with `f = 1 − age / walkerDurationMs`, a hit
///   of `f × damage` (no turret credit; `shockwaveCredit` credits the
///   leader) and then a slow of `f × poison`, subtracted.
/// * After `walkerDurationMs` it is gone.
///
/// The original's zap interval is real time skipped while paused; here it
/// is game time.
void stepWalker(GameSession s, ShockwaveWalker w, double dtMs) {
  final params = s.data.blasts[w.specId]!.params;
  var remaining = dtMs;
  while (remaining > 0 && !w.done) {
    final left = w.legDurationMs - w.legElapsedMs;
    if (remaining < left) {
      w
        ..legElapsedMs += remaining
        ..position = w.legFrom.lerp(w.legTo, w.legElapsedMs / w.legDurationMs);
      break;
    }
    remaining -= left;
    w
      ..position = w.legTo
      ..waypoint += w.direction;
    if (w.waypoint < 0 || w.waypoint >= s.road.points.length) {
      w.done = true;
    } else {
      ShockwaveKind._leg(s, w);
    }
  }
  final tick = params.number('walkerTickMs')!;
  final duration = params.number('walkerDurationMs')!;
  final box = params.number('walkerHitBox')!;
  final credit = s.config.profile.shockwaveCredit ? w.turretUid : null;
  w.sinceTickMs += dtMs;
  while (!w.done && w.sinceTickMs >= tick) {
    w
      ..sinceTickMs -= tick
      ..zaps += 1;
    final f = 1 - w.zaps * tick / duration;
    final damage = f * w.damage;
    final poison = f * w.poison;
    for (final c in List.of(s.creeps)) {
      if (c.gone || !inBox(c.position, w.position, box)) continue;
      s
        ..hitCreep(c, damage < 0 ? 0 : damage, by: credit)
        ..slowCreep(c, poison < 0 ? 0 : poison, subtract: true);
    }
  }
  if (s.clock.nowMs - w.startedAtMs >= duration) w.done = true;
}
