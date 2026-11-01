---
name: data-change
description: The end-to-end procedure for changing a balance value or adding data content (turret, combo recipe, projectile, blast, map, wave curve, challenge preset, string) so that code stays data-driven and every guard rail is updated. Use for any edit under assets/data or the data generator.
---

# Data change procedure

Balance lives in `assets/data/*.json`, generated from `tool/gen_data_from_legacy.dart`
for original values and hand-edited for new content. Code must not grow a branch for a
new piece of content; if it does, the change is in the wrong place.

## 1. Decide what kind of change it is

| Kind | Where it goes | Also required |
|---|---|---|
| Original value correction | generator input (then regenerate) + reference doc | cite legacy source (`legacy-lookup`) |
| Deliberate rebalance (v2 only) | a new `RulesProfile` / `ContentPack`, never the classic data | `docs/DEVIATIONS.md` row |
| New turret | `turrets.json` entry; behaviour id must exist in `RulesRegistry` | asset ids in pack manifest, strings, reviews, tray order |
| New combo recipe | `combos.json`: leader colour, requirement counts, priority, projectile spec + overrides, blast, take rule, recharge, sound | scenario test, regression fixture |
| New projectile/blast | `projectiles.json` / `blasts.json` | kind must exist in the registry |
| New map | `assets/data/maps/<id>.json` (inside 720×480, start/road/base) | thumbnail, road golden, balance bot run |
| Wave/difficulty curve | `difficulty.json`, `waves.json` | balance bots |
| Challenge preset / picker | `challenges.json` | preset test |
| Strings | `l10n/en.json` (merged into `strings/en.json` by the generator); a name, label, tutorial page or descriptor text is edited in its data document, and the generator copies it (`DataTextKeys`) | widget tests that pin text; the same text in every `l10n/` language in the same change (R25, `add-language`); a renamed id leaves its old key in every translation, which the validator then refuses |
| New language / translation | `l10n/<code>.json` | follow `add-language` |

## 2. Steps

1. Edit the data (or the generator input). Keep `schemaVersion` unchanged unless the shape changes.
2. `fvm dart run tool/gen_data_from_legacy.dart` if an original value moved; otherwise skip.
3. `cd packages/onslaught_core && fvm dart test test/data/` — schema, ranges, referential
   integrity, snapshot diff. A snapshot diff you did not intend means you edited generated output by hand: fix the input instead.
4. Run the rule tests that pin the value (`grep -rn "<old value>" packages/onslaught_core/test`) and update them **only** if the change is intended.
5. Run scenarios + regression fixtures. A fixture diff means behaviour changed: either the
   change is wrong, or you re-record with `--update-goldens` and explain in the commit (see `regression-fixtures`).
6. For anything affecting progression (costs, damage, HP curve, waves, maps): run the
   balance bots (`balance-bot`) and paste the before/after wave-reached table in the PR.
7. Update `docs/ONSLAUGHT2_GAME_REFERENCE.md` (original values) or `docs/DEVIATIONS.md` (deliberate changes).
8. Commit as `data: <what>` with the reason and the evidence from steps 3–6.

## 3. Standards

- No numeric balance literal in Dart (rule R7). If a system needs a new tunable, add it to
  the schema with a descriptor (title, description, min, max, step, unit) so the mod editor exposes it automatically.
- Every data record has an `id` (stable, kebab-case) and human `name`; ids never change once shipped (saves and share strings reference them).
- A schema change adds the field to the record's `fromJson` and `toJson` (`packages/onslaught_core/lib/src/data/`), then the generator builds it (`data_gen/gen_*.dart`); `test/data/round_trip_test.dart` checks both directions against the committed documents.
- Arrays that pair keys and values (`cost`/`amount`, `wave`/`rate`) stay parallel arrays with a length check in the schema, mirroring the original indexed-array type.
- Descriptors for new values follow the original ranges where one exists (e.g. range 10–800, rate 1–300, poison 0–40).
- Content for v2 goes in a content pack, not in the classic files; the classic files are frozen by the regression suite.
