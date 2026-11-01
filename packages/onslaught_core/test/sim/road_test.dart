import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

void main() {
  const map = MapDefinition(
    id: 'l',
    name: 'L',
    base: Vec2(100, 100),
    road: [Vec2(0, 0), Vec2(100, 0), Vec2(100, 100)],
  );
  final road = Road.fromMap(map, minePointSpacing: 4);

  test('length and point lookup by distance', () {
    expect(road.length, 200);
    expect(road.pointAt(50), const Vec2(50, 0));
    expect(road.pointAt(150), const Vec2(100, 50));
    expect(road.pointAt(-5), const Vec2(0, 0));
    expect(road.pointAt(999), const Vec2(100, 100));
    expect(road.distanceAtWaypoint(1), 100);
  });

  test('mine points: floor(len / spacing) per segment, rounded (RoadManager.roadBuild)', () {
    expect(road.minePoints.length, 50);
    expect(road.minePoints.first, const Vec2(4, 0));
    expect(road.minePoints[24], const Vec2(100, 0));
    expect(road.minePoints.last, const Vec2(100, 100));
    // A 10 px segment gets floor(10/4) = 2 points at 5 and 10 px.
    const short = MapDefinition(
      id: 's',
      name: 'S',
      base: Vec2(0, 0),
      road: [Vec2(0, 0), Vec2(10, 0)],
    );
    expect(Road.fromMap(short, minePointSpacing: 4).minePoints, const [Vec2(5, 0), Vec2(10, 0)]);
    // Halves round up like AS2 Math.round.
    const odd = MapDefinition(id: 'o', name: 'O', base: Vec2(0, 0), road: [Vec2(0, 0), Vec2(9, 0)]);
    expect(Road.fromMap(odd, minePointSpacing: 4).minePoints, const [Vec2(5, 0), Vec2(9, 0)]);
  });

  test('distance to centre line', () {
    expect(road.distanceToCentreLine(const Vec2(50, 10)), 10);
    expect(road.distanceToCentreLine(const Vec2(110, 50)), 10);
    expect(road.distanceToCentreLine(const Vec2(-3, -4)), 5);
  });
}
