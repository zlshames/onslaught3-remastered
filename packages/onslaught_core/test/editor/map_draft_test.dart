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

  group('start and base (GameManagerMapping onRelease + waypointPathUpdate)', () {
    test('a start inside the start area is placed, outside it leaves the map', () {
      final d = MapDraft.empty.withStart(const Vec2(0, 200), rules);
      expect(d.start, const Vec2(0, 200));
      expect(d.withStart(const Vec2(100, 470), rules).start, isNull);
    });

    test('the base is placed while its centre is in the base area', () {
      final d = MapDraft.empty.withBase(const Vec2(500, 300), rules);
      expect(d.base, const Vec2(500, 300));
      expect(d.withBase(const Vec2(500, 400), rules).base, isNull);
    });

    test('with the grid on they snap to the nearest corner first', () {
      final d = MapDraft.empty
          .withStart(const Vec2(9, 211), rules, snap: true)
          .withBase(const Vec2(511, 289), rules, snap: true);
      expect(d.start, const Vec2(0, 220));
      expect(d.base, const Vec2(520, 280));
    });
  });

  group('waypoints', () {
    test('a tap adds a waypoint at the end (waypointNew)', () {
      final d = MapDraft.empty
          .addWaypoint(const Vec2(100, 100), rules)
          .addWaypoint(const Vec2(200, 100), rules);
      expect(d.waypoints, const [Vec2(100, 100), Vec2(200, 100)]);
    });

    test('outside the start area or on an existing waypoint nothing is added', () {
      final d = MapDraft.empty.addWaypoint(const Vec2(100, 100), rules);
      expect(d.addWaypoint(const Vec2(100, 100), rules), same(d));
      expect(d.addWaypoint(const Vec2(100, 470), rules), same(d));
      // With the grid on the duplicate check sees the snapped position.
      expect(d.addWaypoint(const Vec2(103, 96), rules, snap: true), same(d));
    });

    test('a drag moves a waypoint; dropped off the waypoint area it is removed', () {
      final d = MapDraft.empty
          .addWaypoint(const Vec2(100, 100), rules)
          .addWaypoint(const Vec2(200, 100), rules);
      expect(d.moveWaypoint(0, const Vec2(150, 150), rules).waypoints, const [
        Vec2(150, 150),
        Vec2(200, 100),
      ]);
      expect(d.moveWaypoint(0, const Vec2(10, 150), rules).waypoints, const [Vec2(200, 100)]);
      expect(d.moveWaypoint(1, const Vec2(150, 470), rules).waypoints, const [Vec2(100, 100)]);
    });

    test('remove, insert and nudge', () {
      final d = MapDraft.empty
          .addWaypoint(const Vec2(100, 100), rules)
          .addWaypoint(const Vec2(300, 100), rules);
      expect(d.removeWaypoint(0).waypoints, const [Vec2(300, 100)]);
      expect(d.insertWaypoint(1, const Vec2(200, 100), rules).waypoints, const [
        Vec2(100, 100),
        Vec2(200, 100),
        Vec2(300, 100),
      ]);
      expect(() => d.insertWaypoint(3, Vec2.zero, rules), throwsRangeError);
      expect(
        d.nudgeWaypoint(0, const Vec2(-10, 1), data.world).waypoints.first,
        const Vec2(90, 101),
      );
      // Nudging stops at the play area's edge (waypointNudge).
      expect(d.nudgeWaypoint(0, const Vec2(-500, -500), data.world).waypoints.first, Vec2.zero);
    });

    test('align all snaps everything (gridAlignAll)', () {
      final d = const MapDraft(
        start: Vec2(3, 207),
        base: Vec2(498, 311),
        waypoints: [Vec2(109, 109), Vec2(289, 92)],
      ).alignAll(rules);
      expect(d.start, const Vec2(0, 200));
      expect(d.base, const Vec2(500, 320));
      expect(d.waypoints, const [Vec2(100, 100), Vec2(280, 100)]);
    });
  });

  group('road and midpoints (waypointPathUpdate, waypointInsertBetween)', () {
    const draft = MapDraft(
      start: Vec2(0, 100),
      base: Vec2(500, 300),
      waypoints: [Vec2(200, 100), Vec2(400, 100)],
    );

    test('the road runs start → waypoints → the base entry nearest the last waypoint', () {
      expect(draft.roadPoints(rules), const [
        Vec2(0, 100),
        Vec2(200, 100),
        Vec2(400, 100),
        // BP2 (14.95, 17) is the entry nearest (400, 100).
        Vec2(514.95, 317),
      ]);
    });

    test('with no waypoints the road goes from the start straight to the base', () {
      const d = MapDraft(start: Vec2(0, 300), base: Vec2(500, 300));
      // BP31 (5, 27) beats BP1 (8.5, 20.5) from (0, 300).
      expect(d.roadPoints(rules), const [Vec2(0, 300), Vec2(505, 327)]);
    });

    test('a missing start or base shortens the drawn road', () {
      expect(const MapDraft(base: Vec2(500, 300)).roadPoints(rules), isEmpty);
      expect(
        const MapDraft(waypoints: [Vec2(200, 100)], base: Vec2(500, 300)).roadPoints(rules),
        hasLength(2),
      );
      expect(
        const MapDraft(start: Vec2(0, 100), waypoints: [Vec2(200, 100)]).roadPoints(rules),
        const [Vec2(0, 100), Vec2(200, 100)],
      );
    });

    test('each segment has a handle that inserts at the right index', () {
      final handles = draft.midpoints(rules);
      expect(handles.map((h) => h.place), [0, 1, 2]);
      expect(handles.first.at, const Vec2(100, 100));
      final inserted = draft.insertWaypoint(handles[1].place, handles[1].at, rules);
      expect(inserted.waypoints, const [Vec2(200, 100), Vec2(300, 100), Vec2(400, 100)]);
      // Without a start the first handle sits between the first two waypoints.
      const noStart = MapDraft(waypoints: [Vec2(200, 100), Vec2(400, 100)]);
      expect(noStart.midpoints(rules).single, const MidpointHandle(1, Vec2(300, 100)));
    });
  });

  group('map round trip (mapSave / mapLoad)', () {
    test('toMap needs a start and a base', () {
      expect(const MapDraft(start: Vec2(0, 100)).toMap(rules, id: 'a', name: 'A'), isNull);
    });

    test('a saved draft loads back to the same draft and validates', () {
      const draft = MapDraft(
        start: Vec2(0, 100),
        base: Vec2(500, 300),
        waypoints: [Vec2(200, 100), Vec2(400, 100)],
      );
      final map = draft.toMap(rules, id: 'custom-a', name: 'A')!;
      expect(map.builtIn, isFalse);
      expect(map.road.last, const Vec2(514.95, 317));
      expect(validateMap(map, data.world), isEmpty);
      expect(MapDraft.fromMap(map), draft);
    });

    test('loading a built-in map keeps its start and waypoints and drops the road end', () {
      final classic = data.maps['map1']!;
      final d = MapDraft.fromMap(classic);
      expect(d.start, classic.road.first);
      expect(d.base, classic.base);
      expect(d.waypoints, classic.road.sublist(1, classic.road.length - 1));
    });

    test('equality is by value', () {
      expect(
        const MapDraft(waypoints: [Vec2(1, 2)]),
        MapDraft(waypoints: [const Vec2(1, 2)].toList()),
      );
      expect(MapDraft.empty.isEmpty, isTrue);
      expect(const MapDraft(start: Vec2(1, 1)).isEmpty, isFalse);
    });
  });
}
