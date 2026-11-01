# .agents/

Context that is preloaded for any AI agent working on this repository. The entry point is
the root `AGENTS.md`; it tells agents to read these files in order:

| File | Purpose |
|---|---|
| `project-overview.md` | What the project is, current status, toolchain, repo map |
| `tenets.md` | Principles every decision is measured against |
| `rules.md` | Hard MUST / MUST NOT rules with rationale |
| `architecture.md` | Layers, packages, data flow, extension seams, dependency log |
| `workflow.md` | Commands, definition of done, how-to recipes, fixture policy |
| `legacy-source.md` | How to read the original Flash game's source and assets |
| `glossary.md` | Domain vocabulary |
| `skills/` | Reusable procedures (`<skill>/SKILL.md`), e.g. Android emulator QA |

Keep these files short and current. When a rule or structure changes in code, change it
here in the same commit. Long-form design lives in `docs/`.
