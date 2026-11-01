# Workflow

## Commands (always via fvm)

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test                      # app tests (widget, golden, integration-lite)
cd packages/onslaught_core && fvm dart test   # core sim/rules/data/regression tests
fvm dart format .                     # page width 100 (analysis_options.yaml)
fvm flutter run -d macos              # or an iOS simulator / Android emulator id
fvm flutter run -d macos --dart-define=ENHANCED_SKIN=true   # QA the Enhanced skin (rails, far-side panel, ground) before E0
fvm flutter test --update-goldens     # only when a visual change is intended (rule R15)
fvm dart run tool/gen_data_from_legacy.dart   # regenerate assets/data from docs/legacy/legacy_values.json + l10n/
fvm dart run tool/check_translation.dart <code>      # add-language checker (en is the source)
tool/export_assets.sh                 # re-export art/audio from the SWF (needs FFDec + Java + rsvg-convert)
fvm dart run tool/legacy_extract.dart # one-off/audit: re-extract docs/legacy/ from .legacy/
fvm dart run tool/legacy_extract.dart --transcribed  # after editing engine_constants.dart; no .legacy/ needed
(cd packages/onslaught_core && fvm dart run tool/fixture.dart record|diff|show <id>)   # regression fixtures
fvm flutter test --coverage --coverage-package='^onslaught3_remastered$'   # app coverage
fvm dart run tool/check_coverage.dart coverage/lcov.info 70 packages/onslaught_core/coverage/lcov.info 85
fvm flutter test integration_test -d emulator-5554   # device smoke test + soak (also macos, iOS sim)
fvm flutter test integration_test/soak_test.dart -d emulator-5554 --dart-define=SOAK_WAVES=40   # quick device soak
(cd packages/onslaught_core && fvm dart test --run-skipped -t soak)   # headless 3× soak to wave 300
(cd packages/onslaught_core && fvm dart run tool/web_regression.dart)   # fixtures replayed in Chrome (-c dart2wasm for WebAssembly)
fvm dart run tool/gen_app_icons.dart   # app icons + launch images for every platform (tool/branding/)
```

## Definition of done (every task)
1. The change is complete for the scope asked, or the report says exactly what was left out and why.
2. `fvm flutter analyze` is clean; all test suites pass; new behaviour has tests (rule R16).
3. Data edits come with regenerated snapshots; fixture updates are explained (R8, R15).
4. Docs and `.agents/` updated if the change made them stale (R20).
5. New or changed user-facing text is translated into every `l10n/` language and the
   `add-language` checker reports `0 errors, 0 missing` for each (R25).
6. The final report states what was verified, how, and what was not.

## Planning a task
- For anything beyond a one-file change: list the files you will touch and the tests you
  will add before editing. Check `docs/REMASTER_PLAN.md` §7 for which phase the work
  belongs to and `docs/ONSLAUGHT2_GAME_REFERENCE.md` for the exact original behaviour.
- When a rule is ambiguous, open the legacy class (see `.agents/legacy-source.md`), cite it,
  and if you choose to deviate, add a row to `docs/DEVIATIONS.md` and a `RulesProfile` toggle.

## Recipes

**Change a data schema** → add the field to the record's `fromJson` and `toJson`, build it in
the generator (`data_gen/gen_*.dart`), regenerate; the round-trip test checks both directions.

**Add or change a balance number** → edit the generator input / data JSON, regenerate,
run data-contract tests, update any rule test that pins the value, run balance bots if the
change affects progression.

**Add a turret** → data entry in `turrets.json` (stats, tracks, flags, asset ids, names) →
if it needs a new special, implement a behaviour and register it in `RulesRegistry` →
rule tests + a scenario + a regression fixture → tray/sheet UI reads it from data (no UI
code should need to change) → asset ids present in the classic pack manifest.

**Add a combo recipe** → `combos.json` (requirements, priority, projectile spec +
overrides, blast, take rule, sound) → scenario asserting spawned entities and damage →
regression fixture → reference doc row.

**Add a map** → `assets/data/maps/<id>.json` validated inside 720×480 with start, road,
base → road-render golden → balance bot run.

**Change UI** → implement against `FakeGameViewModel` first (widget tests + goldens at
phone/tablet/desktop), then wire. Never read sim state directly from a widget.

**Swap or add an asset pack** → implement `AssetPack`, register in the chain, run the
asset-manifest test; procedural packs must be deterministic for a given seed.

**Redraw a sprite that is only a bitmap in the SWF (Enhanced only)** → SVG in `tool/art/` in
frame coordinates, an entry with `"svg"` in `tool/asset_map_enhanced.json`, re-pack with
`tool/pack_atlas.dart --map tool/asset_map_enhanced.json`, asset-manifest tests
(ffdec-asset-export skill §4). Classic keeps the original art.

**Add a persisted field** → bump `schemaVersion`, add a `Migrator` step, add a fixture
from the previous version, test round-trip.

## Fixture policy
Regression fixtures (`test/fixtures/regression/*.json`) are the frozen behaviour of v1.
They change only when behaviour changes on purpose; the PR must name the fixture, the
rule that changed and why. Goldens follow the same policy.

## Git
- Branch per task; conventional commit prefixes; no commits or pushes unless asked (R19).
- Never commit generated caches, `.dart_tool`, build output, or anything under `.legacy/`
  that is not already tracked.
