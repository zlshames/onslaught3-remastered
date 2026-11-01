import 'package:onslaught_core/onslaught_core.dart';
import 'package:test/test.dart';

import '../support/repo_data.dart';

void main() {
  late GameData data;
  late MapEditorRules rules;
  setUpAll(() {
    data = loadClassicData();
    rules = data.world.editor;
  });

  MapDefinition map({Vec2 base = const Vec2(500, 300), List<Vec2>? road}) => MapDefinition(
    id: 'custom-test',
    name: 'Test',
    base: base,
    road: road ?? const [Vec2(0, 100), Vec2(400, 100), Vec2(505, 327)],
    builtIn: false,
  );

  group('editor geometry comes from the data (GameManagerMapping, Mapping frame)', () {
    test('grid, areas, anchor and entry points', () {
      expect(rules.gridSize, 20);
      expect(rules.startArea, const Area(0, 0, 720, 465));
      expect(rules.baseArea, const Area(0, 0, 720, 445));
      expect(rules.waypointArea, const Area(18, 18, 684, 444));
      expect(rules.baseAnchor, const Vec2(50, 47));
      expect(rules.baseEntries, hasLength(31));
      expect(rules.baseEntries.first, const Vec2(8.5, 20.5));
      expect(rules.baseEntries.last, const Vec2(5, 27));
      expect(rules.nudge, 1);
      expect(rules.nudgeFast, 10);
      expect(rules.minRoadLength, greaterThan(0));
      expect(rules.maxNameLength, greaterThan(0));
    });
  });

  group('validateMap', () {
    test('every built-in map passes', () {
      for (final m in data.maps.values) {
        expect(validateMap(m, data.world), isEmpty, reason: m.id);
      }
    });

    test('a start outside the start area is "no start" (mapSave)', () {
      final m = map(road: const [Vec2(100, 470), Vec2(400, 100), Vec2(505, 327)]);
      expect(validateMap(m, data.world), [MapProblem.noStart]);
    });

    test('a base whose centre is outside the base area is "no base"', () {
      // Anchor at (550, 447): 2 px below the base area.
      final m = map(base: const Vec2(500, 400), road: const [Vec2(0, 100), Vec2(505, 427)]);
      expect(validateMap(m, data.world), [MapProblem.noBase]);
      // On the edge it is still on the map (bounding-box hitTest).
      final edge = map(base: const Vec2(500, 398), road: const [Vec2(0, 100), Vec2(505, 425)]);
      expect(validateMap(edge, data.world), isEmpty);
    });

    test('a road shorter than the minimum is too short (remaster)', () {
      final short = rules.minRoadLength - 1;
      final m = map(road: [const Vec2(300, 100), Vec2(300 + short, 100)]);
      expect(validateMap(m, data.world), [MapProblem.tooShort]);
      final ok = map(road: [const Vec2(300, 100), Vec2(300 + rules.minRoadLength, 100)]);
      expect(validateMap(ok, data.world), isEmpty);
    });

    test('points off the play area are reported (malformed imports)', () {
      final m = map(road: const [Vec2(0, 100), Vec2(900, 100), Vec2(505, 327)]);
      expect(validateMap(m, data.world), [MapProblem.outside]);
    });

    test('problems are reported in order: start, base, length, outside', () {
      const m = MapDefinition(
        id: 'x',
        name: 'x',
        base: Vec2(700, 470),
        road: [Vec2(10, 470), Vec2(12, 470)],
      );
      expect(validateMap(m, data.world), [
        MapProblem.noStart,
        MapProblem.noBase,
        MapProblem.tooShort,
      ]);
    });
  });

  test('roadLength sums the segments', () {
    expect(roadLength(const [Vec2(0, 0), Vec2(30, 40), Vec2(30, 50)]), 60);
    expect(roadLength(const [Vec2(1, 1)]), 0);
  });

  group('snapToGrid (gridAlign: nearest corner, ties round down)', () {
    test('rounds to the nearest corner', () {
      expect(snapToGrid(const Vec2(29, 31), 20), const Vec2(20, 40));
      expect(snapToGrid(const Vec2(40, 0), 20), const Vec2(40, 0));
    });

    test('a tie keeps the lower corner (top-left is tried first)', () {
      expect(snapToGrid(const Vec2(30, 50), 20), const Vec2(20, 40));
    });

    test('negative positions snap too', () {
      expect(snapToGrid(const Vec2(-4, -16), 20), const Vec2(0, -20));
    });
  });

  group('baseEntryNearest (waypointClosestBasePoint)', () {
    test('picks the entry point nearest the last waypoint', () {
      const base = Vec2(300, 200);
      // Far to the left, level with BP29 (5, 47).
      expect(baseEntryNearest(base, const Vec2(0, 247), rules), const Vec2(305, 247));
      // Straight below the middle of the bottom edge: BP21 (55, 77).
      expect(baseEntryNearest(base, const Vec2(355, 400), rules), const Vec2(355, 277));
      // Above the top-left corner: BP2 (14.95, 17) is nearer than BP1.
      expect(baseEntryNearest(base, const Vec2(315, 0), rules), const Vec2(314.95, 217));
    });

    test('on a tie the earlier marker wins', () {
      const base = Vec2(0, 0);
      // Equidistant from BP19 (75, 77) and BP20 (65, 77).
      expect(baseEntryNearest(base, const Vec2(70, 200), rules), const Vec2(75, 77));
    });
  });
}
