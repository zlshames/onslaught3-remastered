# AGENTS.md — Onslaught 3 Remastered

This file is the single entry point for any AI coding agent (Claude, Codex, Cursor, Gemini,
Copilot, Aider, …) working in this repository. Tool-specific files such as `CLAUDE.md` only
redirect here; do not put instructions anywhere else.

## Read this first (in order)

1. `.agents/project-overview.md` — what this project is, current status, toolchain, repo map
2. `.agents/tenets.md` — the principles every decision is measured against
3. `.agents/rules.md` — hard rules (MUST / MUST NOT). Violating one is a failed task.
4. `.agents/architecture.md` — layers, packages, data flow, extension seams
5. `.agents/workflow.md` — commands, definition of done, how to add things, fixtures
6. `.agents/legacy-source.md` — how to read the original Flash game when a rule is unclear
7. `.agents/glossary.md` — domain vocabulary (a "poison" is a slow, a "creep" is an attacker, …)
8. `.agents/skills/README.md` — index of reusable procedures (skills); load the matching
   `SKILL.md` when a task needs one (e.g. `android-emulator-qa` for anything on the Android AVD)

Deep references (read the relevant section when the task needs it, not up front):

- `docs/REMASTER_PLAN.md` — architecture, mobile UI design, phased build order, testing strategy
- `docs/ENHANCED_PLAN.md` — the Enhanced mode plan (phases E0+), beside Classic
- `docs/ONSLAUGHT2_GAME_REFERENCE.md` — the original game's rules and every balance number
- `docs/legacy/` — the original's values extracted once into a reference table
  (`legacy_values.json`, `LEGACY_VALUES.md`) plus engine behaviour notes (`ENGINE_NOTES.md`);
  `assets/data` is generated from it, so look numbers up there rather than re-reading `.legacy/`

## The project in one paragraph

A cross-platform Flutter remaster of the Flash tower-defence game *Onslaught 2*. Version 1
must behave exactly like the original (rules, numbers, maps, combos), rebuilt on a
pure-Dart simulation core with a data-driven balance layer, rendered with Flame, and
given a touch-first UI for portrait and landscape. Later versions may replace the UI, the art (including
procedurally generated art), and add features; the architecture and the test suite exist
to make that safe.

## Tenets (summary — full text in `.agents/tenets.md`)

1. **Faithful first.** v1 is the original game. When unsure, read the legacy source, not your memory.
2. **Data over code.** Balance numbers live in `assets/data/*.json`; code holds behaviour only.
3. **Pure core.** `packages/onslaught_core` has no Flutter or Flame imports, ever.
4. **Swappable edges.** UI, art, audio, content and features sit behind interfaces; don't bypass them.
5. **Tests are the guard rails.** Behaviour changes update fixtures deliberately, in the same change.
6. **Mobile-native.** Touch phones in either orientation are the primary target; desktop is a bonus.
7. **Small, finished steps.** Every change compiles, passes tests, and leaves the repo shippable.

## Hard rules (summary — full text and rationale in `.agents/rules.md`)

- MUST NOT import `package:flutter` or `package:flame` inside `packages/onslaught_core`.
- MUST NOT hard-code balance values in Dart; put them in data and read them through `GameData`.
- MUST NOT edit, delete or build anything under `.legacy/`; it is read-only reference material.
- MUST NOT change a regression fixture without a matching rule change described in the same PR.
- MUST NOT add a dependency without recording why in `.agents/architecture.md`.
- MUST run `fvm flutter analyze` and `fvm flutter test` (and the core package tests) before declaring a task done.
- MUST keep `docs/`, `.agents/` and the data schema in sync with code changes they describe.
- MUST ask before destructive or irreversible actions (deleting files, rewriting history, force pushes).
- MUST translate every new or changed user-facing string into all supported languages
  (`l10n/<code>.json`) in the same change; the `add-language` checker passes for each (R25).
- MUST NOT change these standards (`AGENTS.md`, `.agents/`, skills, the plan, the deviations log)
  without the project owner's explicit decision; propose the change, then wait (R24).

## How to work here

- Use the fvm-pinned Flutter: `fvm flutter …`, `fvm dart …` (never a global Flutter).
- Plan before editing for anything beyond a one-file change; name the files you will touch.
- Prefer extending a registry/data file over adding a branch to an existing system.
- When the original behaviour is ambiguous, cite the legacy file and line you based the
  decision on, and record deliberate deviations in `docs/DEVIATIONS.md`.
- Keep commit messages conventional (`feat:`, `fix:`, `test:`, `data:`, `docs:`, `chore:`),
  one logical change per commit, no attribution lines required by this project.
- Report outcomes faithfully: say what you verified, what you did not, and what failed.
