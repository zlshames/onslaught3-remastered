/// The string tables (`strings/<locale>.json`): English generated from the
/// legacy table, the hand-written English of `l10n/en.json` and the data
/// documents' own text; every other language copied from `l10n/<code>.json`.
library;

import '../data/challenge_defs.dart';
import '../data/combo_recipe.dart';
import '../data/data_text.dart';
import '../data/descriptor_defs.dart';
import '../data/map_definition.dart';
import '../data/mod_editor_defs.dart';
import '../data/string_table.dart';
import '../data/turret_def.dart';
import '../data/tutorial_defs.dart';
import 'legacy_table.dart';

/// `strings/en.json`: first the English the legacy table and the data give
/// (target modes, difficulty names, colour badges, the original's
/// messages), then [handWritten] (`l10n/en.json`: the remaster's interface
/// text and its own messages, overriding a generated key of the same name),
/// then [dataText].
StringTable generateEnglish(
  LegacyTable l, {
  required Map<String, String> handWritten,
  required Map<String, String> dataText,
}) {
  final tg = l.eng('targeting');
  final modes = strings(tg['modes']);
  final names = strings(tg['modeNames']);
  return StringTable(
    locale: 'en',
    strings: {
      for (var i = 0; i < modes.length; i++) 'targetMode.${modes[i]}': names[i],
      for (final d in difficultyNames.entries) 'difficulty.${d.key}': d.value,
      // The remaster's colour badges: one letter per colour turret (the
      // first letter of its colour), on the badge and in combo partner
      // lists; translations pick their own.
      for (final id in basicColourIds) 'badge.$id': id[0].toUpperCase(),
      // Mode, challenge and tutorial messages and labels, verbatim
      // (`engine.messages`; `{difficulty}` is the difficulty's name,
      // `difficulty.<id>`, where the original printed the id `game_diff`:
      // DEVIATIONS `difficultyNames`).
      for (final e in l.eng('messages').entries)
        if (e.key != 'source') 'flow.${e.key}': e.value! as String,
      // Map editor messages, verbatim (`engine.mapEditor.messages`).
      for (final e in obj(l.eng('mapEditor')['messages']).entries)
        'editor.${e.key}': e.value! as String,
      ...handWritten,
      ...dataText,
    },
  );
}

/// A translation document (`l10n/<code>.json`: `{schemaVersion, locale,
/// strings}`) as a string table.
StringTable translationTable(Map<String, Object?> doc) => StringTable(
  locale: doc['locale']! as String,
  strings: obj(doc['strings']).cast<String, String>(),
);

/// The player-facing text of the generated records under its
/// [DataTextKeys] (turret, combo, map and challenge names, challenge
/// picker labels, tutorial pages, mod editor titles and descriptors), so
/// translations can override it. English is copied from the documents,
/// which keep their text: the game shows the same words either way.
Map<String, String> generateDataText({
  required List<TurretDef> turrets,
  required List<ComboRecipe> combos,
  required List<MapDefinition> maps,
  required ChallengeDefs challenges,
  required TutorialDefs tutorial,
  required ModEditorDefs modEditor,
  required DescriptorDefs descriptors,
}) {
  final pickers = <String, String>{};
  for (final group in [challenges.pickers, challenges.classicPickers]) {
    for (final e in group.entries) {
      for (final o in e.value) {
        final key = DataTextKeys.picker(e.key, o.label);
        final seen = pickers.putIfAbsent(key, () => o.label);
        if (seen != o.label) throw StateError('$key labels both "$seen" and "${o.label}"');
      }
    }
  }
  Map<String, String> descriptor(String asset, ValueDescriptor d, {String? part}) => {
    'title': d.title,
    // Only the value's own description is shown, not its entries' parts'.
    if (part == null) 'description': d.description,
    'unit': ?d.unit,
  }.map((k, v) => MapEntry(DataTextKeys.descriptor(asset, k, part: part), v));
  final text = <String, String>{
    for (final t in turrets) DataTextKeys.turret(t.id): t.name,
    for (final c in combos) DataTextKeys.combo(c.id): c.name,
    for (final m in maps) DataTextKeys.map(m.id): m.name,
    for (final p in challenges.presets) DataTextKeys.challenge(p.id): p.name,
    ...pickers,
    for (final (i, p) in tutorial.pages.indexed) ...{
      DataTextKeys.tutorialTitle(i): p.title,
      DataTextKeys.tutorialBody(i): p.body,
    },
    for (final item in modEditor.items) DataTextKeys.modItem(item.id): item.title,
    for (final e in descriptors.byAsset.entries) ...{
      ...descriptor(e.key, e.value),
      if (e.value.key case final key?) ...descriptor(e.key, key, part: 'key'),
      if (e.value.value case final value?) ...descriptor(e.key, value, part: 'value'),
    },
  };
  // Nothing to translate in an empty text (the tutorial's silent pages).
  return text..removeWhere((_, v) => v.isEmpty);
}
