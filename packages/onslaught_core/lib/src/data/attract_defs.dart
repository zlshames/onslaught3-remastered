import 'package:meta/meta.dart';

import '../math/vec2.dart';
import 'json_reader.dart';
import 'map_definition.dart';
import 'world_def.dart';

/// One turret of the attract demo, placed at ([x], [y]).
@immutable
class AttractTurret {
  const AttractTurret(this.turret, this.x, this.y);

  factory AttractTurret.fromJson(JsonReader r) {
    r.expectOnlyKeys({'turret', 'x', 'y'});
    return AttractTurret(r.string('turret'), r.number('x'), r.number('y'));
  }

  /// `turrets.json` id.
  final String turret;
  final double x;
  final double y;

  Map<String, Object?> toJson() => {'turret': turret, 'x': jsonNumber(x), 'y': jsonNumber(y)};
}

/// `attract.json`: the demo game behind the main menu (`GameManagerIntro`):
/// its own road over the whole stage, preset level-1 turrets and a wave
/// scheme of its own. Lives are never lost and kills never count.
@immutable
class AttractDef {
  const AttractDef({
    required this.difficulty,
    required this.waveSize,
    required this.waveSpacingMs,
    required this.baseHp,
    required this.creepTypes,
    required this.sizeChange,
    required this.stageWidth,
    required this.stageHeight,
    required this.road,
    required this.turrets,
    required this.groundArt,
  });

  factory AttractDef.fromJson(JsonReader r) {
    r.expectOnlyKeys({
      'schemaVersion',
      'difficulty',
      'waveSize',
      'waveSpacingMs',
      'baseHp',
      'creepTypes',
      'sizeChange',
      'stage',
      'road',
      'turrets',
      'groundArt',
    });
    final stage = r.child('stage')..expectOnlyKeys({'width', 'height'});
    return AttractDef(
      difficulty: r.string('difficulty'),
      waveSize: r.integer('waveSize', min: 1),
      waveSpacingMs: r.number('waveSpacingMs', min: 1),
      baseHp: r.number('baseHp', min: 0),
      creepTypes: r.integer('creepTypes', min: 1),
      sizeChange: r.optBoolean('sizeChange', fallback: true),
      stageWidth: stage.number('width', min: 1),
      stageHeight: stage.number('height', min: 1),
      road: r.list('road', (c) => c.asPoint(), minLength: 2),
      turrets: r.list('turrets', AttractTurret.fromJson),
      groundArt: r.list('groundArt', GroundArt.fromJson),
    );
  }

  static const int schemaVersion = 1;

  /// The map id the demo session reports.
  static const String mapId = 'attract';

  final String difficulty;

  /// Creeps per wave (their HP is scaled up to match a standard wave).
  final int waveSize;
  final double waveSpacingMs;

  /// HP of a standard-size creep before the first wave's growth.
  final double baseHp;

  /// Only the first this many creep types are sent.
  final int creepTypes;

  /// Whether smaller waves draw bigger creeps.
  final bool sizeChange;

  /// The demo uses the whole original stage (720 × 535), not just the play area.
  final double stageWidth;
  final double stageHeight;
  final List<Vec2> road;
  final List<AttractTurret> turrets;

  /// The decorations on the menu's ground, which differ from a game's.
  final List<GroundArt> groundArt;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'difficulty': difficulty,
    'waveSize': waveSize,
    'waveSpacingMs': jsonNumber(waveSpacingMs),
    'baseHp': jsonNumber(baseHp),
    'creepTypes': creepTypes,
    'sizeChange': sizeChange,
    'stage': {'width': jsonNumber(stageWidth), 'height': jsonNumber(stageHeight)},
    'road': [for (final p in road) pointToJson(p)],
    'turrets': [for (final t in turrets) t.toJson()],
    'groundArt': [for (final g in groundArt) g.toJson()],
  };

  /// The road as a map; the base sits at the road's end (the demo draws none).
  MapDefinition get map =>
      MapDefinition(id: mapId, name: 'Attract', base: road.last, road: road, order: 1 << 16);
}
