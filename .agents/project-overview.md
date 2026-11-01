# Project overview

**Onslaught 3 Remastered** is a cross-platform Flutter rebuild of *Onslaught 2*, a 2008
Flash tower-defence game (code and engine by Gaby Vanhegan, sound by Anthony Galante).
The original is a 720×480 single-path TD with four colour turrets whose fully-upgraded
neighbours fire 20 different combo weapons, plus modifier auras, super turrets, endless
waves, challenges, a sandbox, a map editor and a mod system.

## Status (updated 2026-10-19)

- Phase 0 (foundations) is implemented: pub workspace with `packages/onslaught_core`,
  typed data + loader + validator + mod deltas, all `assets/data` generated from the legacy
  reference table, classic asset pack (atlases 1× to 9× loaded per zoom, sounds), an Enhanced asset pack (vector creep redraws, for Enhanced games only), extension seams
  (`AssetPack`, `GameViewModel`, `RulesRegistry`, `RulesProfile`, `FeatureFlags`), test
  harness (`SimTestHarness`, `FixtureRecorder`, `FakeGameViewModel`, goldens, architecture
  tests, coverage gates), CI workflows, and a `GameScreen` with pan/zoom over any built-in
  map.
- Phase 1 (core loop) is implemented: waves, creeps, Blue, targeting, upgrades, sell, move,
  game over, HUD v1 (top bar, tray, selected-turret sheet), first regression fixtures.
- Phase 2 (four colours + specials) is implemented: Green link pooling, Red rockets and
  holding pattern, Yellow sparks/slows/charge, freakouts, the seven modifier auras, weapon
  unlocks by kills, message toasts, audio cues for game events, and a sheet card per special.
- Phase 3 (combos and ordnance, all 20 recipes) and Phase 4 (super turrets) are implemented.
- Phase 5 (modes, progression, menus) is implemented: main menu over the attract demo, mode /
  map / challenge / settings screens, challenge objectives, time and turret limits and presets,
  the tutorial (pages, "Show me" arrows, 50-wave end), unlock milestones, best games, the
  `profile` document and a debug unlock-all toggle.
- Phase 6 (map editor + sharing) is implemented: Map Tools (`/maps` library, `/editor`) with
  touch editing (palette start/base, tap to add, drag, "+" handles, delete, nudge keys, 20 px
  grid and align all, undo/redo, pinch-zoom), validation (start, base, minimum road length),
  save/load/delete in the `maps` document, `ons3:map:` share codes (`ShareCodec`) with import,
  play at a chosen difficulty, thumbnails, and the `MapGenerator` seam with its contract test.
- Phase 7 (mod/data editor) is implemented: the Mods screen (`/mods`) generated from
  `mod_editor.json` (the original's items and values, each mapped to its place in the data)
  and `descriptors.json`, with number/boolean/string/indexed widgets, min/max checks and the
  data's own validation, reset value/item/all, the "use in new games" switch, the signature
  and in-game watermark, the `mods` document, and `ons3:mod:` share codes with import (which
  also reads the original game's mod saves). A mod applies from the next game.
- Phase 8 (polish and release) is in progress (2026-10-19): rocket smoke trails with the
  original's smoke settings, vibration, a Tower placement setting (drag and drop, or
  drop and lock: release drops the ghost, a drag anywhere nudges it, Place builds),
  colour-blind-safe badges (shape + letter) on the
  colour turrets, accessibility checks and large-text goldens on every screen, the
  localisation hook (`GameText.tr`, `l10n/` translations, language setting), custom games
  (mod on or player map) kept out of progress with their own records (`profile.custom`,
  Records page, Map Tools; edited roads keep earlier versions' records), app icons and launch screens from the original
  art (`tool/gen_app_icons.dart`), release signing via `android/key.properties`, the release
  workflow (gates + all six platform builds), and the 3× soak to wave 300 (headless and
  on device). See `docs/REMASTER_PLAN.md` §7.
- The original's values are extracted once into `docs/legacy/` (see its README); the
  behavioural spec is `docs/ONSLAUGHT2_GAME_REFERENCE.md` (with a corrections section).

## Targets

- iOS, Android (primary, portrait and landscape), web, macOS, Windows, Linux.
- v1 = exact behavioural copy of the original. v2+ may change UI, art and features.

## Toolchain

| Tool | Version / location |
|---|---|
| Flutter | 3.47.6 stable via **fvm** (`.fvmrc`); always `fvm flutter`, `fvm dart` |
| Dart | 3.13 |
| Flame | pin `^1.38.0` (do not use the 2.0 dev prerelease) |
| Java 21 | Homebrew, needed only for FFDec |
| FFDec 26.3 | `~/Downloads/ffdec_26.3.0_macosx/FFDec.app/Contents/Resources/ffdec-cli.jar` (developer machine; not a build dependency) |

## Repo map

```
AGENTS.md, CLAUDE.md        agent entry point and redirect
.agents/                    this folder: preloaded agent context
docs/REMASTER_PLAN.md       architecture, UI design, phases, testing (the plan)
docs/ENHANCED_PLAN.md       Enhanced mode: design brief, phases E0+, open decisions
docs/ONSLAUGHT2_GAME_REFERENCE.md  original rules + all balance tables (the spec)
docs/DEVIATIONS.md          deliberate departures from the original
docs/legacy/                the original's values as a reference table (legacy_values.json,
                            LEGACY_VALUES.md) and engine behaviour notes (ENGINE_NOTES.md)
docs/README.md, docs/history/  index of every document with its status; finished plans
lib/                        Flutter app: app/, features/{menu,game,editor,mods,tutorial}, services/
packages/onslaught_core/    pure-Dart data model + simulation + rules; test harness in lib/testing.dart;
                            fixtures in test/fixtures/, fixture tool in tool/fixture.dart
assets/data/                JSON balance/content data (generated from docs/legacy/legacy_values.json)
assets/images/classic, assets/audio/classic  classic asset pack (atlases, manifest, sounds)
assets/images/enhanced      Enhanced asset pack (vector creep redraws), layered over classic
tool/                       legacy_extract.dart (one-off), gen_data_from_legacy.dart,
                            export_assets.sh + pack_atlas.dart + asset_map.json (classic) and
                            asset_map_enhanced.json, art/ (SVG redraws for the Enhanced pack), check_coverage.dart
.github/workflows/          ci.yml (PR gate), nightly.yml, release.yml, pages.yml (web build → GitHub Pages)
test/, packages/*/test/     tests; goldens and regression fixtures live beside them
.legacy/Onslaught2.swf      the original game (read-only)
.legacy/deobfuscated/       readable ActionScript 2 export (use this)
.legacy/dissassembled/      raw obfuscated export + sprites/sounds/fonts/texts (assets only)
```

## Key numbers to keep in your head

Play area 720×480 world px (3:2), 10 lives, $30 start, waves of 10 every 20 s, 9 creep
types, combo range 70 px, turret footprint ~36 px, sell refund 70 %, score = kills × spent.
Everything else: look it up in the reference doc, never from memory.
