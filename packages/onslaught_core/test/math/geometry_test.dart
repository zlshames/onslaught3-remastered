import 'dart:math' as math;

import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

/// `math/geometry.dart`: the shared maths helpers (audit D10).
void main() {
  test('roundHalfUp is AS2 Math.round: halves go towards +∞', () {
    expect(roundHalfUp(2.5), 3);
    expect(roundHalfUp(2.49), 2);
    expect(roundHalfUp(-2.5), -2);
    expect(roundHalfUp(-0.5), 0);
    expect(roundHalfUp(-2.51), -3);
    expect(roundHalfUp(7), 7);
    expect(roundHalfUp(1.5).toInt(), 2, reason: 'the int form the time-limit badge uses');
  });

  group('distanceToSegment', () {
    const a = Vec2(0, 0);
    const b = Vec2(10, 0);
    test('perpendicular inside the segment', () {
      expect(distanceToSegment(const Vec2(5, 3), a, b), 3);
    });
    test('beyond either end measures to that end', () {
      expect(distanceToSegment(const Vec2(-4, 3), a, b), 5);
      expect(distanceToSegment(const Vec2(13, 4), a, b), 5);
    });
    test('a zero-length segment measures to its point', () {
      expect(distanceToSegment(const Vec2(3, 4), a, a), 5);
    });
    test('matches the road centre line on every leg', () {
      // The road used its own copy of this formula before (audit D10).
      final road = Road.fromMap(
        const MapDefinition(
          id: 'm',
          name: 'm',
          base: Vec2(100, 100),
          road: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)],
        ),
        minePointSpacing: 0,
      );
      for (final p in const [Vec2(50, 7), Vec2(103, 40), Vec2(-3, -4), Vec2(120, 120)]) {
        final legs = math.min(
          distanceToSegment(p, const Vec2(0, 0), const Vec2(100, 0)),
          distanceToSegment(p, const Vec2(100, 0), const Vec2(100, 100)),
        );
        expect(road.distanceToCentreLine(p), legs);
      }
    });
  });

  group('headingVector and forwardFrom (Flash angles: 0° = +x, clockwise)', () {
    test('cardinal headings', () {
      final east = headingVector(0, 10);
      expect(east.x, 10);
      expect(east.y, 0);
      final south = headingVector(90, 10);
      expect(south.x, closeTo(0, 1e-12));
      expect(south.y, closeTo(10, 1e-12));
      final west = forwardFrom(const Vec2(5, 5), 180, 5);
      expect(west.x, closeTo(0, 1e-12));
      expect(west.y, closeTo(5, 1e-12));
    });
    test('forwardFrom is the start plus the heading vector, bit for bit', () {
      for (final h in const [-179.5, -45.0, 0.0, 33.3, 90.0, 179.0]) {
        const from = Vec2(12.25, -7.5);
        final v = headingVector(h, 17.5);
        expect(forwardFrom(from, h, 17.5), Vec2(from.x + v.x, from.y + v.y));
      }
    });
  });
}
