---
name: phase-task
description: How to start, scope, execute and close any unit of implementation work in this project so every task is planned against the phase plan, respects the tenets and rules, and ends with the definition of done. Use at the start of every coding task.
---

# Running a task

## 1. Frame it (before touching code)

1. Restate the task in one sentence and map it to a phase and bullet in
   `docs/REMASTER_PLAN.md` §7. If it fits no phase, say so and ask whether it is in scope.
2. Find the original behaviour for anything gameplay-related in
   `docs/ONSLAUGHT2_GAME_REFERENCE.md`; use `legacy-lookup` if it is missing or unclear.
3. Decide which layer each change belongs to (`.agents/architecture.md`): data, core
   rules/sim, Flame view, HUD widget, service, tool. If a change crosses from data into
   code, check rule R4/R7: can it be data + registry instead?
4. List the files you will touch and the tests you will add (rule R16), and the fixtures
   or goldens you expect to change. Post this list before editing when the task is more
   than a one-file change.
5. Check the rules file for anything the task might collide with (R1–R23). If the task
   requires breaking a rule or changing a standard, stop and ask (rule R24).

## 2. Execute

- Work in small compiling steps; run the narrowest relevant test after each step.
- Data first, then core, then view, then UI; each with its tests, so a half-done task is still green.
- Keep a running note of assumptions and anything unverified for the final report.
- Use the platform skills to see UI changes running; never describe a screen you did not view.
- If you discover an original bug, decide with the deviation table (`docs/DEVIATIONS.md`): copy it under `classic`, fix it behind a toggle, document it.

## 3. Close

Run the full definition of done (`.agents/workflow.md`):
```bash
fvm dart format --set-exit-if-changed .
fvm flutter analyze
fvm flutter test
(cd packages/onslaught_core && fvm dart test)
```
Then the report: what changed (files), what was verified and how (test names, screenshots,
bot tables), what was not verified, deviations recorded, docs/`.agents` touched, open questions.
Commit only when asked (R19), with a conventional prefix and the fixture/golden reasons in the body.

## Scope guard

- The requested scope is the deliverable. Do not quietly narrow it (report what was left and why) or widen it (propose extras separately).
- A refactor "while you are there" that touches a frozen area (classic data, fixtures, goldens) is a separate task needing a decision.
