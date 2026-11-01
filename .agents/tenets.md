# Tenets

Ordered. When two conflict, the earlier one wins.

## 1. Faithful first
v1 behaves exactly like the original: same numbers, same targeting, same combo recipes,
same maps, same quirks unless listed in `docs/DEVIATIONS.md`. The source of truth is the
legacy ActionScript in `.legacy/deobfuscated/` and the tables in
`docs/ONSLAUGHT2_GAME_REFERENCE.md`, not anyone's memory of the game. If the reference
and the code disagree, read the legacy source and fix whichever is wrong.

## 2. Data over code
Every balance value, recipe, map, wave curve, unlock threshold, string and asset id lives
in `assets/data/*.json` with a typed, validated schema. Dart code expresses behaviour; it
never embeds a number a designer might want to change. The original's "mod" system is
the normal way the game is configured, not a feature bolted on.

## 3. Pure core
`packages/onslaught_core` is plain Dart: no Flutter, no Flame, no platform APIs, no file
paths, no wall-clock time. It takes `GameData` + a seed + `GameCommand`s and produces
state + `GameEvent`s, deterministically. Everything about the game that matters can be
tested headless in milliseconds.

## 4. Swappable edges
UI (`GameViewModel` + `UiSkin`), art and audio (`AssetPack` chain, including procedural
packs), content (`ContentPack`), mechanics (`RulesRegistry` behaviours) and rule sets
(`RulesProfile`) are interfaces with a classic implementation. New work plugs in beside
the classic one; it does not fork or special-case it.

## 5. Tests are the guard rails
The faithful-mode regression fixtures freeze v1. Rule tests, data-contract tests,
balance bots, goldens, architecture tests and migrations catch regressions before a
human does. A change without its tests is not done; a fixture change without a stated
reason is a bug.

## 6. Mobile-native
Phones with touch, in portrait or landscape, are the primary device; the game adapts
when the player turns the device. Every interaction must work with a
finger (44 pt targets, no hover, no keyboard-only paths), with pinch-zoom and pan over a
map wider than the original. Desktop and web get the same UI plus shortcuts.

## 7. Small, finished steps
Prefer a small change that compiles, passes tests and leaves `main` shippable over a
large one that does not. Finish the whole task you took on; if part is blocked, say so
explicitly rather than quietly narrowing scope.

## 8. Explain the why
Decisions that are not obvious from the code go in `docs/`, `.agents/` or
`docs/DEVIATIONS.md` with the reason, in the same commit as the change.
