import 'angles.dart';
import 'det_math.dart';
import 'vec2.dart';

/// AS2 `Math.round`: halves round towards +∞ (also below zero, so −0.5
/// rounds to 0). Call `.toInt()` on the result for a whole number.
double roundHalfUp(double v) => (v + 0.5).floorToDouble();

/// Distance from [point] to the segment [a]–[b], ends included; the
/// distance to [a] when the segment has no length.
double distanceToSegment(Vec2 point, Vec2 a, Vec2 b) {
  final ab = b - a;
  final len2 = ab.lengthSquared;
  if (len2 == 0) return point.distanceTo(a);
  final ap = point - a;
  final t = ((ap.x * ab.x + ap.y * ab.y) / len2).clamp(0.0, 1.0);
  return point.distanceTo(a + ab * t);
}

/// The vector of [length] px along [headingDeg] (Flash convention: 0° = +x,
/// clockwise).
Vec2 headingVector(double headingDeg, double length) {
  final rad = degToRad(headingDeg);
  return Vec2(detCos(rad) * length, detSin(rad) * length);
}

/// The point [distance] px from [from] along [headingDeg]
/// (`OnslaughtObject.trigForwardAtAngle`).
Vec2 forwardFrom(Vec2 from, double headingDeg, double distance) =>
    from + headingVector(headingDeg, distance);
