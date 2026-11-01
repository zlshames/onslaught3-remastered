/// Turns the committed legacy reference table (`docs/legacy/legacy_values.json`)
/// and the `l10n/` string tables into the game's data documents
/// (`assets/data/*.json`). Pure: JSON in, JSON out, deterministic. Each
/// document is built as the typed records the game reads (`gen_*.dart`, one
/// per document or family) and written with their `toJson`
/// ([gameDocuments]), so the generator and the data layer share one schema.
/// The id, asset-id and behaviour-id naming decided here is the remaster's;
/// the numbers all come from the table.
library;

import '../data/game_data.dart';
import '../data/string_table.dart';
import 'game_documents.dart';
import 'gen_challenges.dart';
import 'gen_combos.dart';
import 'gen_maps.dart';
import 'gen_meta.dart';
import 'gen_mod_editor.dart';
import 'gen_ordnance.dart';
import 'gen_strings.dart';
import 'gen_turrets.dart';
import 'gen_waves.dart';
import 'gen_world.dart';
import 'legacy_table.dart';

export 'legacy_table.dart'
    show
        holdingRocketLifetimeMs,
        legacyClipId,
        mapMaxNameLength,
        mapMinRoadLength,
        rocketOffscreen,
        simulationTickHz;

/// Generates every data document, keyed by path relative to `assets/data`.
///
/// [translations] are the `l10n/<locale>.json` documents
/// (`{schemaVersion, locale, strings}`), keyed by locale: `en` is the
/// hand-written English (the remaster's interface text and messages) that
/// joins the generated English in `strings/en.json`; every other locale is
/// written as `strings/<locale>.json`. All are listed in the manifest.
Map<String, Object?> generateGameDocuments(
  Map<String, Object?> legacy, {
  Map<String, Map<String, Object?>> translations = const {},
}) {
  final l = LegacyTable(legacy);
  final turrets = generateTurrets(l);
  final combos = generateCombos(l);
  final maps = generateMaps(l);
  final challenges = generateChallenges(l);
  final tutorial = generateTutorial(l);
  final descriptors = generateDescriptors(l);
  final modEditor = generateModEditor(l);
  final english = generateEnglish(
    l,
    handWritten: translations['en'] == null
        ? const {}
        : translationTable(translations['en']!).strings,
    dataText: generateDataText(
      turrets: turrets,
      combos: combos.recipes,
      maps: maps,
      challenges: challenges,
      tutorial: tutorial,
      modEditor: modEditor,
      descriptors: descriptors,
    ),
  );
  return gameDocuments(
    GameData(
      world: generateWorld(l),
      rules: generateRules(l),
      turrets: {for (final t in turrets) t.id: t},
      combos: {for (final c in combos.recipes) c.id: c},
      comboDefaults: combos.defaults,
      combonly: combos.combonly,
      projectiles: {for (final p in generateProjectiles(l)) p.id: p},
      blasts: {for (final b in generateBlasts(l)) b.id: b},
      creeps: generateCreeps(l),
      difficulty: generateDifficulty(l),
      waves: generateWaves(l),
      maps: {for (final m in maps) m.id: m},
      challenges: challenges,
      progression: generateProgression(l),
      targeting: generateTargeting(l),
      tutorial: tutorial,
      attract: generateAttract(l),
      audio: generateAudio(l),
      strings: <String, StringTable>{
        'en': english,
        for (final e in translations.entries)
          if (e.key != 'en') e.key: translationTable(e.value),
      },
      descriptors: descriptors,
      modEditor: modEditor,
      documents: const {},
    ),
  );
}
