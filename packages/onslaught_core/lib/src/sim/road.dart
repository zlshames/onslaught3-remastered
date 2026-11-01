import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../data/map_definition.dart';
import '../math/geometry.dart';
import '../math/vec2.dart';

/// The road of a map as a length-parameterised polyline: creeps and shockwave
/// walkers move along it by distance, landmines and black holes snap to its
/// mine points.
@immutable
class Road {
  Road._(this.points, this._cumulative, this.minePoints);

  /// Builds the road for [map]. Mine points follow `RoadManager.roadBuild`:
  /// each segment gets `n = floor(length / minePointSpacing)` points at
  /// fractions `i / n` (i = 1…n) of the segment, rounded to whole pixels.
  factory Road.fromMap(MapDefinition map, {required double minePointSpacing}) {
    final pts = map.road;
    final cum = <double>[0];
    final mines = <Vec2>[];
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1];
      final b = pts[i];
      final len = b.distanceTo(a);
      cum.add(cum.last + len);
      final n = minePointSpacing > 0 ? (len / minePointSpacing).floor() : 0;
      for (var k = 1; k <= n; k++) {
        final p = a.lerp(b, k / n);
        mines.add(Vec2(roundHalfUp(p.x), roundHalfUp(p.y)));
      }
    }
    return Road._(List.unmodifiable(pts), List.unmodifiable(cum), List.unmodifiable(mines));
  }

  final List<Vec2> points;
  final List<double> _cumulative;

  /// Landmine / black-hole anchor points along the road.
  final List<Vec2> minePoints;

  /// Total length in px.
  double get length => _cumulative.last;

  /// Distance along the road at which waypoint [i] lies.
  double distanceAtWaypoint(int i) => _cumulative[i];

  /// The point [distance] px from the spawn (clamped to the ends).
  Vec2 pointAt(double distance) => _pointAt(points, _cumulative, distance);

  /// Shortest distance from [p] to the road's centre line.
  double distanceToCentreLine(Vec2 p) {
    var best = double.infinity;
    for (var i = 1; i < points.length; i++) {
      best = math.min(best, distanceToSegment(p, points[i - 1], points[i]));
    }
    return best;
  }
}

Vec2 _pointAt(List<Vec2> pts, List<double> cum, double d) {
  if (d <= 0) return pts.first;
  if (d >= cum.last) return pts.last;
  var lo = 0;
  var hi = cum.length - 1;
  while (hi - lo > 1) {
    final mid = (lo + hi) >> 1;
    if (cum[mid] <= d) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final seg = cum[hi] - cum[lo];
  final t = seg == 0 ? 0.0 : (d - cum[lo]) / seg;
  return pts[lo].lerp(pts[hi], t);
}
