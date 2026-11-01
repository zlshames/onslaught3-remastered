import 'package:flutter/foundation.dart';
import 'package:onslaught_core/onslaught_core.dart';

/// Something on the editor canvas a finger can grab.
sealed class EditorTarget {
  const EditorTarget();
}

final class StartTarget extends EditorTarget {
  const StartTarget();
}

final class BaseTarget extends EditorTarget {
  const BaseTarget();
}

final class WaypointTarget extends EditorTarget {
  const WaypointTarget(this.index);
  final int index;
}

/// A "+" handle: a tap inserts a waypoint, a drag inserts and moves it.
final class MidpointTarget extends EditorTarget {
  const MidpointTarget(this.handle);
  final MidpointHandle handle;
}

/// What is being dragged right now and where the finger has it.
@immutable
class EditorDrag {
  const EditorDrag(this.target, this.at, {required this.valid});

  /// [StartTarget], [BaseTarget] or [WaypointTarget] (a dragged midpoint
  /// becomes the waypoint it inserted).
  final EditorTarget target;

  /// Where it would drop: the start or a waypoint's position, the base's
  /// top-left corner.
  final Vec2 at;

  /// False when dropping here takes it off the map (or removes a
  /// waypoint).
  final bool valid;
}

/// The map editor's state (`GameManagerMapping`): the [MapDraft] with
/// undo/redo, the grid toggle, the selected waypoint, an in-progress drag,
/// and the name and id the map was last saved under. Widgets read it and
/// call its edits; it holds no Flutter widgets.
class MapEditorController extends ChangeNotifier {
  MapEditorController({required this.world, MapDefinition? map})
    : _draft = map == null ? MapDraft.empty : MapDraft.fromMap(map),
      _savedDraft = map == null ? MapDraft.empty : MapDraft.fromMap(map),
      name = map?.name ?? '',
      savedId = map?.id;

  final WorldDef world;

  /// Longest undo history kept.
  static const int historyLimit = 200;

  MapEditorRules get rules => world.editor;

  MapDraft _draft;
  MapDraft _savedDraft;
  final List<MapDraft> _undo = [];
  final List<MapDraft> _redo = [];

  /// The committed map (what undo/redo step through).
  MapDraft get draft => _draft;

  /// The name the map was last saved as ('' for a new map).
  String name;

  /// The library id the map was last saved under; null until first saved.
  String? savedId;

  bool _snap = false;

  /// The grid toggle (`MapGridSnap`); off by default as in the original.
  bool get snap => _snap;

  int? _selected;

  /// The selected waypoint (`waypoint_cur`).
  int? get selected => _selected;

  EditorDrag? _drag;
  EditorDrag? get drag => _drag;
  MapDraft? _dragBase;
  Vec2 _grab = Vec2.zero;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Changed since it was last saved (or opened).
  bool get dirty => _draft != _savedDraft;

  /// The draft as drawn: the committed one, with an in-progress drag
  /// applied at the finger's position.
  MapDraft get shown {
    final d = _drag;
    final base = _dragBase ?? _draft;
    if (d == null) return base;
    return switch (d.target) {
      StartTarget() => MapDraft(start: d.at, base: base.base, waypoints: base.waypoints),
      BaseTarget() => MapDraft(start: base.start, base: d.at, waypoints: base.waypoints),
      WaypointTarget(:final index) => MapDraft(
        start: base.start,
        base: base.base,
        waypoints: [...base.waypoints]..[index] = d.at,
      ),
      MidpointTarget() => base,
    };
  }

  /// Why the map cannot be saved yet, in the order the original reports
  /// them; empty once it can.
  List<MapProblem> get problems {
    final map = buildMap(id: 'draft', name: 'draft');
    if (map == null) {
      return [
        if (_draft.start == null) MapProblem.noStart,
        if (_draft.base == null) MapProblem.noBase,
      ];
    }
    return validateMap(map, world);
  }

  MapDefinition? buildMap({required String id, required String name}) =>
      _draft.toMap(rules, id: id, name: name);

  // ------------------------------------------------------------ history

  void _commit(MapDraft next) {
    if (next == _draft) return;
    _undo.add(_draft);
    if (_undo.length > historyLimit) _undo.removeAt(0);
    _redo.clear();
    _draft = next;
    if (_selected != null && _selected! >= next.waypoints.length) _selected = null;
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _redo.add(_draft);
    _draft = _undo.removeLast();
    _selected = null;
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _undo.add(_draft);
    _draft = _redo.removeLast();
    _selected = null;
    notifyListeners();
  }

  // ------------------------------------------------------------ hit tests

  /// What is under world point [p], with [radius] world px of finger slop:
  /// waypoints (the most recent on top), then midpoint handles, the start,
  /// then the base.
  EditorTarget? hitTest(Vec2 p, double radius) {
    final d = _draft;
    final r2 = radius * radius;
    for (var i = d.waypoints.length - 1; i >= 0; i--) {
      if (d.waypoints[i].distanceSquaredTo(p) <= r2) return WaypointTarget(i);
    }
    for (final h in d.midpoints(rules)) {
      if (h.at.distanceSquaredTo(p) <= r2) return MidpointTarget(h);
    }
    if (d.start != null && d.start!.distanceSquaredTo(p) <= r2) return const StartTarget();
    final b = d.base;
    final placement = world.placement;
    if (b != null &&
        p.x >= b.x - radius / 2 &&
        p.y >= b.y - radius / 2 &&
        p.x <= b.x + placement.baseWidth + radius / 2 &&
        p.y <= b.y + placement.baseHeight + radius / 2) {
      return const BaseTarget();
    }
    return null;
  }

  // ------------------------------------------------------------ edits

  /// A tap at [p] (world px): a waypoint toggles its selection
  /// (`waypointSelect`), a "+" handle inserts a waypoint, the start or base
  /// does nothing, and empty ground adds a waypoint at the end of the road.
  void tap(Vec2 p, double radius) {
    switch (hitTest(p, radius)) {
      case WaypointTarget(:final index):
        _selected = _selected == index ? null : index;
        notifyListeners();
      case MidpointTarget(:final handle):
        _selected = null;
        _commit(_draft.insertWaypoint(handle.place, handle.at, rules, snap: _snap));
      case StartTarget() || BaseTarget():
        break;
      case null:
        final next = _draft.addWaypoint(p, rules, snap: _snap);
        _selected = null;
        if (next == _draft) {
          notifyListeners();
        } else {
          _commit(next);
        }
    }
  }

  /// Puts the start at [p] (the palette, or key 1 at the cursor).
  void placeStart(Vec2 p) => _commit(_draft.withStart(p, rules, snap: _snap));

  /// Puts the base with its centre at [centre] (the palette, or key 3).
  void placeBase(Vec2 centre) =>
      _commit(_draft.withBase(centre - rules.baseAnchor, rules, snap: _snap));

  /// Adds a waypoint at [p] (key 2 at the cursor).
  void addWaypoint(Vec2 p) => _commit(_draft.addWaypoint(p, rules, snap: _snap));

  /// Inserts a waypoint at [p] as the road's first (Shift+2,
  /// `waypointInsertAtStart`).
  void insertWaypointAtStart(Vec2 p) => _commit(_draft.insertWaypoint(0, p, rules, snap: _snap));

  void select(int? index) {
    _selected = index;
    notifyListeners();
  }

  /// Removes the selected waypoint (`waypointDelete`).
  void deleteSelected() {
    final i = _selected;
    if (i == null) return;
    _selected = null;
    _commit(_draft.removeWaypoint(i));
  }

  /// Moves the selected waypoint by [delta] (arrow keys, `waypointNudge`).
  void nudgeSelected(Vec2 delta) {
    final i = _selected;
    if (i == null) return;
    _commit(_draft.nudgeWaypoint(i, delta, world));
  }

  void toggleSnap() {
    _snap = !_snap;
    notifyListeners();
  }

  void alignAll() => _commit(_draft.alignAll(rules));

  /// Empties the map (`mapClear`); undoable.
  void clear() {
    _selected = null;
    _commit(MapDraft.empty);
  }

  /// Records that the map was saved as [map].
  void markSaved(MapDefinition map) {
    name = map.name;
    savedId = map.id;
    _savedDraft = _draft;
    notifyListeners();
  }

  // ------------------------------------------------------------ drags

  /// Starts dragging [target] with the finger at [p]. Dragging a "+" handle
  /// inserts its waypoint and drags that.
  void beginDrag(EditorTarget target, Vec2 p) {
    var base = _draft;
    var t = target;
    var origin = p;
    switch (target) {
      case StartTarget():
        origin = base.start!;
      case BaseTarget():
        origin = base.base!;
      case WaypointTarget(:final index):
        origin = base.waypoints[index];
      case MidpointTarget(:final handle):
        base = base.insertWaypoint(handle.place, handle.at, rules);
        t = WaypointTarget(handle.place);
        origin = handle.at;
    }
    _dragBase = base;
    _grab = p - origin;
    _selected = null;
    _drag = EditorDrag(t, origin, valid: true);
    notifyListeners();
  }

  /// Moves the drag so the grabbed point follows the finger at [p].
  void dragTo(Vec2 p) {
    final d = _drag;
    if (d == null) return;
    final at = p - _grab;
    _drag = EditorDrag(d.target, at, valid: _dropValid(d.target, at));
    notifyListeners();
  }

  /// Drops the dragged item where it is, with the original's release rules
  /// (snap, areas, a waypoint dropped off the map is removed).
  void endDrag() {
    final d = _drag;
    final base = _dragBase;
    if (d == null || base == null) return;
    _drag = null;
    _dragBase = null;
    final next = switch (d.target) {
      StartTarget() => base.withStart(d.at, rules, snap: _snap),
      BaseTarget() => base.withBase(d.at, rules, snap: _snap),
      WaypointTarget(:final index) => base.moveWaypoint(index, d.at, rules, snap: _snap),
      MidpointTarget() => base,
    };
    if (next == _draft) {
      notifyListeners();
    } else {
      _commit(next);
    }
  }

  void cancelDrag() {
    if (_drag == null) return;
    _drag = null;
    _dragBase = null;
    notifyListeners();
  }

  bool _dropValid(EditorTarget t, Vec2 at) {
    final p = _snap ? snapToGrid(at, rules.gridSize) : at;
    return switch (t) {
      StartTarget() => rules.startArea.contains(p),
      BaseTarget() => rules.baseArea.contains(p + rules.baseAnchor),
      WaypointTarget() => rules.waypointArea.contains(p),
      MidpointTarget() => true,
    };
  }
}
