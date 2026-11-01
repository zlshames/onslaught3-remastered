import 'dart:math' as math;

import '../data/world_def.dart';
import '../math/det_math.dart';
import '../math/vec2.dart';
import '../sim/road.dart';

/// Why a turret cannot stand at a spot (`BuildShape.buildCheck`). The
/// names are the `CommandRejected` reasons.
enum PlacementIssue {
  /// Outside the play area (`PlayArea.hitTest`).
  outsidePlayArea,

  /// The game's turret limit is reached (challenges).
  turretLimit,

  /// Closer than `turretSpacing` to another turret's centre.
  tooCloseToTurret,

  /// A clearance sample point touches the road or the base.
  blocked,
}

/// Checks a turret centred at [at] against the placement rules
/// (`BuildShape.buildCheck`, `buildCheckOtherTurrets`; `MoveShape` passes the
/// moving turret's own position out of [others]):
///
/// - [at] lies in the play area;
/// - fewer than [turretLimit] turrets exist (when there is a limit);
/// - every other turret centre is at least `turretSpacing` away;
/// - none of the `clearanceSamples` points on the `clearanceRadius` circle
///   around [at] touches the road stroke (within `outerWidth / 2` of the
///   centre line, round caps and joins included) or the base rectangle.
///   The centre itself is not sampled, as in the original.
///
/// Returns null when the spot is valid. Cash and pause are the caller's.
PlacementIssue? placementIssue({
  required WorldDef world,
  required Road road,
  required Vec2 base,
  required Vec2 at,
  required Iterable<Vec2> others,
  int? turretLimit,
}) {
  if (!world.contains(at.x, at.y)) return PlacementIssue.outsidePlayArea;
  final list = others.toList();
  if (turretLimit != null && list.length >= turretLimit) return PlacementIssue.turretLimit;
  final rules = world.placement;
  for (final o in list) {
    if (o.distanceTo(at) < rules.turretSpacing) return PlacementIssue.tooCloseToTurret;
  }
  final halfRoad = world.road.outerWidth / 2;
  for (final p in clearanceSamples(at, rules.clearanceRadius, rules.clearanceSamples)) {
    if (road.distanceToCentreLine(p) <= halfRoad) return PlacementIssue.blocked;
    if (p.x >= base.x &&
        p.x <= base.x + rules.baseWidth &&
        p.y >= base.y &&
        p.y <= base.y + rules.baseHeight) {
      return PlacementIssue.blocked;
    }
  }
  return null;
}

/// [count] points evenly spaced on the circle of [radius] around [at],
/// starting at +x. For the original's 8 these are the four axis points and
/// the four diagonals (`BuildShape` ctor `build_areas`).
List<Vec2> clearanceSamples(Vec2 at, double radius, int count) => [
  for (var i = 0; i < count; i++)
    Vec2(
      at.x + radius * detCos(i * 2 * math.pi / count),
      at.y + radius * detSin(i * 2 * math.pi / count),
    ),
];
