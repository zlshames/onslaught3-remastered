---
name: balance-bot
description: Run the headless balance bots (scripted strategies that play the simulation at maximum speed) to check that data or rule changes keep the game's difficulty curve within tolerance, and to produce before/after tables for a PR. Use for any change to costs, damage, ranges, HP curves, waves, maps or targeting.
---

# Balance bots

A bot is a deterministic strategy (build order + upgrade policy + wave-send policy) run
through `SimTestHarness` with a fixed seed on a given map/difficulty/profile. The output
is the wave reached, lives lost per 50 waves, cash over time and kill counts. Bands are
tolerances around the recorded baseline. Bots live in
`packages/onslaught_core/test/balance/` and are built in Phase 1; the standard applies from then.

## Roster (baseline recorded on first green run)

| Bot | Map / difficulty | Strategy | Proves |
|---|---|---|---|
| `blue-rush` | Classic / easy | spam Blue near corners, max damage first | early game, combos trigger |
| `four-colour` | Classic / medium | 2 of each colour in combo range, round-robin upgrades | combo recipes and modifiers |
| `red-green-link` | Incoming / hard | red rockets + linked greens, rate upgrades | links, holding, BFG |
| `super-late` | Sinus / hard | reaches sniper/railgun/fusion unlocks | late-game scaling |
| `sandbox-everything` | Lyne / sandbox2 | all 16 turrets | nothing crashes with everything active |
| `challenge-<preset>` ×14 | per preset | preset-appropriate strategy | each preset is winnable or fails as intended |

## Commands

```bash
cd packages/onslaught_core
fvm dart test test/balance                                   # all bots vs baselines (slow; also nightly)
fvm dart run tool/balance.dart run blue-rush --seed 42 --waves 300
fvm dart run tool/balance.dart compare --base main --head HEAD    # before/after table for a PR
fvm dart run tool/balance.dart baseline blue-rush            # re-record baseline — only with a stated reason
```
The compare output is a Markdown table (bot, waves reached base/head, lives lost, time to
first combo, cash at wave 50/100/200) — paste it into the PR when data changes.

## Interpreting results

- Within band: fine. Band widths live in `test/balance/bands.json` (default ±5 % waves, ±1 life).
- Out of band after an *original-value correction*: the previous baseline was wrong; re-record and say so.
- Out of band after a *deliberate rebalance*: expected; re-record under the new `RulesProfile`/content pack, never under `classic`.
- Out of band after a *code refactor*: a bug; fix the code.
- Crash or exception at any wave: always a bug, regardless of bands.
- Bots also serve as the 3× soak: `--waves 300 --speed 3` must finish without exceptions and within the per-tick perf budget.

## Standards

- Bots are seeded and deterministic; a flaky bot is a determinism bug (see `regression-fixtures`).
- Strategies are data too (`test/balance/strategies/*.json`): build order, upgrade priority, send-wave rule; adding a strategy does not need Dart changes.
- Baselines are committed and reviewed; re-recording names the cause.
- Nightly CI runs the full roster and posts the compare table; PR CI runs the three fastest bots on data changes.
