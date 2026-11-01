import 'package:flutter_test/flutter_test.dart';
import 'package:onslaught3_remastered/features/editor/editor_controller.dart';
import 'package:onslaught_core/onslaught_core.dart';

import '../../support/test_data.dart';

void main() {
  late GameData data;
  setUpAll(() => data = loadTestGameData());

  MapEditorController editor([MapDefinition? map]) =>
      MapEditorController(world: data.world, map: map);

  /// Start, base and two waypoints: a valid map.
  MapEditorController built() => editor()
    ..placeStart(const Vec2(0, 100))
    ..placeBase(const Vec2(550, 347))
    ..tap(const Vec2(200, 100), 10)
    ..tap(const Vec2(200, 300), 10);

  test('a new map is empty, clean and reports the missing start and base', () {
    final c = editor();
    expect(c.draft.isEmpty, isTrue);
    expect(c.dirty, isFalse);
    expect(c.canUndo, isFalse);
    expect(c.problems, [MapProblem.noStart, MapProblem.noBase]);
    expect(c.snap, isFalse, reason: 'the grid is off by default (grid_snap = false)');
  });

  test('palette drops place the start and the base (by its centre)', () {
    final c = built();
    expect(c.draft.start, const Vec2(0, 100));
    expect(c.draft.base, const Vec2(500, 300));
    expect(c.draft.waypoints, const [Vec2(200, 100), Vec2(200, 300)]);
    expect(c.problems, isEmpty);
    expect(c.dirty, isTrue);
  });

  test('every edit is undoable and redoable; a new edit clears redo', () {
    final c = built();
    c.undo();
    expect(c.draft.waypoints, const [Vec2(200, 100)]);
    c.undo();
    expect(c.draft.waypoints, isEmpty);
    expect(c.canRedo, isTrue);
    c.redo();
    expect(c.draft.waypoints, const [Vec2(200, 100)]);
    c.tap(const Vec2(400, 400), 10);
    expect(c.canRedo, isFalse);
    while (c.canUndo) {
      c.undo();
    }
    expect(c.draft, MapDraft.empty);
  });

  test('taps: a waypoint toggles selection, a "+" inserts, a no-op adds no history', () {
    final c = built();
    c.tap(const Vec2(203, 98), 10);
    expect(c.selected, 0);
    c.tap(const Vec2(203, 98), 10);
    expect(c.selected, isNull);
    final before = c.draft;
    c.tap(const Vec2(100, 100), 10); // the "+" between the start and waypoint 0
    expect(c.draft.waypoints.first, const Vec2(100, 100));
    c.undo();
    expect(c.draft, before);
    c.tap(const Vec2(300, 470), 10); // below the start area: nothing is added
    expect(c.draft, before);
  });

  test('delete and nudge act on the selected waypoint', () {
    final c = built()..select(1);
    c.nudgeSelected(const Vec2(10, -1));
    expect(c.draft.waypoints[1], const Vec2(210, 299));
    c.deleteSelected();
    expect(c.draft.waypoints, const [Vec2(200, 100)]);
    expect(c.selected, isNull);
    c.deleteSelected(); // nothing selected
    expect(c.draft.waypoints, hasLength(1));
  });

  test('dragging moves the item live and commits once on release', () {
    final c = built();
    final history = c.canUndo;
    c.beginDrag(const WaypointTarget(1), const Vec2(205, 305));
    c.dragTo(const Vec2(305, 255));
    expect(c.shown.waypoints[1], const Vec2(300, 250), reason: 'keeps the grab offset');
    expect(c.draft.waypoints[1], const Vec2(200, 300), reason: 'not committed yet');
    expect(c.drag!.valid, isTrue);
    c.endDrag();
    expect(c.draft.waypoints[1], const Vec2(300, 250));
    expect(history, isTrue);
    c.undo();
    expect(c.draft.waypoints[1], const Vec2(200, 300));
  });

  test('a waypoint dragged off the map is removed; the drag says so first', () {
    final c = built();
    c.beginDrag(const WaypointTarget(0), const Vec2(200, 100));
    c.dragTo(const Vec2(5, 100));
    expect(c.drag!.valid, isFalse);
    c.endDrag();
    expect(c.draft.waypoints, const [Vec2(200, 300)]);
  });

  test('the start and base drag back off the map when dropped outside their areas', () {
    final c = built();
    c.beginDrag(const StartTarget(), const Vec2(0, 100));
    c.dragTo(const Vec2(0, 470));
    expect(c.drag!.valid, isFalse);
    c.endDrag();
    expect(c.draft.start, isNull);
    c.beginDrag(const BaseTarget(), const Vec2(520, 320));
    c.dragTo(const Vec2(540, 340));
    c.endDrag();
    expect(c.draft.base, const Vec2(520, 320));
  });

  test('dragging a "+" inserts its waypoint and moves it, as one undo step', () {
    final c = built();
    final before = c.draft;
    final plus = c.draft.midpoints(c.rules)[1]; // between the two waypoints
    expect(c.hitTest(plus.at, 10), isA<MidpointTarget>());
    c.beginDrag(MidpointTarget(plus), plus.at);
    c.dragTo(const Vec2(350, 200));
    c.endDrag();
    expect(c.draft.waypoints, const [Vec2(200, 100), Vec2(350, 200), Vec2(200, 300)]);
    c.undo();
    expect(c.draft, before);
  });

  test('with the grid on, drops snap to it; align all snaps everything', () {
    final c = editor()..toggleSnap();
    c.placeStart(const Vec2(3, 97));
    expect(c.draft.start, const Vec2(0, 100));
    c
      ..toggleSnap()
      ..tap(const Vec2(211, 109), 10)
      ..alignAll();
    expect(c.draft.waypoints.single, const Vec2(220, 100));
  });

  test('hit testing prefers waypoints, then handles, the start and the base', () {
    final c = built();
    expect(c.hitTest(const Vec2(200, 105), 10), isA<WaypointTarget>());
    expect(c.hitTest(const Vec2(0, 104), 10), isA<StartTarget>());
    expect(c.hitTest(const Vec2(560, 340), 10), isA<BaseTarget>());
    expect(c.hitTest(const Vec2(400, 50), 10), isNull);
  });

  test('saving records the name and id and makes the map clean', () {
    final c = built();
    final map = c.buildMap(id: 'custom-a', name: 'A')!;
    c.markSaved(map);
    expect(c.dirty, isFalse);
    expect((c.name, c.savedId), ('A', 'custom-a'));
    c.tap(const Vec2(400, 400), 10);
    expect(c.dirty, isTrue);
  });

  test('opening a saved map loads its draft and is clean', () {
    final map = built().buildMap(id: 'custom-a', name: 'A')!;
    final c = editor(map);
    expect(c.draft, MapDraft.fromMap(map));
    expect(c.dirty, isFalse);
    expect((c.name, c.savedId), ('A', 'custom-a'));
  });

  test('keyboard placement: a waypoint at the end, or at the start with Shift', () {
    final c = built()
      ..addWaypoint(const Vec2(400, 300))
      ..insertWaypointAtStart(const Vec2(100, 200));
    expect(c.draft.waypoints.first, const Vec2(100, 200));
    expect(c.draft.waypoints.last, const Vec2(400, 300));
  });

  test('clear empties the map and can be undone', () {
    final c = built()..clear();
    expect(c.draft.isEmpty, isTrue);
    c.undo();
    expect(c.draft.waypoints, hasLength(2));
  });
}
