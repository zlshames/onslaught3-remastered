# docs/

What each document is and whether it is current. Agents read the ones `AGENTS.md` lists;
the rest are background.

| Document | Status | What it is |
|---|---|---|
| `REMASTER_PLAN.md` | current (standards, R24) | architecture, mobile UI design, phased build order, testing strategy |
| `ENHANCED_PLAN.md` | current (standards, R24) | the Enhanced mode plan (phases E0+), beside Classic |
| `ONSLAUGHT2_GAME_REFERENCE.md` | current (the spec) | the original game's rules and every balance number, with corrections |
| `DEVIATIONS.md` | current (standards, R24) | every deliberate departure from the original and its `RulesProfile` toggle |
| `legacy/` | current (reference) | the original's values extracted once (`legacy_values.json`, `LEGACY_VALUES.md`) and engine notes |
| `RELEASING.md` | current (2026-10-31) | how a release is cut on GitHub: one-time setup, tagging, what each download is |
| `LOGGING.md` | current (2026-10-21) | the local log: levels, masking of personal data, rotation, export, failure handling |
| `REPLAY_PLAN.md` | resume in part (2026-10-21); replays not started | replays and resume; its status line says what is built |
| `screenshots/` | current (2026-10-31) | full-resolution game screenshots for the README, from the Android emulator |
| `history/PORTRAIT_PLAN.md` | implemented 2026-10-19 | the portrait-mode build plan; the shipped design is in `REMASTER_PLAN.md` |
| `history/SCREEN_FIT_PLAN.md` | implemented 2026-10-19 | the screen-fit design that `PORTRAIT_PLAN.md` carried out; superseded sections are marked inside |

A finished plan moves to `history/` (owner decision 2026-10-20); code comments may still cite
it by section, which is why the files keep their names.
