import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadClassicData());

  // A straight road along y = 100 and a base whose top-left is (600, 300).
  const map = MapDefinition(
    id: 'test',
    name: 'Test',
    base: Vec2(600, 300),
    road: [Vec2(0, 100), Vec2(720, 100)],
  );

  PlacementIssue? check(Vec2 at, {List<Vec2> others = const [], int? limit}) {
    final road = Road.fromMap(map, minePointSpacing: data.world.road.minePointSpacing);
    return placementIssue(
      world: data.world,
      road: road,
      base: map.base,
      at: at,
      others: others,
      turretLimit: limit,
    );
  }

  test('placement constants come from the data (BuildShape)', () {
    final p = data.world.placement;
    expect(p.turretSpacing, 36);
    expect(p.clearanceRadius, 19);
    expect(p.clearanceSamples, 8);
    expect(p.moveCost, 500);
    expect(data.world.road.outerWidth, 31);
  });

  test('an open spot is valid', () => expect(check(const Vec2(300, 250)), isNull));

  test('outside the play area', () {
    expect(check(const Vec2(-1, 250)), PlacementIssue.outsidePlayArea);
    expect(check(const Vec2(300, 481)), PlacementIssue.outsidePlayArea);
  });

  test('turret spacing is 36 px centre to centre (strictly less is rejected)', () {
    expect(
      check(const Vec2(300, 250), others: [const Vec2(335.9, 250)]),
      PlacementIssue.tooCloseToTurret,
    );
    expect(check(const Vec2(300, 250), others: [const Vec2(336, 250)]), isNull);
  });

  test('the turret limit counts existing turrets', () {
    expect(
      check(const Vec2(300, 250), others: [const Vec2(400, 400)], limit: 1),
      PlacementIssue.turretLimit,
    );
  });

  test('a sample point within 15.5 px of the road centre line blocks', () {
    // Samples at radius 19: the one straight up from y = 134 is at 115,
    // 15 px from the centre line.
    expect(check(const Vec2(300, 134)), PlacementIssue.blocked);
    // From y = 135 it is 16 px away; the diagonals are further.
    expect(check(const Vec2(300, 135)), isNull);
  });

  test('the base rectangle blocks like the road', () {
    expect(check(const Vec2(590, 320)), PlacementIssue.blocked); // +x sample at 609
    expect(check(const Vec2(580, 320)), isNull); // +x sample at 599
    expect(check(const Vec2(650, 300 + 82.15 + 19)), PlacementIssue.blocked);
  });

  test('clearance samples are the four axis points and four diagonals', () {
    final pts = clearanceSamples(Vec2.zero, 19, 8);
    expect(pts, hasLength(8));
    for (final p in pts) {
      expect(p.length, closeTo(19, 1e-9));
    }
    expect(pts[0].x, closeTo(19, 1e-9));
    expect(pts[2].y, closeTo(19, 1e-9));
    expect(pts[1].x, closeTo(19 * 0.7071067811865476, 1e-9));
  });
}
