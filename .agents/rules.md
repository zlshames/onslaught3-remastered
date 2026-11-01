# Rules

Hard constraints. "MUST" and "MUST NOT" are literal. If a task cannot be completed
without breaking one, stop and ask instead of breaking it.

## Architecture
- R1. MUST NOT import `package:flutter/*`, `package:flame/*`, `dart:ui` or `dart:io` in
  `packages/onslaught_core`. (Tenet 3; enforced by the architecture test.)
- R2. MUST NOT import Flame types in `lib/features/*/hud/` or any Flutter widget; widgets
  talk to the game only through `GameViewModel` / `GameCommand`.
- R3. MUST NOT let features import each other's internals; cross-feature communication
  goes through the session facade, `GameEvent`s or Riverpod providers in `lib/app/`.
- R4. MUST add new mechanics by registering a behaviour in `RulesRegistry` and adding
  data, not by adding `if (turret.type == …)` branches to existing systems.
- R5. MUST reference art, audio and fonts by logical asset id resolved through the
  `AssetPack` chain; MUST NOT reference asset file paths from rules or widgets.
- R6. MUST NOT add a package dependency without appending a row (package, purpose,
  alternatives considered) to the dependency log in `.agents/architecture.md`.

## Data and balance
- R7. MUST NOT hard-code a balance value (damage, cost, range, rate, timing, radius,
  threshold, probability) in Dart outside `assets/data`. Allowed literals in `rules/` and
  `sim/`: 0, 1, -1, 2, 100, 360, 1000 (in int or double spelling), 0.5 in round-half-up,
  and unit conversions. The no-magic-numbers test also scans `data/` and `testing/`.
  (Enforced by that test; extend its allowlist only with a comment explaining why.)
- R8. MUST regenerate the data snapshot (`tool/gen_data_from_legacy.dart`) or update the
  reference doc when a data value changes, and say which in the commit.
- R9. MUST keep every persisted document (`profile`, `settings`, maps, mods, share
  strings, replays) schema-versioned and add a migration + fixture when its shape changes.
- R10. MUST NOT change original behaviour silently. Any departure from the original
  rules is a `RulesProfile` toggle, documented in `docs/DEVIATIONS.md` with the reason.

## Legacy material
- R11. MUST NOT modify, delete, move or build anything under `.legacy/`. It is read-only
  reference: the SWF, the raw obfuscated export, and the deobfuscated source.
- R12. MUST read `.legacy/deobfuscated/` (readable) rather than
  `.legacy/dissassembled/scripts/` (obfuscated) when checking original behaviour, and
  MUST cite the file (and function) you relied on when making a faithfulness decision.
- R13. MUST NOT copy obfuscated or decompiled code into the project; re-implement the
  behaviour in idiomatic Dart with tests.

## Testing and verification
- R14. MUST run `fvm flutter analyze` (zero warnings) and the full test suites
  (`fvm flutter test` and `fvm dart test` in `packages/onslaught_core`) before reporting a
  task complete, and MUST report failures verbatim rather than describing them as passing.
- R15. MUST NOT update a regression fixture, golden or balance-bot tolerance unless the
  same change deliberately alters the behaviour and the commit message says so.
- R16. MUST add tests with new behaviour: rule tests for formulas, a scenario for sim
  changes, a fixture for new recipes/turrets/projectiles, widget + golden tests for UI,
  a migration fixture for persisted-shape changes.
- R17. MUST NOT skip, delete or `@Skip` a failing test to get green; fix it or ask.

## Process
- R18. MUST ask before destructive or irreversible actions: deleting non-generated files,
  rewriting git history, force-pushing, dropping persisted data, changing CI secrets.
- R19. MUST NOT commit or push unless asked; when asked, one logical change per commit
  with a conventional prefix (`feat:`, `fix:`, `test:`, `data:`, `docs:`, `chore:`,
  `refactor:`). No AI attribution trailers are required by this project.
- R20. MUST keep `AGENTS.md`, `.agents/*` and `docs/*` consistent with the code in the same
  change that makes them stale.
- R21. MUST use the fvm-pinned toolchain (`fvm flutter`, `fvm dart`); MUST NOT run a
  global `flutter` or upgrade the SDK without being asked.
- R22. MUST NOT reintroduce the defunct online services (Playr score/map servers,
  Kongregate, MochiAds, GameGum) or any analytics/telemetry without an explicit request.
- R23. MUST state assumptions and unverified parts explicitly in the final report of a task.

## Standards
- R24. The standards (`AGENTS.md`, everything in `.agents/` including skills, `docs/REMASTER_PLAN.md`,
  `docs/DEVIATIONS.md`) change only by the project owner's decision. An agent MAY propose a
  change (quote the current text, the proposed text, and the reason) and MUST NOT apply it
  until the owner says yes in the conversation. Exception: fixing a verified factual error
  (a wrong path, version or command) is allowed and must be called out in the report.

## Localisation
- R25. MUST translate every user-facing string added or changed (an `l10n/en.json` or
  legacy-table string, or a name, label, tutorial page or descriptor in a data document)
  into every supported language (each `l10n/<code>.json`) in the same change, following
  `add-language` ("Updating a language"): regenerate the data and run its checker for every
  language until each ends with `0 errors, 0 missing`. Text is never hard-coded in a widget;
  it is looked up (`GameText.tr`, `DataText`). A machine translation says so in the commit
  and in the `l10n/README.md` table. (Owner decision, 2026-10-19.)
