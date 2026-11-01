# .agents/skills/

Reusable, agent-agnostic procedures ("skills"). Each skill is a folder with a `SKILL.md`
that has YAML frontmatter (`name`, `description`) followed by step-by-step instructions
and verified commands. Agents load a skill when the task matches its description.

| Skill | Use it when |
|---|---|
| `phase-task/` | Starting any coding task: scope it against the plan, list files/tests, close with the definition of done |
| `flutter-run-and-hot-reload/` | Running the app on any target from an agent shell, hot reload/restart by signal, logs, DevTools |
| `android-emulator-qa/` | Boot, drive, screenshot, record or test the app on the Android virtual device on this machine |
| `ios-simulator-qa/` | The same on an iOS Simulator (xcrun simctl) |
| `qa-report/` | Writing up any QA finding, bug repro or verification in the standard format |
| `legacy-lookup/` | Answering "what did the original do?" from the deobfuscated source, with citations |
| `ffdec-asset-export/` | Exporting art/audio/scripts from the SWF at every atlas density, vector redraws of bitmap-only sprites (the Enhanced pack's creeps), and mapping them to logical asset ids |
| `data-change/` | Changing a balance value or adding data content end to end |
| `regression-fixtures/` | Recording, diffing and deliberately updating the faithful-mode golden-state fixtures |
| `add-language/` | Adding a new interface language, or updating translations after English text changed |
| `golden-tests/` | Writing and updating screenshot tests for widgets, screens and roads |
| `balance-bot/` | Running the headless balance bots and producing before/after tables |
| `release-build/` | Cutting versioned release builds for every platform with the release checklist |

Conventions:
- Commands must be copy-paste runnable on this machine; verify them before committing.
- State machine-specific facts (paths, device names) at the top so they are easy to update.
- Keep skills focused; link to `docs/` for background.
- Skills are standards: changing one needs the project owner's decision (rule R24); fixing a
  verified factual error (path, version, command) is allowed and must be reported.
- Mark what has been verified on this machine and when; keep unverified steps labelled.
- `.claude/skills` is a symlink to this folder so Claude Code discovers them; other agents
  read this README via `AGENTS.md`.
