import 'dart:math' as math;

import 'package:meta/meta.dart';

/// An immutable 2D vector in world pixels (origin top-left, y down), the unit
/// every range, speed and radius in the data uses.
@immutable
class Vec2 {
  const Vec2(this.x, this.y);

  static const Vec2 zero = Vec2(0, 0);

  final double x;
  final double y;

  Vec2 operator +(Vec2 o) => Vec2(x + o.x, y + o.y);
  Vec2 operator -(Vec2 o) => Vec2(x - o.x, y - o.y);
  Vec2 operator *(double s) => Vec2(x * s, y * s);

  double get length => math.sqrt(x * x + y * y);
  double get lengthSquared => x * x + y * y;

  double distanceTo(Vec2 o) => (this - o).length;
  double distanceSquaredTo(Vec2 o) => (this - o).lengthSquared;

  /// Linear interpolation from this to [o] at parameter [t] in [0, 1].
  Vec2 lerp(Vec2 o, double t) => Vec2(x + (o.x - x) * t, y + (o.y - y) * t);

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  @override
  bool operator ==(Object other) => other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}
