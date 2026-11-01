/// `world.json` and `rules.json` from the legacy table.
library;

import '../data/rules_constants.dart';
import '../data/world_def.dart';
import 'legacy_table.dart';

/// The ground decorations of a table section (`world`, `attractDemo`).
List<GroundArt> groundArtFrom(Object? table) => [
  for (final g in listOf(table).cast<Map<String, Object?>>())
    GroundArt(
      art: g['art']! as String,
      x: number(g['x']),
      y: number(g['y']),
      scale: g['scale'] == null ? 1 : number(g['scale']),
      rotation: g['rotation'] == null ? 0 : number(g['rotation']),
    ),
];

/// `world.json`: the play area, road style, placement rules, world art,
/// cosmetic effects and the map editor's geometry.
WorldDef generateWorld(LegacyTable l) {
  final w = l.eng('world');
  final s = l.eng('settings');
  return WorldDef(
    playWidth: number(w['playWidth']),
    playHeight: number(w['playHeight']),
    road: RoadStyle(
      outerWidth: number(w['roadOuterWidth']),
      outerColor: rgb(w['roadOuterColor']),
      innerWidth: number(w['roadInnerWidth']),
      innerColor: rgb(w['roadInnerColor']),
      minePointSpacing: number(w['minePointSpacing']),
    ),
    placement: PlacementRules(
      turretSpacing: number(w['turretSpacing']),
      clearanceRadius: number(w['clearanceRadius']),
      clearanceSamples: integer(w['clearanceSamples']),
      moveCost: number(w['moveCost']),
      baseWidth: number(w['baseWidth']),
      baseHeight: number(w['baseHeight']),
    ),
    art: const {
      'base': 'base.player',
      'ground': 'ground.classic',
      'rocketSmoke': 'fx.rocket-trail',
    },
    groundArt: groundArtFrom(w['groundArt']),
    // `SmokeManager.rocketSmoke`: one trail clip per rocket tick, in a ring
    // of `rocket_smoke_max`; on/off and the ring size are settings.
    effects: WorldEffects(
      rocketSmoke: RocketSmokeRules(
        enabled: s['rocketSmoke']! as bool,
        max: integer(s['rocketSmokeMax']),
        maxPrefMin: integer(s['rocketSmokeMaxMin']),
        maxPrefMax: integer(s['rocketSmokeMaxMax']),
      ),
    ),
    editor: _mapEditor(l),
  );
}

/// The map editor's geometry (`engine.mapEditor`) plus the remaster's
/// validation limits.
MapEditorRules _mapEditor(LegacyTable l) {
  final e = l.eng('mapEditor');
  Area area(Object? v) {
    final a = listOf(v);
    return Area(number(a[0]), number(a[1]), number(a[2]), number(a[3]));
  }

  return MapEditorRules(
    gridSize: number(e['gridSize']),
    startArea: area(e['startArea']),
    baseArea: area(e['baseArea']),
    waypointArea: area(e['waypointArea']),
    baseAnchor: pointFromList(e['baseAnchor']),
    baseEntries: [for (final p in listOf(e['baseEntries'])) pointFromList(p)],
    nudge: number(e['nudge']),
    nudgeFast: number(e['nudgeFast']),
    minRoadLength: mapMinRoadLength.toDouble(),
    maxNameLength: mapMaxNameLength,
  );
}

/// `rules.json`: the global rule constants.
RulesConstants generateRules(LegacyTable l) {
  final r = l.eng('rules');
  final s = l.eng('settings');
  final base = obj(obj(l.turrets['TurretBlue'])['values']);
  final gm = l['gameManager'];
  return RulesConstants(
    tickHz: simulationTickHz,
    speedFactorMin: number(s['timeScaleMinPercent']) / 100,
    speedFactorMax: number(s['timeScaleMaxPercent']) / 100,
    lives: integer(gm['playerLives']),
    sellRefund: number(l['turretManager']['turretResale']),
    modifierMultFloor: number(r['modifierMultFloor']),
    comboRange: number(base['combo_range']),
    blackHolePointRange: number(base['combo_hole_range']),
    slowFloor: number(r['slowFloor']),
    slowRecoverAmount: number(r['slowRecoverAmount']),
    slowRecoverIntervalMs: number(r['slowRecoverIntervalMs']),
    winCheckIntervalMs: number(r['winCheckIntervalMs']),
  );
}
