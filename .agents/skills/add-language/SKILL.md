---
name: add-language
description: The end-to-end procedure for adding a new interface language (translation) to Onslaught 3 Remastered, or bringing an existing one up to date after English text changed, so the game offers it in Settings → Language and follows the device's language. Covers the go/no-go checks, the l10n/<code>.json file, translation rules, the coverage checker, regenerating the data, iOS/macOS metadata, tests and on-device QA. Use whenever a language is added, a translation is edited, or l10n/en.json gained keys that translations lack.
---

# Add a language

A language is **data, not code**: one file, `l10n/<code>.json`, that the generator copies to
`assets/data/strings/<code>.json` and lists in the manifest. Nothing in `lib/` changes. If a
step below seems to need a Dart change, the language fails the gate in step 0: stop and
propose the code change to the project owner instead.

## Facts about this project (verified 2026-10-19, Flutter 3.47.6 via fvm)

| Item | Value |
|---|---|
| Source of English | `l10n/en.json` (`ui.*` and the remaster's messages: `app.title`, `language.name`, `message.*`, `editor.help.*`, `mods.*`, …) + the legacy table (`flow.*`, `editor.*`, `targetMode.*`, …) + the data documents' own text (`turret.*`, `combo.*`, `map.*`, `challenge.*`, `tutorial.*`, `mods.item.*`, `descriptor.*`: `DataTextKeys`) → generated `assets/data/strings/en.json` (~843 keys) |
| Translation input | `l10n/<code>.json` — `{schemaVersion: 1, locale, strings}`, nothing else (see `l10n/README.md`) |
| Generated output | `assets/data/strings/<code>.json` + a `strings/<code>.json` line in `assets/data/manifest.json` — never hand-edit |
| Generator | `fvm dart run tool/gen_data_from_legacy.dart` |
| Lookup | `GameText.tr` / `RefText.tr` (`lib/app/strings.dart`): chosen language → English → the key; the data's own text through `DataText` (`turretName`, `tutorialPages`, …): chosen language → English → the document |
| Locale key | **language code only** (`Locale.languageCode`): `fr`, `de`, `ja`. No region or script variants |
| Offered languages | `supportedLocalesOf` = English + every string table; Settings → Language lists each table's `language.name` |
| Placeholder guard | `validateGameData` (`packages/onslaught_core/lib/src/data/game_data_validator.dart`) refuses unknown keys and changed `{placeholders}` |
| Coverage checker | `tool/check_translation.dart` (`fvm dart run`; `en` is checked as the source: shape and regenerated, never missing keys) |
| Material/Cupertino widget text | `flutter_localizations` (`GlobalMaterialLocalizations.delegates` in `lib/app/app.dart`) |
| Fonts | none bundled: the platform font renders every script |

## 0. Gate: can this language be added without code?

Pick the code: the ISO 639-1 two-letter code Flutter uses (`es`, `pt`, `zh`, `ko`). Then check
all of these. Any **no** → stop, report why, and propose the code change; do not work around it.

1. **Flutter's widgets speak it.** Both commands must print the code (otherwise Material
   widgets have no localisations for it and the app fails in that locale):

   ```bash
   sed -n '/kMaterialSupportedLanguages = /,/]);/p' .fvm/flutter_sdk/packages/flutter_localizations/lib/src/l10n/generated_material_localizations.dart | grep "'fr'"
   ```

   ```bash
   sed -n '/kCupertinoSupportedLanguages = /,/]);/p' .fvm/flutter_sdk/packages/flutter_localizations/lib/src/l10n/generated_cupertino_localizations.dart | grep "'fr'"
   ```

2. **One language code is enough.** The app keys tables by language code alone, so
   `pt-BR` vs `pt-PT`, `zh-Hans` vs `zh-Hant`, `sr-Latn` vs `sr-Cyrl` cannot both ship. If the
   owner wants a specific variant, ship it under the bare code (say which variant in the
   README table) only if they agree that the other variant will never be added; otherwise
   region/script support is a code change first.
3. **Left-to-right, or the owner has signed off on RTL.** Arabic, Hebrew, Persian, Urdu etc.
   are mirrored by Flutter automatically, but the HUD, tray, road and editors have
   never been checked right-to-left. RTL needs the owner's go-ahead and the full QA pass in
   step 6 on every screen, and any layout fix is a separate code change.
4. **It is not already there:** `ls l10n/` (if it exists, follow "Updating a language" below).

## 1. Start the file

Get the work list (every English key with its text, in table order):

```bash
fvm dart run tool/check_translation.dart fr --todo > "$TMPDIR/fr.todo.json"
```

Create `l10n/fr.json` with exactly this shape (UTF-8, real characters, not `\u` escapes,
2-space indent, keys in the same order as the work list):

```json
{
  "schemaVersion": 1,
  "locale": "fr",
  "strings": {
    "language.name": "Français",
    "...": "..."
  }
}
```

For a large batch, translate the work list in chunks by namespace (`ui.menu.*`,
`ui.settings.*`, `flow.*`, …) and merge each into `strings`; `--allow-missing` (step 3) lets
you check a partial file.

## 2. Translate: the rules

- **Keys** are copied exactly. Never invent a key; a key you omit shows in English.
- **`{placeholders}`** are copied verbatim, every one, spelling unchanged (`{name}`, not
  `{nom}`). Move them anywhere in the sentence the grammar needs.
- **`language.name`** is the language's own name as its speakers write it (endonym:
  `Deutsch`, `日本語`, `Español`), capitalised as that language capitalises it.
- **No plural machinery.** `fill` only substitutes text, so a `{count}`/`{kills}`/`{value}`
  string must read correctly for 0, 1 and many: prefer the "Label: {count}" form over a
  sentence that needs agreement.
- **Numbers are not localised** (they arrive as `1234`, `1.5`); don't add separators or units
  around a placeholder that the English doesn't have.
- **Keep untranslated:** product and proper names — `ONSLAUGHT 3`, `Onslaught 3 Remastered`
  (`app.title`, `ui.menu.title`), the people named in `ui.menu.credits`, and the `Remastered`
  subtitle unless the owner asks otherwise. The checker warns on these; that's expected.
- **Game vocabulary** follows `.agents/glossary.md` (a "poison" is a slow, a "creep" is an
  attacker, a "combo" is a colour recipe…): translate the meaning, and use one term per
  concept everywhere (turret, wave, kills, cash, tray, sandbox).
- **`badge.*`** (`badge.blue/green/red/yellow`) is a single character drawn on a turret for
  colour-blind players: the first letter of that colour's name in the language, and the four
  must be different. For scripts without letters, pick one short, distinct glyph per colour.
  When two first letters collide (German: **G**rün / **G**elb), keep the English letters
  `B G R Y` for all four rather than inventing a letter, and say so in the README table.
- **Length.** The UI is a phone first, and a portrait phone is only 375 pt wide (iPhone SE);
  HUD buttons, tray labels, sheet buttons and settings rows are tight. Stay close to the English length; when a literal translation is much longer,
  choose the shorter natural phrasing.
- **Tone.** `flow.*`, `message.*`, `editor.*`, `mods.*` are the original game's own words
  (casual, British spelling): translate the voice, not the double spaces between sentences.
- **Provenance.** If an agent produced the translation, it is a machine translation: say so
  in the README table (step 7) and in the commit, and ask the owner whether it needs a
  native speaker's review before release.

## 3. Check coverage and correctness

```bash
fvm dart run tool/check_translation.dart fr
```

It must end with `0 errors, 0 missing`. Fix every `ERROR` (unknown key, placeholder
mismatch, empty value, wrong shape, `language.name` left as English). Read every `WARN`
(same as English) and keep only the deliberate ones from step 2. A finished language has
no missing keys; ship a partial one only with the owner's agreement (the missing keys show
in English).

## 4. Regenerate the data

```bash
fvm dart run tool/gen_data_from_legacy.dart
```

```bash
git status --short assets/data l10n
```

Expect exactly: `l10n/fr.json` (new), `assets/data/strings/fr.json` (new) and
`assets/data/manifest.json` (one added `strings/fr.json` line). Anything else changed means
the generator input moved under you (someone edited `l10n/en.json` or the legacy table):
stop and find out why before going on.

## 5. Platform metadata (iOS and macOS)

Flutter's iOS localisation guide requires the bundle to declare its languages, and the App
Store lists them from the same key. In **both** `ios/Runner/Info.plist` and
`macos/Runner/Info.plist`, keep a `CFBundleLocalizations` array listing `en` and every
`l10n/` language (add the key, after `CFBundleDevelopmentRegion`, with the first language):

```xml
	<key>CFBundleLocalizations</key>
	<array>
		<string>en</string>
		<string>fr</string>
	</array>
```

Android, web, Windows and Linux need nothing: Flutter reads the system language list.
(Android 13's per-app language picker would need a `locales_config.xml`; not set up in this
project — propose it separately if wanted.)

Unverified on a device as of 2026-10-19: whether iOS reports the device language to the app
without this key. Add it anyway.

## 6. Verify

1. Tests (rule R14: all three before calling it done):

   ```bash
   fvm flutter analyze
   ```

   ```bash
   fvm flutter test
   ```

   ```bash
   cd packages/onslaught_core && fvm dart test
   ```

   `snapshot_test.dart` passes only if step 4 was run; the data validator (run on every
   load) fails on placeholder or key mistakes the checker missed;
   `test/l10n/ui_strings_test.dart` already covers language switching generically, so a new
   language needs no new test.
2. **See it running** (`flutter-run-and-hot-reload`, then `ios-simulator-qa` or
   `android-emulator-qa`). Settings → Language → the new `language.name`, then walk every
   screen at the smallest landscape phone size and at 375 pt wide in portrait: home, Settings, mode select, challenge
   picker, map select, a game (HUD, tray, turret sheet, pause, wave messages, game over),
   records, map library/editor, mods. Look for clipped, ellipsised or overlapping text and
   watch the run log for overflow (`$T` and the log path as in `flutter-run-and-hot-reload`):

   ```bash
   grep -i "overflowed" /tmp/flutter-$T.log
   ```

   Then check the device-language path: with Settings → Language on *Device language*, set
   a simulator's system language and relaunch; the game must come up in it. Verified on
   iOS 2026-10-19 (use a spare phone such as `iPhone 17e`, the smallest, so the default QA
   device keeps English):

   ```bash
   D="iPhone 17e"; xcrun simctl boot "$D"; xcrun simctl bootstatus "$D" -b
   ```

   ```bash
   xcrun simctl spawn "$D" defaults write -g AppleLanguages -array de-DE && xcrun simctl spawn "$D" defaults write -g AppleLocale -string de_DE && xcrun simctl shutdown "$D" && xcrun simctl boot "$D"
   ```

   Then install and launch the simulator build (`ios-simulator-qa` §2) and screenshot the home
   screen. The web build in the agent's built-in browser at 844×390 is a quick way to walk
   the menus and Settings, but taps on the game board did not register there (2026-10-19):
   check the in-game HUD, tray and sheets on a simulator or emulator.
3. Report what you saw with `qa-report` (screens checked, screenshots of the tightest ones,
   any overflow). Overflow is fixed by a shorter translation first; a layout change is a
   separate code change (with `golden-tests`).

## 7. Record and commit

- `l10n/README.md`: add a row to the **Languages** table (code, name, coverage, who
  translated it / machine or reviewed, date).
- `CHANGELOG.md`: under the unreleased version, "Language: <English name> (<endonym>)".
- One commit: `data: add <English name> (<code>) translation` with the checker's summary line,
  test results and QA outcome, and whether the text is machine-translated.

## Updating a language (English changed)

After any edit to `l10n/en.json` or the legacy strings, every translation can fall behind.
Missing keys show in English at runtime (not a crash), but a **renamed placeholder** or a
**removed key** makes the data validator reject the whole table, so the build's tests fail.

```bash
fvm dart run tool/gen_data_from_legacy.dart
```

```bash
find l10n -name "*.json" -exec basename {} .json \; | while read -r code; do fvm dart run tool/check_translation.dart "$code"; done
```

The loop includes `en`: it must also end with `0 errors, 0 missing` (an error there means
`l10n/en.json` changed and the data was not regenerated). For each other language: remove keys reported as unknown, fix placeholder errors, translate the
`--todo` list, then rerun steps 3–4 and 6.1, update the coverage in the README table, and
commit as `data: update <language> translation`. A key whose English *meaning* changed but
whose key did not is invisible to the checker: grep the diff of `l10n/en.json` for changed
values and retranslate those keys too.
