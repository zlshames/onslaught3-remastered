/// The parts of `docs/legacy/legacy_values.json` that come from the
/// hand-transcribed `engine_constants.dart` rather than from parsing
/// `.legacy/`: the `engine` section, the combo recipe structure
/// (`combos.recipes`, `unreachable`, `combonly`) and the sandbox racks
/// (`gameManager.modeRacks`). They need no legacy source, so
/// `tool/legacy_extract.dart --transcribed` can refresh them anywhere, and
/// `test/tool/legacy_transcription_test.dart` checks in CI that the
/// committed table still equals them.
library;

import 'engine_constants.dart' as engine;

/// `engine`: the engine classes' literals.
Map<String, Object?> engineSection() => {
  'note': 'Transcribed from engine classes; see docs/legacy/ENGINE_NOTES.md.',
  'world': engine.world,
  'rules': engine.rules,
  'projectileDefaults': engine.projectileDefaults,
  'projectileEngines': engine.projectileEngines,
  'projectileLinkages': engine.projectileLinkages,
  'blasts': engine.blasts,
  'turretSpecials': engine.turretSpecials,
  'targeting': engine.targeting,
  'creeps': engine.creeps,
  'weapons': {
    'source':
        'Turret sprites (Weapon placement matrix) and weapon sprites (Cannon 827, Laser 861, '
        'MissileLauncher 909 FirePoint0..3, SparkGun 922, 917, 851, Railgun 881, '
        'TargetBeacon 944) via FFDec swf2xml',
    'restRotation': engine.weaponRotations,
    'firePoints': engine.firePoints,
  },
  'settings': engine.settings,
  'soundMix': engine.soundMix,
  'soundEvents': engine.soundEvents,
  'artSymbols': engine.artSymbols,
  'attractDemo': engine.attractDemo,
  'messages': engine.messages,
  'mapEditor': engine.mapEditor,
};

/// The transcribed fields of `combos` (its `data` is parsed from
/// `Combos.as`).
Map<String, Object?> comboStructure() => {
  'recipes': engine.comboRecipes,
  'unreachable': engine.unreachableCombos,
  'combonly': {
    'source': 'turrets/TurretCombonly.as:comboScan, comboFire',
    'scan': engine.combonlyScan,
  },
};

/// `gameManager.modeRacks`.
Map<String, Object?> modeRacksSection() => {
  'source': 'GameManager.as:resetGame (game_type "sandbox"; sandbox2 when unlocked)',
  'racks': engine.modeRacks,
};

/// [table] with every transcribed section replaced by the current
/// transcription, in place (key order kept).
Map<String, Object?> withTranscribedSections(Map<String, Object?> table) {
  (table['gameManager']! as Map)['modeRacks'] = modeRacksSection();
  final combos = table['combos']! as Map;
  comboStructure().forEach((k, v) => combos[k] = v);
  table['engine'] = engineSection();
  return table;
}
