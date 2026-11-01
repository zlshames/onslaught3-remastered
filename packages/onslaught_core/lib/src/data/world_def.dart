import 'package:meta/meta.dart';

import '../math/vec2.dart';
import 'json_reader.dart';

/// A decoration drawn on the ground, under the road: [art] with its
/// registration point at ([x], [y]), scaled and turned clockwise by [rotation]
/// degrees.
@immutable
class GroundArt {
  const GroundArt({
    required this.art,
    required this.x,
    required this.y,
    this.scale = 1,
    this.rotation = 0,
  });

  factory GroundArt.fromJson(JsonReader r) {
    r.expectOnlyKeys({'art', 'x', 'y', 'scale', 'rotation'});
    return GroundArt(
      art: r.string('art'),
      x: r.number('x'),
      y: r.number('y'),
      scale: r.optNumber('scale', min: 0) ?? 1,
      rotation: r.optNumber('rotation') ?? 0,
    );
  }

  final String art;
  final double x;
  final double y;
  final double scale;
  final double rotation;

  Map<String, Object?> toJson() => {
    'art': art,
    'x': jsonNumber(x),
    'y': jsonNumber(y),
    if (scale != 1) 'scale': jsonNumber(scale),
    if (rotation != 0) 'rotation': jsonNumber(rotation),
  };
}

/// `world.json`: the play area and the geometry rules of the road and placement.
@immutable
class WorldDef {
  const WorldDef({
    required this.playWidth,
    required this.playHeight,
    required this.road,
    required this.placement,
    required this.art,
    required this.groundArt,
    required this.effects,
    required this.editor,
  });

  factory WorldDef.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'schemaVersion',
      'playArea',
      'road',
      'placement',
      'art',
      'groundArt',
      'effects',
      'editor',
    });
    final area = r.child('playArea');
    area.expectOnlyKeys({'width', 'height'});
    return WorldDef(
      playWidth: area.number('width', min: 1),
      playHeight: area.number('height', min: 1),
      road: RoadStyle.fromJson(r.child('road')),
      placement: PlacementRules.fromJson(r.child('placement')),
      art: r.mapOf('art', (c) => c.asString()),
      groundArt: r.list('groundArt', GroundArt.fromJson),
      effects: WorldEffects.fromJson(r.child('effects')),
      editor: MapEditorRules.fromJson(r.child('editor')),
    );
  }

  static const int schemaVersion = 1;

  /// Width of the play area in world px (720 in the original).
  final double playWidth;

  /// Height of the play area in world px (480 in the original).
  final double playHeight;
  final RoadStyle road;
  final PlacementRules placement;

  /// World art by role (`base`, `ground`, `rocketSmoke`) → logical asset id.
  final Map<String, String> art;

  /// The decorations on a game's ground.
  final List<GroundArt> groundArt;

  /// Cosmetic effects and their player-setting bounds.
  final WorldEffects effects;

  /// The map editor's geometry and validation limits.
  final MapEditorRules editor;

  bool contains(double x, double y) => x >= 0 && y >= 0 && x <= playWidth && y <= playHeight;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'playArea': {'width': jsonNumber(playWidth), 'height': jsonNumber(playHeight)},
    'road': road.toJson(),
    'placement': placement.toJson(),
    'art': art,
    'groundArt': [for (final g in groundArt) g.toJson()],
    'effects': effects.toJson(),
    'editor': editor.toJson(),
  };
}

/// Cosmetic world effects (no effect on the simulation).
@immutable
class WorldEffects {
  const WorldEffects({required this.rocketSmoke});

  factory WorldEffects.fromJson(JsonReader r) {
    r.expectOnlyKeys({'rocketSmoke'});
    return WorldEffects(rocketSmoke: RocketSmokeRules.fromJson(r.child('rocketSmoke')));
  }

  final RocketSmokeRules rocketSmoke;

  Map<String, Object?> toJson() => {'rocketSmoke': rocketSmoke.toJson()};
}

/// Rocket smoke trails (`SmokeManager.rocketSmoke`): every rocket drops one
/// trail clip (`world.art.rocketSmoke`) per engine tick; the newest [max]
/// clips are kept (a ring). The player can switch them off (`PrefSmoke`) and
/// set the ring size between [maxPrefMin] and [maxPrefMax] (`PrefSmokeMax`).
@immutable
class RocketSmokeRules {
  const RocketSmokeRules({
    required this.enabled,
    required this.max,
    required this.maxPrefMin,
    required this.maxPrefMax,
  });

  factory RocketSmokeRules.fromJson(JsonReader r) {
    r.expectOnlyKeys({'enabled', 'max', 'maxPrefMin', 'maxPrefMax'});
    final min = r.integer('maxPrefMin', min: 0);
    return RocketSmokeRules(
      enabled: r.boolean('enabled'),
      max: r.integer('max', min: min),
      maxPrefMin: min,
      maxPrefMax: r.integer('maxPrefMax', min: min),
    );
  }

  /// Default for the smoke setting.
  final bool enabled;

  /// Default ring size.
  final int max;
  final int maxPrefMin;
  final int maxPrefMax;

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'max': max,
    'maxPrefMin': maxPrefMin,
    'maxPrefMax': maxPrefMax,
  };
}

/// How the road is drawn and sampled (`RoadManager`).
@immutable
class RoadStyle {
  const RoadStyle({
    required this.outerWidth,
    required this.outerColor,
    required this.innerWidth,
    required this.innerColor,
    required this.minePointSpacing,
  });

  factory RoadStyle.fromJson(JsonReader r) {
    r.expectOnlyKeys({'outerWidth', 'outerColor', 'innerWidth', 'innerColor', 'minePointSpacing'});
    return RoadStyle(
      outerWidth: r.number('outerWidth', min: 1),
      outerColor: r.rgb('outerColor'),
      innerWidth: r.number('innerWidth', min: 1),
      innerColor: r.rgb('innerColor'),
      minePointSpacing: r.number('minePointSpacing', min: 1),
    );
  }

  final double outerWidth;

  /// 0xRRGGBB.
  final int outerColor;
  final double innerWidth;

  /// 0xRRGGBB.
  final int innerColor;

  /// Distance in px between consecutive mine points along the road.
  final double minePointSpacing;

  Map<String, Object?> toJson() => {
    'outerWidth': jsonNumber(outerWidth),
    'outerColor': rgbToJson(outerColor),
    'innerWidth': jsonNumber(innerWidth),
    'innerColor': rgbToJson(innerColor),
    'minePointSpacing': jsonNumber(minePointSpacing),
  };
}

/// Turret placement rules (`BuildShape.buildCheck`).
@immutable
class PlacementRules {
  const PlacementRules({
    required this.turretSpacing,
    required this.clearanceRadius,
    required this.clearanceSamples,
    required this.moveCost,
    required this.baseWidth,
    required this.baseHeight,
  });

  factory PlacementRules.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'turretSpacing',
      'clearanceRadius',
      'clearanceSamples',
      'moveCost',
      'baseWidth',
      'baseHeight',
    });
    return PlacementRules(
      turretSpacing: r.number('turretSpacing', min: 0),
      clearanceRadius: r.number('clearanceRadius', min: 0),
      clearanceSamples: r.integer('clearanceSamples', min: 1),
      moveCost: r.number('moveCost', min: 0),
      baseWidth: r.number('baseWidth', min: 0),
      baseHeight: r.number('baseHeight', min: 0),
    );
  }

  /// Minimum centre-to-centre distance between turrets.
  final double turretSpacing;

  /// Radius of the circle sampled for road/base collisions.
  final double clearanceRadius;

  /// Number of points sampled on that circle.
  final int clearanceSamples;

  /// Cash cost of moving a turret.
  final double moveCost;

  /// Size of the player base, which blocks building like the road. The
  /// map's base position is the base's top-left corner.
  final double baseWidth;
  final double baseHeight;

  Map<String, Object?> toJson() => {
    'turretSpacing': jsonNumber(turretSpacing),
    'clearanceRadius': jsonNumber(clearanceRadius),
    'clearanceSamples': clearanceSamples,
    'moveCost': jsonNumber(moveCost),
    'baseWidth': jsonNumber(baseWidth),
    'baseHeight': jsonNumber(baseHeight),
  };
}

/// An axis-aligned rectangle in world px.
@immutable
class Area {
  const Area(this.x, this.y, this.width, this.height);

  factory Area.fromJson(JsonReader r) {
    r.expectOnlyKeys({'x', 'y', 'width', 'height'});
    return Area(
      r.number('x'),
      r.number('y'),
      r.number('width', min: 0),
      r.number('height', min: 0),
    );
  }

  final double x;
  final double y;
  final double width;
  final double height;

  double get right => x + width;
  double get bottom => y + height;

  /// Edges included, like Flash's bounding-box `hitTest`.
  bool contains(Vec2 p) => p.x >= x && p.y >= y && p.x <= right && p.y <= bottom;

  /// [p] moved to the nearest point inside.
  Vec2 clamp(Vec2 p) => Vec2(p.x.clamp(x, right), p.y.clamp(y, bottom));

  Map<String, Object?> toJson() => {
    'x': jsonNumber(x),
    'y': jsonNumber(y),
    'width': jsonNumber(width),
    'height': jsonNumber(height),
  };

  @override
  bool operator ==(Object other) =>
      other is Area &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);
}

/// The map editor (`GameManagerMapping`): where the start, the base and the
/// waypoints may go, the snap grid, the base's road entry points, and the
/// remaster's validation limits.
@immutable
class MapEditorRules {
  const MapEditorRules({
    required this.gridSize,
    required this.startArea,
    required this.baseArea,
    required this.waypointArea,
    required this.baseAnchor,
    required this.baseEntries,
    required this.nudge,
    required this.nudgeFast,
    required this.minRoadLength,
    required this.maxNameLength,
  });

  factory MapEditorRules.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'gridSize',
      'startArea',
      'baseArea',
      'waypointArea',
      'baseAnchor',
      'baseEntries',
      'nudge',
      'nudgeFast',
      'minRoadLength',
      'maxNameLength',
    });

    return MapEditorRules(
      gridSize: r.number('gridSize', min: 1),
      startArea: Area.fromJson(r.child('startArea')),
      baseArea: Area.fromJson(r.child('baseArea')),
      waypointArea: Area.fromJson(r.child('waypointArea')),
      baseAnchor: r.point('baseAnchor'),
      baseEntries: r.list('baseEntries', (c) => c.asPoint(), minLength: 1),
      nudge: r.number('nudge', min: 0),
      nudgeFast: r.number('nudgeFast', min: 0),
      minRoadLength: r.number('minRoadLength', min: 0),
      maxNameLength: r.integer('maxNameLength', min: 1),
    );
  }

  /// Snap grid spacing in px (`grid_size`).
  final double gridSize;

  /// Where the start may be (`StartArea`); new waypoints must also be in it.
  final Area startArea;

  /// Where the base's [baseAnchor] may be (`BaseArea`).
  final Area baseArea;

  /// A waypoint released outside it is removed (`PlayArea`).
  final Area waypointArea;

  /// The base's centre point (`BasePoint`), from its top-left corner.
  final Vec2 baseAnchor;

  /// Where the road may meet the base (`BP1`..`BP31`), from its top-left
  /// corner; the road ends at the one nearest the last waypoint.
  final List<Vec2> baseEntries;

  /// Arrow-key nudge in px, and with Shift.
  final double nudge;
  final double nudgeFast;

  /// The shortest road a map may be saved with, in px (remaster).
  final double minRoadLength;

  /// The longest map name (remaster).
  final int maxNameLength;

  Map<String, Object?> toJson() => {
    'gridSize': jsonNumber(gridSize),
    'startArea': startArea.toJson(),
    'baseArea': baseArea.toJson(),
    'waypointArea': waypointArea.toJson(),
    'baseAnchor': pointToJson(baseAnchor),
    'baseEntries': [for (final p in baseEntries) pointToJson(p)],
    'nudge': jsonNumber(nudge),
    'nudgeFast': jsonNumber(nudgeFast),
    'minRoadLength': jsonNumber(minRoadLength),
    'maxNameLength': maxNameLength,
  };
}
