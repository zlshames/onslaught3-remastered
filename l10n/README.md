# Translations

Every hand-edited string table lives here, one file per language, `l10n/<language code>.json`.
`en.json` is the English source of the remaster's own text: the interface (`ui.*` keys) and the
remaster's messages (`app.title`, `language.name`, `message.*`, `editor.help.*`, `mods.*`, …).
`tool/gen_data_from_legacy.dart` builds the game's English table,
`assets/data/strings/en.json`, from three sources: the original's messages from the legacy table
(`flow.*`, `editor.*`, `targetMode.*`, `difficulty.*`, `badge.*`), `l10n/en.json`, and the data
documents' own text (turret, combo, map and challenge names, challenge picker labels, tutorial
pages, mod editor titles and descriptors) copied under the `DataTextKeys` keys
(`turret.<id>.name`, `tutorial.page.<n>.title`, `descriptor.<asset>.title`, …;
`packages/onslaught_core/lib/src/data/data_text.dart`). Every other file is a translation that
the generator copies unchanged to `assets/data/strings/<code>.json` and lists in the manifest.
Never edit `assets/data/strings/`; the data snapshot test fails when it differs from what the
generator writes. Widgets read every string through `GameText.tr` (`lib/app/strings.dart`) or
the `DataText` lookups; `test/l10n/ui_strings_test.dart` fails on an unknown key and
`test/architecture_test.dart` on a new hard-coded string. A translation has the same shape as
`en.json`:

```json
{
  "schemaVersion": 1,
  "locale": "fr",
  "strings": {
    "ui.menu.play": "Jouer",
    "message.weaponAvailable": "Nouvelle arme disponible : {name}"
  }
}
```

- Keys are the English keys; any key left out shows in English.
- Keep every `{placeholder}` of the English string (the data validator refuses
  a translation that adds, drops or renames one).
- `language.name` is the language's own name, shown in Settings → Language.
- Run `fvm dart run tool/gen_data_from_legacy.dart`: it writes
  `assets/data/strings/<locale>.json` and lists it in the manifest. The app then
  offers the language and follows the device's language when it matches.
- Check a language with `fvm dart run tool/check_translation.dart <code>` (it must end
  with `0 errors, 0 missing`); `--todo` prints the keys still to translate.

JSON has no comments, so notes for translators on particular keys live here:

- `language.name`: the language's own name (Settings → Language).
- `ui.common.cash`: an amount of cash (`formatCash`): the currency around the grouped digits.
- `ui.mods.defaultName`: a new mod's name as shown (stored as `ModLibrary.defaultName`).
- `badge.*`: one letter per colour turret (the first letter of its colour), on the badge and in
  combo partner lists.
- `message.*`: the original's welcome lines (`GameManager.as:setupGame`, PC key hints dropped)
  and the remaster's custom-game notice; `{name}` in `message.weaponAvailable` is the turret's
  display name.
- `editor.help.*`: the original's help pages (`mapping/MappingHelp.as`) with the mouse and
  keyboard instructions rewritten for touch.
- `ui.share.*`: why a pasted map or mod code cannot be read, shown as `{detail}` of
  `ui.editor.importError` / `ui.mods.importError`. `{other}` and `{kind}` are the kind word as it
  appears in the code (`map`, `mod`); `{issue}` is the path of the field the data validator refused
  (`map:/schemaVersion`): a path, not a sentence, so it is the same in every language.
- `mods.*`: the original mod editor's titles (`ModInterface.as`, `ModAssetDesc.as`,
  `ModImportExport.as`) plus the remaster's validation messages.

Adding or updating a language: follow the `add-language` skill
(`.agents/skills/add-language/SKILL.md`).

## Languages

| Code | Language | Coverage | Translated by | Updated |
|---|---|---|---|---|
| `en` | English | source (`en.json` + legacy table + data documents) | hand-written | — |
| `de` | Deutsch (German) | 897/897 keys | machine (Claude), not yet reviewed by a native speaker; badges keep `B G R Y` (Grün/Gelb collide); the screen-fit keys (`ui.editor.more`, `ui.game.windowTooSmall*`, `ui.settings.ground*`) the reset notice (`ui.menu.recovered`) and tower placement (`ui.settings.placement*`, `ui.game.placeDrop*`, `ui.game.placeAdjust`, `ui.game.placeConfirm`, `ui.game.moveConfirm`) the share-code errors (`ui.share.*`) the 2350-gaby tutorial texts (`flow.tutorialUnlockChallenge`, `flow.lockedChallenge`) the resume dialog (`ui.resume.*`) and Settings → Diagnostics (`ui.settings.diagnostics`, `ui.settings.logLevel*`, `ui.settings.exportLogs*`, `ui.settings.clearLogs*`) machine-translated too | 2026-10-21 |
