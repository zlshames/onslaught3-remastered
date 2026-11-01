---
name: regression-fixtures
description: How to record, run, inspect, diff and deliberately update the faithful-mode regression fixtures (golden-state event logs) that freeze v1 behaviour of the simulation. Use when adding a recipe/turret/projectile, when a fixture test fails, or when a behaviour change is intended.
---

# Regression fixtures (golden-state tests)

A fixture is a recorded run of the simulation: scenario config (map, mode, difficulty,
rules profile, seed, scripted `GameCommand`s with tick numbers) plus the resulting
`GameEvent` log and a state hash every N ticks. The test replays the scenario and requires
the log and hashes to match exactly. This suite is what makes "v1 = the original" a fact
rather than a hope. The harness (`SimTestHarness`, `FixtureRecorder`) lands in Phase 0;
the standards below apply from the first fixture.

## Layout

```
packages/onslaught_core/test/fixtures/regression/
  <area>/<scenario-id>.json          # e.g. combos/blue-clusterbomb.json, waves/classic-easy-20.json
packages/onslaught_core/test/regression/<area>_test.dart   # one test per fixture, generated from the folder
```
Fixture JSON: `{ schemaVersion, scenario: {map, mode, difficulty, profile, seed, commands:[{tick, command}]},
ticks, hashEvery, events:[…], hashes:[…], recordedAt, recordedWith: <git sha> }`.

## Commands

```bash
cd packages/onslaught_core
fvm dart test test/regression                              # run all
fvm dart test test/regression -N "blue-clusterbomb"        # one scenario
fvm dart run tool/fixture.dart record --all                # re-record ALL — only with a stated reason (`dart test` has no --update-goldens)
fvm dart run tool/fixture.dart record combos/blue-clusterbomb   # record a new or single fixture
fvm dart run tool/fixture.dart diff   combos/blue-clusterbomb   # first differing tick, event and hash, side by side
fvm dart run tool/fixture.dart show   combos/blue-clusterbomb --from 240 --to 300
fvm dart run tool/web_regression.dart   # the regression and determinism suites in Chrome (-c dart2wasm for WebAssembly)
```

## Recording a new fixture (every new recipe, turret, projectile, blast, creep behaviour)

1. Write the scenario to exercise exactly one behaviour: minimal map (prefer `map9` "Lyne"
   or the tutorial map), minimal turrets, fixed seed, enough ticks for the behaviour to
   complete (combo fired → projectiles resolved → blast damage applied).
2. Record with `profile: classic` (bit-faithful) **and** `classicFixed` if the behaviour is
   touched by a deviation toggle; name them `<id>.classic.json` / `<id>.fixed.json`.
3. Read the recorded event log once by eye and check it against the reference doc
   (spawned entity kinds, damage numbers, timings). A fixture that encodes a bug you did
   not notice freezes the bug.
4. Add a short `description` field saying what the scenario proves.

## When a fixture fails

1. `fixture.dart diff` to find the first divergence. Classify it:
   - **Unintended** (you changed code that should not alter behaviour): fix the code.
   - **Non-determinism** (differs run to run): find the unseeded random, wall-clock read,
     unordered map iteration or float accumulation and fix it. Never widen tolerance.
   - **Intended** (the task is to change this behaviour): re-record only the affected
     fixtures, and in the commit message name each fixture, the rule that changed, and why.
2. Never update goldens to make CI green without the explanation; never `@Skip` the test (rule R17).
3. If an intended change alters `classic` fixtures, that is a deviation: it needs a
   `RulesProfile` toggle and a `docs/DEVIATIONS.md` row, and `classic` must keep the old recording.

## Standards

- Fixtures are reviewed like code: the PR diff must show the JSON change, and the reviewer checks the event deltas, not just the hash.
- Keep fixtures small (< ~2000 events); long soak runs belong to the balance bots.
- Determinism contract: same seed + commands ⇒ identical events and hashes on the VM (macOS and Linux CI) and in Chrome (dart2js, dart2wasm); fixtures are never per-platform (owner, 2026-10-20); a determinism test runs every fixture twice.
- Hash algorithm and event serialisation are versioned (`schemaVersion`); changing them re-records everything in one dedicated `test:` commit with no behaviour change, verified by the diff tool reporting event-equality.
