/// Writes typed game data back out as the `assets/data` documents: the
/// inverse of `GameData.fromDocuments`, built from each record's `toJson`.
/// The generator serialises the records it builds from the legacy table with
/// it, and the round-trip test checks that the committed documents read and
/// written back come out unchanged.
library;

import '../data/game_data.dart';

/// Every document of [data], keyed by path relative to `assets/data`, the
/// manifest first and listing the rest in order: the fixed documents, the
/// string tables (English, then the other locales sorted) and the maps in
/// picker order.
Map<String, Object?> gameDocuments(GameData data) {
  final docs = <String, Object?>{
    'world.json': data.world.toJson(),
    'rules.json': data.rules.toJson(),
    'turrets.json': {
      'schemaVersion': 1,
      'turrets': [for (final t in data.turrets.values) t.toJson()],
    },
    'combos.json': {
      'schemaVersion': 1,
      'defaults': data.comboDefaults.toJson(),
      'combos': [for (final c in data.combos.values) c.toJson()],
      'combonly': [for (final o in data.combonly) o.toJson()],
    },
    'projectiles.json': {
      'schemaVersion': 1,
      'projectiles': [for (final p in data.projectiles.values) p.toJson()],
    },
    'blasts.json': {
      'schemaVersion': 1,
      'blasts': [for (final b in data.blasts.values) b.toJson()],
    },
    'creeps.json': data.creeps.toJson(),
    'difficulty.json': data.difficulty.toJson(),
    'waves.json': data.waves.toJson(),
    'challenges.json': data.challenges.toJson(),
    'progression.json': data.progression.toJson(),
    'targeting.json': data.targeting.toJson(),
    'tutorial.json': data.tutorial.toJson(),
    if (data.attract case final attract?) 'attract.json': attract.toJson(),
    'audio.json': data.audio.toJson(),
    'descriptors.json': data.descriptors.toJson(),
    if (data.modEditor.items.isNotEmpty) 'mod_editor.json': data.modEditor.toJson(),
    if (data.strings['en'] case final en?) 'strings/en.json': en.toJson(),
    for (final locale in data.strings.keys.where((l) => l != 'en').toList()..sort())
      'strings/$locale.json': data.strings[locale]!.toJson(),
    for (final m in data.maps.values) 'maps/${m.id}.json': m.toJson(),
  };
  return {
    'manifest.json': {'schemaVersion': 1, 'files': docs.keys.toList()},
    ...docs,
  };
}
