import 'dart:math' as math;

import '../math/angles.dart';
import '../math/det_math.dart';
import '../math/vec2.dart';
import '../sim/entities.dart';

/// Degrees from [from] to [to], Flash convention: 0° = +x, clockwise (y is
/// down), in (−180, 180] (`OnslaughtObject.trigDegreesTo`).
double bearingDeg(Vec2 from, Vec2 to) => radToDeg(detAtan2(to.y - from.y, to.x - from.x));

/// What Flash stores when a `_rotation` is assigned: the angle wrapped into
/// (−180, 180].
double normalizeRotation(double deg) {
  final r = deg % 360;
  return r > 360 / 2 ? r - 360 : r;
}

/// [v] rotated by [deg] degrees (clockwise on screen).
Vec2 rotateVec(Vec2 v, double deg) {
  final rad = degToRad(deg);
  final c = detCos(rad);
  final s = detSin(rad);
  return Vec2(v.x * c - v.y * s, v.x * s + v.y * c);
}

/// Result of turning a weapon for one step.
typedef Bearing = ({double rotation, bool faced});

/// Turns a weapon at [rotation] toward [bearing] by at most
/// `rotateDegPerS × dtMs / 1000` degrees (`turrets/Turret.as:turretBearTowards`).
///
/// It snaps onto the bearing and reports `faced` when the raw difference
/// `bearing − rotation` is under [toleranceDeg] or under this step's turn.
/// Otherwise it turns the shorter way (clockwise on a tie). The raw
/// difference is not wrapped, so across the ±180° seam (e.g. 179° vs −179°)
/// it cannot snap and turns one full step past first, as the original does.
Bearing bearTowards({
  required double rotation,
  required double bearing,
  required double rotateDegPerS,
  required double dtMs,
  required double toleranceDeg,
}) {
  final step = dtMs / 1000 * rotateDegPerS;
  final diff = bearing - rotation;
  if (diff.abs() < toleranceDeg || diff.abs() < step.abs()) {
    return (rotation: bearing, faced: true);
  }
  final clockwise = (diff + 360) % 360;
  final anticlockwise = (360 - diff) % 360;
  final turned = anticlockwise < clockwise ? rotation - step : rotation + step;
  return (rotation: normalizeRotation(turned), faced: false);
}

/// How a target mode ranks candidates (`OnslaughtObject.targetAcquire`).
enum _Metric { distance, hp, speed, age }

const Map<String, (_Metric, bool)> _modes = {
  // id: (metric, minimise)
  'near': (_Metric.distance, true),
  'far': (_Metric.distance, false),
  'weak': (_Metric.hp, true),
  'strong': (_Metric.hp, false),
  'slow': (_Metric.speed, true),
  'fast': (_Metric.speed, false),
  'old': (_Metric.age, false),
  'young': (_Metric.age, true),
};

/// Whether [mode] is a target mode the rules know.
bool isTargetMode(String mode) => _modes.containsKey(mode);

/// Picks a target for a source at [from] with [range]
/// (`OnslaughtObject.targetAcquire` / `targetAcquireBySlice`):
///
/// 1. candidates inside the square `±range` box (inclusive), then
/// 2. strictly inside the circle (`dist² < range²`),
/// 3. ranked by [mode]: minimising modes keep a strictly smaller value
///    (the original starts from 1e38; any value above every candidate is
///    equivalent), maximising ones a strictly larger value starting
///    from 0, so a candidate whose value is 0 is never picked by them.
///
/// Ties go to the first candidate in [creeps] order. The original walks its
/// attacker array with `for…in` twice (building the slice, then ranking it);
/// assuming AS2 enumerates arrays newest-first (not observed in Flash), the
/// two passes cancel out and the oldest creep wins a tie. Unknown modes fall
/// back to `near`.
Creep? acquireTarget({
  required Iterable<Creep> creeps,
  required Vec2 from,
  required double range,
  required String mode,
  required double nowMs,
}) {
  final (metric, minimise) = _modes[mode] ?? _modes['near']!;
  final range2 = range * range;
  var best = minimise ? double.infinity : 0.0;
  Creep? pick;
  for (final c in creeps) {
    if (!c.targetable) continue;
    final dx = c.position.x - from.x;
    final dy = c.position.y - from.y;
    if (dx.abs() > range || dy.abs() > range) continue;
    final d2 = dx * dx + dy * dy;
    if (d2 >= range2) continue;
    final value = switch (metric) {
      _Metric.distance => d2,
      _Metric.hp => c.hp,
      _Metric.speed => c.speed,
      _Metric.age => c.ageMs(nowMs),
    };
    if (minimise ? value < best : value > best) {
      best = value;
      pick = c;
    }
  }
  return pick;
}

/// Whether a current target may be kept (`OnslaughtObject.targetInRange`):
/// still targetable, inside the `±range` box and within `range` (inclusive,
/// unlike acquisition).
bool targetStillInRange({required Creep target, required Vec2 from, required double range}) {
  if (!target.targetable) return false;
  final dx = target.position.x - from.x;
  final dy = target.position.y - from.y;
  if (dx.abs() > range || dy.abs() > range) return false;
  return math.sqrt(dx * dx + dy * dy) <= range;
}

/// The current target if it may be kept, otherwise a newly acquired one
/// (`OnslaughtObject.targetAvailableOrAcquire`).
Creep? keepOrAcquireTarget({
  required Creep? current,
  required Iterable<Creep> creeps,
  required Vec2 from,
  required double range,
  required String mode,
  required double nowMs,
}) {
  if (current != null && targetStillInRange(target: current, from: from, range: range)) {
    return current;
  }
  return acquireTarget(creeps: creeps, from: from, range: range, mode: mode, nowMs: nowMs);
}
