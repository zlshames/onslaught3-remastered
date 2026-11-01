import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../data/map_definition.dart';
import '../data/world_def.dart';
import '../math/vec2.dart';
import 'map_rules.dart';

/// A "+" handle halfway along a road segment: tapping it inserts a waypoint
/// at [at] with index [place] (`waypointInsertBetween`).
@immutable
class MidpointHandle {
  const MidpointHandle(this.place, this.at);

  /// Index the new waypoint takes in [MapDraft.waypoints].
  final int place;
  final Vec2 at;

  @override
  bool operator ==(Object other) =>
      other is MidpointHandle && other.place == place && other.at == at;

  @override
  int get hashCode => Object.hash(place, at);

  @override
  String toString() => 'MidpointHandle($place, $at)';
}

/// A map being edited (`GameManagerMapping`): an optional start, an optional
/// base (its top-left corner) and the waypoints between them. The road's
/// last point is not stored: it is the base entry point nearest the last
/// waypoint, recomputed whenever the map changes, as in the original.
///
/// Every edit returns a new draft, so undo/redo is a list of drafts.
/// `snap` is the editor's grid toggle; with it on, placed points move to the
/// nearest grid corner.
@immutable
class MapDraft {
  const MapDraft({this.start, this.base, this.waypoints = const []});

  /// The draft of an existing map (`mapLoad`): the road's first point is the
  /// start, its last point (the base entry) is dropped and recomputed.
  factory MapDraft.fromMap(MapDefinition map) => MapDraft(
    start: map.road.first,
    base: map.base,
    waypoints: List.unmodifiable(map.road.sublist(1, map.road.length - 1)),
  );

  static const MapDraft empty = MapDraft();

  final Vec2? start;

  /// The base's top-left corner.
  final Vec2? base;
  final List<Vec2> waypoints;

  bool get isEmpty => start == null && base == null && waypoints.isEmpty;

  MapDraft _withWaypoints(List<Vec2> points) =>
      MapDraft(start: start, base: base, waypoints: List.unmodifiable(points));

  static Vec2 _snapped(Vec2 p, MapEditorRules rules, bool snap) =>
      snap ? snapToGrid(p, rules.gridSize) : p;

  /// The start dropped at [p]; dropped outside the start area it leaves the
  /// map (`waypointPathUpdate` puts it back on the palette).
  MapDraft withStart(Vec2 p, MapEditorRules rules, {bool snap = false}) {
    final at = _snapped(p, rules, snap);
    return MapDraft(
      start: rules.startArea.contains(at) ? at : null,
      base: base,
      waypoints: waypoints,
    );
  }

  /// The base dropped with its top-left corner at [topLeft]; if its centre
  /// is outside the base area it leaves the map.
  MapDraft withBase(Vec2 topLeft, MapEditorRules rules, {bool snap = false}) {
    final at = _snapped(topLeft, rules, snap);
    return MapDraft(
      start: start,
      base: rules.baseArea.contains(at + rules.baseAnchor) ? at : null,
      waypoints: waypoints,
    );
  }

  /// A waypoint added at the end of the road (`waypointNew`), or this draft
  /// unchanged when [p] is outside the start area or a waypoint is already
  /// there.
  MapDraft addWaypoint(Vec2 p, MapEditorRules rules, {bool snap = false}) {
    final at = _snapped(p, rules, snap);
    if (!rules.startArea.contains(at) || waypoints.contains(at)) return this;
    return _withWaypoints([...waypoints, at]);
  }

  /// A waypoint inserted at index [place] (a midpoint handle,
  /// `waypointInsert`).
  MapDraft insertWaypoint(int place, Vec2 p, MapEditorRules rules, {bool snap = false}) {
    RangeError.checkValueInInterval(place, 0, waypoints.length, 'place');
    return _withWaypoints([...waypoints]..insert(place, _snapped(p, rules, snap)));
  }

  /// Waypoint [index] dropped at [p]; dropped outside the waypoint area it
  /// is removed (`waypointMake` `onMouseUp`).
  MapDraft moveWaypoint(int index, Vec2 p, MapEditorRules rules, {bool snap = false}) {
    final at = _snapped(p, rules, snap);
    if (!rules.waypointArea.contains(at)) return removeWaypoint(index);
    return _withWaypoints([...waypoints]..[index] = at);
  }

  MapDraft removeWaypoint(int index) => _withWaypoints([...waypoints]..removeAt(index));

  /// Waypoint [index] moved by [delta], kept inside the play area
  /// (`waypointNudge`).
  MapDraft nudgeWaypoint(int index, Vec2 delta, WorldDef world) {
    final p = waypoints[index] + delta;
    final at = Vec2(
      p.x.clamp(0, world.playWidth).toDouble(),
      p.y.clamp(0, world.playHeight).toDouble(),
    );
    return _withWaypoints([...waypoints]..[index] = at);
  }

  /// Everything moved to the nearest grid corner ("align all",
  /// `gridAlignAll`); a start or base that ends up outside its area leaves
  /// the map.
  MapDraft alignAll(MapEditorRules rules) {
    var d = _withWaypoints([for (final w in waypoints) snapToGrid(w, rules.gridSize)]);
    if (start != null) d = d.withStart(start!, rules, snap: true);
    if (base != null) d = d.withBase(base!, rules, snap: true);
    return d;
  }

  /// The road as drawn (`waypointPathUpdate`): the start if placed, the
  /// waypoints, and the base entry nearest the last of those if the base is
  /// placed.
  List<Vec2> roadPoints(MapEditorRules rules) {
    final points = [?start, ...waypoints];
    if (base != null && points.isNotEmpty) {
      points.add(baseEntryNearest(base!, points.last, rules));
    }
    return points;
  }

  /// A "+" handle on every drawn road segment.
  List<MidpointHandle> midpoints(MapEditorRules rules) {
    final points = roadPoints(rules);
    final offset = start == null ? 0 : 1;
    return [
      for (var k = 0; k + 1 < points.length; k++)
        MidpointHandle(k + 1 - offset, (points[k] + points[k + 1]) * (1 / 2)),
    ];
  }

  /// The finished map (`mapSave`), or null while the start or the base is
  /// missing. Check it with [validateMap] before saving.
  MapDefinition? toMap(MapEditorRules rules, {required String id, required String name}) {
    if (start == null || base == null) return null;
    return MapDefinition(
      id: id,
      name: name,
      base: base!,
      road: List.unmodifiable(roadPoints(rules)),
      builtIn: false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapDraft &&
      other.start == start &&
      other.base == base &&
      const ListEquality<Vec2>().equals(other.waypoints, waypoints);

  @override
  int get hashCode => Object.hash(start, base, Object.hashAll(waypoints));
}
