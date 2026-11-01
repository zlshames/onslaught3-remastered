---
name: ios-simulator-qa
description: Boot, drive, screenshot, record and test the Onslaught 3 Remastered Flutter app on an iOS Simulator on this Mac using xcrun simctl. Use for manual QA, visual checks of the portrait and landscape UI (including turning mid-game), reproducing bugs and running integration tests on iOS.
---

# iOS Simulator QA

Agent-agnostic: everything here uses `xcrun simctl` and `fvm flutter`. (Claude Code also has
a built-in simulator tool; it is fine to use it for viewing, but keep the commands below as
the standard so any agent can do the same.)

## Facts about this machine (verified 2026-10-18)

| Item | Value |
|---|---|
| Xcode | 27.1 at `/Applications/Xcode.app` (`xcode-select -p` is correct) |
| Runtime | iOS 26.5 only |
| Phones | iPhone 17 Pro **(default QA device)**, iPhone 17 Pro Max, iPhone 17, iPhone 17e, iPhone Air |
| Tablets | iPad Pro 13"/11" (M5), iPad Air 13"/11" (M4), iPad mini (A17 Pro), iPad (A16) |
| App bundle id | `com.zlshames.onslaught3-remastered` (iOS and macOS; from `ios/Runner.xcodeproj/project.pbxproj` and `macos/Runner/Configs/AppInfo.xcconfig`) |
| Built app | `build/ios/iphonesimulator/Runner.app` after `fvm flutter build ios --simulator --debug` |

Use the device **name** in commands (`"iPhone 17 Pro"`) or its UDID from
`xcrun simctl list devices available`. Prefer one phone (17 Pro) and one tablet (iPad Pro 11")
for layout checks.

```bash
DEV="iPhone 17 Pro"
BUNDLE=com.zlshames.onslaught3-remastered
```

Verified on 2026-10-18 against iPhone 17 Pro: boot, install, launch, screenshot, appearance,
recordVideo. Input injection and rotation really are unavailable from `simctl`.

## 1. Lifecycle

```bash
xcrun simctl list devices available                 # names, UDIDs, state
xcrun simctl boot "$DEV"                            # no-op if already booted
xcrun simctl bootstatus "$DEV" -b                   # block until booted
open -a Simulator                                   # show the window (optional; headless works without it)
xcrun simctl shutdown "$DEV"
xcrun simctl erase "$DEV"                           # factory reset (device must be shut down)
```

## 2. Build, install, launch

```bash
fvm flutter build ios --simulator --debug           # background; several minutes the first time
xcrun simctl install "$DEV" build/ios/iphonesimulator/Runner.app
xcrun simctl launch "$DEV" $BUNDLE                  # prints the pid
xcrun simctl terminate "$DEV" $BUNDLE
xcrun simctl uninstall "$DEV" $BUNDLE
xcrun simctl launch --console "$DEV" $BUNDLE        # attach stdout/stderr (Dart prints) to this shell
```

Or with hot reload (see the `flutter-run-and-hot-reload` skill):
`nohup fvm flutter run -d "$DEV" --pid-file /tmp/flutter-ios.pid > /tmp/flutter-ios.log 2>&1 &`

## 3. Orientation and appearance

The app follows the device (portrait and both landscapes on iPhone, all four on iPad); test
both, and turn the device mid-wave with a turret selected and during a tray drag. Appearance
and text size (verify with a screenshot):

```bash
xcrun simctl ui "$DEV" appearance dark              # or light
xcrun simctl ui "$DEV" content_size extra-large     # Dynamic Type for large-text goldens (accessibility sizes: accessibility-medium … accessibility-extra-extra-extra-large)
xcrun simctl ui "$DEV" increase_contrast enabled
```
There is no `simctl` rotate; rotation comes from the Simulator menu (Device → Rotate,
⌘←/⌘→) or an integration test (a headless simulator, e.g. one streamed to an agent panel,
cannot be rotated: cover rotation with the game-screen widget tests that resize the view).

## 4. Observe

```bash
xcrun simctl io "$DEV" screenshot /tmp/qa/ios-01.png            # PNG at device pixel size (then view it)
xcrun simctl io "$DEV" recordVideo --codec h264 /tmp/qa/ios.mp4 &   # background; stop with: pkill -INT -f 'simctl io.*recordVideo'
xcrun simctl spawn "$DEV" log stream --predicate 'process == "Runner"' --style compact   # device log (background it)
xcrun simctl diagnose "$DEV"                                    # full diagnostics bundle (slow; only for hard crashes)
```

Screenshots are physical pixels: iPhone 17 Pro gives 1206×2622 portrait (2622×1206 landscape),
3× scale, so **Flutter logical px = physical ÷ 3** (logical 402×874). iPads are 2×.

## 5. Input

`simctl` has **no tap/swipe/text injection**. Options, in order of preference:
1. **Integration tests** (`fvm flutter test integration_test -d "$DEV"`) for any scripted
   interaction, including pinch and multi-touch.
2. The agent's built-in simulator tool when one exists (Claude Code: tap/swipe/text/touch paths).
3. Deep links: `xcrun simctl openurl "$DEV" "onslaught://debug/..."` once the app registers a
   debug URL scheme (Phase 0 adds `onslaught://` for test hooks).
4. Manual: the Simulator window.

Keyboard: the simulator forwards the Mac keyboard when its window is focused, so desktop
shortcuts can be tested there by hand, not by script.

## 6. Tests on the simulator

```bash
fvm flutter test integration_test -d "$DEV"
fvm flutter test integration_test/smoke_test.dart -d "$DEV" --dart-define=SEED=42
fvm flutter drive --driver=test_driver/integration_test.dart --target=integration_test/smoke_test.dart -d "$DEV"
```

## 7. QA session recipe

1. Boot (§1), build + install + launch (§2).
2. Screenshot each screen to `/tmp/qa/ios-NN-description.png`; view and describe each.
3. For interactions, write or run an integration test rather than guessing; use `log stream`
   in the background for exceptions.
4. Repeat on iPad Pro 11" for the tablet layout; repeat with `content_size extra-large`.
5. Report with the `qa-report` skill. Leave the simulator booted unless told otherwise.

## 8. Gotchas

- First `build ios` and first `flutter run` on a fresh simulator are slow (minutes); background them.
- `simctl install` needs a *simulator* build (`--simulator`), not a device build.
- `erase` fails while booted; shut down first.
- Two simulators can be booted at once; always pass the device name to avoid ambiguity.
- The bundle id differs from the Android application id (Android cannot contain hyphens: `com.zlshames.onslaught3remastered`).
