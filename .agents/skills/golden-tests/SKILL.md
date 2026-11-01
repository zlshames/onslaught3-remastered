---
name: golden-tests
description: How to write, run, update and review golden (screenshot) tests for HUD widgets, screens and road rendering with alchemist, across phone/tablet/desktop sizes, light/dark and large text, without flakiness. Use for any UI change or new widget.
---

# Golden tests

Goldens are the visual regression suite for the Flutter layer. They run on the host
(`fvm flutter test`), never on a device, and must be deterministic across macOS and Linux CI.

## Layout and naming

```
test/goldens/<feature>/<widget>_golden_test.dart
test/goldens/<feature>/goldens/ci/<fileName>.png       # alchemist CI variant: committed (text drawn as blocks)
test/goldens/<feature>/goldens/macos/<fileName>.png    # alchemist platform variant: committed (real fonts, recorded on macOS)
test/goldens/game/goldens/road_<mapId>.png             # flame_test road goldens: committed
```
Alchemist writes one image per `goldenTest`, with every scenario (device × theme × text scale)
laid out in a grid, so name scenarios `<device> <state>`.
Device set (from `test/goldens/devices.dart`, logical px): landscape `phone` (iPhone 17 Pro,
874×402), `phoneSmall` (the Pixel 10 AVD, 923×411), `tablet` (iPad Pro 11", 1210×834),
`desktop` (1280×720) — `GoldenDevices.all`, what every existing golden uses; more landscape
sizes `phoneSE` (667×375), `ipad10` (1180×820), `laptop` (1440×900) in `landscapeExtra`; and
portrait `phonePortrait` (402×874), `phoneSmallPortrait` (375×667), `tabletPortrait`
(834×1210) in `portrait`. New UI gets portrait scenarios too. A screen picks its layout from
its own constraints (`LayoutBuilder`), not `MediaQuery.sizeOf`: a golden's MediaQuery is the
whole golden surface, not the scenario.
Themes: light and dark. Text scale: 1.0 and 1.3 for HUD panels.

## Writing one

```dart
goldenTest(
  'selected tower sheet',
  fileName: 'selected_tower_sheet',
  builder: () => GoldenTestGroup(children: [
    for (final s in SelectedTowerStates.all)      // no selection, blue lvl0, blue maxed, fusion, targeter, modifier
      GoldenTestScenario(name: s.name, child: TowerSheet(viewModel: FakeGameViewModel(s))),
  ]),
);
```
- Always render from `FakeGameViewModel` / fixed data; never from a live simulation.
- Fonts: the committed CI variant draws text as blocks, so it does not depend on fonts. When the
  project ships its own fonts, load them in `test/flutter_test_config.dart` for the platform variant.
- Freeze time and animations: `tester.pumpAndSettle()` with `Duration.zero` animations via the test theme, or pump a fixed frame; disable shimmer/blink effects under `TestEnvironment.isGolden`.
- Images/sprites: use the classic asset pack's test subset bundled in `test/assets`, so a pack change is visible but not required for every golden.
- Road goldens: one per built-in map at the 720×480 play-area size (1 world px per pixel), rendering
  `RoadComponent` through `flame_test`'s `testGolden`.

## Commands

```bash
fvm flutter test test/goldens                              # compare
fvm flutter test test/goldens --update-goldens             # regenerate — only for an intended visual change
fvm flutter test test/goldens/game/tower_sheet_test.dart   # one file
```
Goldens are recorded on macOS and CI runs them on macOS (the `app` job in
`.github/workflows/ci.yml`) so antialiasing matches. `CI=true` skips the platform variant, as CI
does. If CI differs from a local run, find the cause (fonts, time, randomness); never raise the
tolerance.

## Reviewing a golden change

- Open before/after PNGs side by side (`test/goldens/**/failures/*_masterImage.png`, `*_testImage.png`, `*_isolatedDiff.png`) and describe the pixel change in the PR.
- A golden diff with no intended visual change is a bug or flakiness; do not update.
- New widget ⇒ new golden in all device/theme combinations it supports; a widget that only appears on phones still gets the tablet size to prove it degrades sanely.
- Tolerance stays at 0 (exact). Flaky elements are fixed at the source (fonts, time, randomness, platform-specific scrollbars via `ScrollConfiguration`).

## Standards

- Every HUD widget and screen has a golden before it is wired to the live view model.
- Goldens are committed PNGs; keep them small (crop to the widget, avoid full-screen when a panel is enough).
- Updating goldens is a `test:` change that names the visual intent in the message.
