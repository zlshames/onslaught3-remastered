import '../data/map_definition.dart';
import '../data/world_def.dart';
import '../math/vec2.dart';

/// Why a map cannot be saved or played.
enum MapProblem {
  /// The start is not on the map (`mapSave`: outside `StartArea`).
  noStart,

  /// The base is not on the map (`mapSave`: `BasePoint` outside `BaseArea`).
  noBase,

  /// The road is shorter than `MapEditorRules.minRoadLength` (remaster).
  tooShort,

  /// A road point or the base lies outside the play area (a malformed
  /// import; the editor cannot make one).
  outside,
}

/// The problems that stop [map] being saved or played, in the order the
/// original reports them (start, then base), then the remaster's checks.
/// Empty = valid. Built-in, editor, imported and generated maps all pass
/// through this.
List<MapProblem> validateMap(MapDefinition map, WorldDef world) {
  final r = world.editor;
  final inside = [...map.road, map.base].every((p) => world.contains(p.x, p.y));
  return [
    if (!r.startArea.contains(map.spawn)) MapProblem.noStart,
    if (!r.baseArea.contains(map.base + r.baseAnchor)) MapProblem.noBase,
    if (roadLength(map.road) < r.minRoadLength) MapProblem.tooShort,
    if (!inside) MapProblem.outside,
  ];
}

/// Total length of the polyline [road] in px.
double roadLength(List<Vec2> road) {
  var total = 0.0;
  for (var i = 1; i < road.length; i++) {
    total += road[i - 1].distanceTo(road[i]);
  }
  return total;
}

/// [p] moved to the nearest grid corner (`gridAlign`: the four surrounding
/// corners tried top-left, top-right, bottom-left, bottom-right, the first
/// strictly nearest wins, so a tie rounds down).
Vec2 snapToGrid(Vec2 p, double grid) {
  double axis(double v) {
    final low = (v / grid).floor() * grid;
    return v - low > grid / 2 ? low + grid : low;
  }

  return Vec2(axis(p.x), axis(p.y));
}

/// Where the road meets a base whose top-left corner is [base]: the entry
/// point nearest [from] (`waypointClosestBasePoint`: `BP1`..`BP31` in order,
/// the first strictly nearest wins).
Vec2 baseEntryNearest(Vec2 base, Vec2 from, MapEditorRules rules) {
  Vec2? best;
  var bestD = double.infinity;
  for (final e in rules.baseEntries) {
    final p = base + e;
    final d = p.distanceSquaredTo(from);
    if (d < bestD) {
      bestD = d;
      best = p;
    }
  }
  return best!;
}
