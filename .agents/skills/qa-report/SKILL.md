---
name: qa-report
description: The standard format and checklist for reporting a QA finding, bug reproduction or verification result in this project, so every report has the same shape, evidence and next step. Use at the end of any manual test, bug hunt or visual check.
---

# QA report standard

A report is written so a reader who did not watch the session can act on it. It lives in
the task's final message and, for bugs, as a test.

## Required sections (in this order)

1. **Summary** — one sentence: what was tested, pass/fail, on which device.
2. **Environment** — platform, device/AVD/simulator name, OS version, build type
   (debug/profile/release), commit or branch, rules profile and seed if a game was run,
   `--dart-define`s used.
3. **Steps** — numbered, each one a single action in the user's terms ("tap Blue in the
   tray", not "input tap 2308 901"); include the exact command when it matters.
4. **Expected vs actual** — one line each, with a reference to the rule in
   `docs/ONSLAUGHT2_GAME_REFERENCE.md` or `docs/REMASTER_PLAN.md` that defines "expected".
5. **Evidence** — screenshots (`/tmp/qa/NN-description.png`, viewed, one line describing
   what each shows), log excerpts (≤ 20 lines, trimmed to the relevant part), frame stats
   if performance related, the UI-tree node if a control was missing.
6. **Scope checked / not checked** — what else was verified in the same session and what
   was deliberately not (other platforms, other difficulties, large text).
7. **Repro as a test** — for a confirmed bug: the integration or scenario test added (file
   path), or the reason none could be written yet.
8. **Suggested cause / next step** — optional, clearly marked as a hypothesis.

## Rules

- Never report "works" without evidence (a viewed screenshot, a test run, a log line).
- Report failures verbatim (error text in a code block), never paraphrased as passing.
- Name the device by its real name (`Pixel_10_Custom_RAM`, `iPhone 17 Pro`), and the
  commit (`git rev-parse --short HEAD`) so the result is reproducible.
- Keep screenshots at physical resolution; mention the logical scale (÷2.625 Android AVD,
  ÷3 iPhone 17 Pro) when giving coordinates.
- One report per flow; do not merge unrelated findings.
- Game-rule findings cite the original source (`.agents/legacy-source.md`) when the
  question is "is this faithful?".

## Template

```
**Summary:** <flow> — PASS/FAIL on <device>.
**Environment:** <platform/os>, <build>, <commit>, profile=<classic|classicFixed>, seed=<n>
**Steps:**
1. …
**Expected:** … (ref: GAME_REFERENCE §x)
**Actual:** …
**Evidence:** /tmp/qa/01-….png (shows …); log: ```…```
**Checked / not checked:** …
**Repro test:** integration_test/…_test.dart (or: not yet, because …)
**Next step:** …
```
