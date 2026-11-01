---
name: android-emulator-qa
description: Boot, drive, inspect, screenshot, record and test the Onslaught 3 Remastered Flutter app on the Android virtual device (AVD) installed on this Mac. Use for manual QA, reproducing bugs, visual checks of the portrait and landscape UI (including turning mid-game), integration tests and performance captures on Android.
---

# Android emulator QA

## Facts about this machine (verified 2026-10-18)

| Item | Value |
|---|---|
| Android SDK | `~/Library/Android/sdk` (`ANDROID_HOME` is **not** exported by default) |
| `adb` | `~/Library/Android/sdk/platform-tools/adb` (on PATH), v37 |
| `emulator` | `~/Library/Android/sdk/emulator/emulator` (**not** on PATH), v36.6 |
| `avdmanager`, `sdkmanager`, `screenshot2` | `~/Library/Android/sdk/cmdline-tools/latest/bin/` (not on PATH) |
| AVD | **`Pixel_10_Custom_RAM`** — Pixel 10, Android 16 (API 36.1), `google_apis` arm64-v8a, no Play Store, 1080×2424 @ 420 dpi, 2 GB RAM (emulator raises to 4 GB), hardware keyboard on, **cold boot forced** (`fastboot.forceColdBoot=yes`, so every boot takes ~60–120 s) |
| Device serial once booted | `emulator-5554` |
| App id | `com.zlshames.onslaught3remastered`, activity `.MainActivity` (Android forbids hyphens, so this is the Android form of the iOS/macOS id `com.zlshames.onslaught3-remastered`) |
| Flutter | always `fvm flutter …` from the repo root |

Start every shell with (same as `scripts/env.sh`):

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
APP=com.zlshames.onslaught3remastered
```

Bundled helpers: `scripts/env.sh` (exports above), `scripts/wait_boot.sh` (block until
booted), `scripts/ui_dump.py [label] [--tap]` (list labelled UI nodes with centres, or tap
the first match). All commands in this file were run against the real AVD on 2026-10-18
(the hot-reload signals were verified on the macOS target).

Long-running commands (emulator, `flutter run`, builds) must run in the background with
output redirected to a log file; the agent shell times out at 2 minutes.

## 1. Lifecycle

```bash
emulator -list-avds                                   # expect: Pixel_10_Custom_RAM
nohup emulator -avd Pixel_10_Custom_RAM -netdelay none -netspeed full \
  > /tmp/emulator.log 2>&1 &                          # add -no-window for headless/CI
adb wait-for-device
adb shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done; echo BOOTED'   # or scripts/wait_boot.sh
adb devices -l                                        # emulator-5554 device
adb emu kill                                          # shut down cleanly
emulator -avd Pixel_10_Custom_RAM -wipe-data          # factory reset the AVD
```

If `adb devices` shows `offline` or nothing after boot: `adb kill-server && adb start-server`.
If two devices are attached, add `-s emulator-5554` to every `adb` call.

## 2. Build, install, launch

```bash
fvm flutter build apk --debug                         # background; ~2 min, debug APK is ~150 MB
adb install -r build/app/outputs/flutter-apk/app-debug.apk   # prints "Success"
adb shell am start -n $APP/.MainActivity
adb shell am force-stop $APP                          # kill
adb uninstall $APP                                    # remove
adb shell pm clear $APP                               # wipe app data (persisted profile/settings)
```

Or run with hot reload (background, logged). Hot reload/restart by signal:

```bash
nohup fvm flutter run -d emulator-5554 --pid-file /tmp/flutter.pid > /tmp/flutter-run.log 2>&1 &
kill -USR1 "$(cat /tmp/flutter.pid)"                  # hot reload   (verified on macOS; same tool behaviour on Android)
kill -USR2 "$(cat /tmp/flutter.pid)"                  # hot restart
tail -50 /tmp/flutter-run.log                         # VM service URL, exceptions, prints
```

Profile builds for performance work: `fvm flutter run --profile -d emulator-5554`.

## 3. Orientation (the game follows the device: portrait and both landscapes)

```bash
adb shell settings put system accelerometer_rotation 0      # disable auto-rotate
adb shell settings put system user_rotation 1               # 0 portrait, 1 landscape (90°), 2 upside-down, 3 landscape (270°)
adb shell wm size                                           # Physical size: 1080x2424
adb shell dumpsys window displays | grep -o 'rotation=[0-9]' | head -1   # rotation=1 when landscape is in effect
```

The stock launcher is **portrait-locked**, so the home screen (and screenshots of it) stay
1080×2424 whatever you set. Rotation takes effect as soon as an app that allows it is in
front: launching our app with `user_rotation 1` gives `rotation=1` and 2424×1080
screenshots (verified). The app allows portrait and both landscapes
(`screenOrientation="fullUser"`), so set `user_rotation` 0 for portrait. To test turning
mid-game, change `user_rotation` while a wave runs (with a turret selected, and during a tray
drag): the HUD moves (portrait: stats on top, tray strip along the bottom, the map upright and
filling the screen), the selection stays, a drag in progress is cancelled.
`adb emu rotate` (sensor rotation) only matters when `accelerometer_rotation` is 1.

## 4. Coordinates

- Physical pixels: 1080 wide × 2424 tall in portrait; 2424 × 1080 in landscape.
- Density 420 dpi ⇒ **Flutter logical px = physical px ÷ 2.625** (and dp = the same).
- Our world/camera maps the 720×480 play area into the viewport; to tap a world point,
  read the current camera transform from the debug overlay (Phase 0 adds a
  `--dart-define=DEBUG_OVERLAY=true` HUD that prints zoom/offset) or use an integration test.
- Find UI elements by text/semantics rather than guessing pixels (see §6).

## 5. Input

```bash
adb shell input tap X Y                                     # tap
adb shell input swipe X1 Y1 X2 Y2 300                       # drag/pan over 300 ms (drag-to-build, pan map)
adb shell input swipe X Y X Y 800                           # long-press (same point, 800 ms)
adb shell input text 'MapName'                              # type into focused field (use %s for space)
adb shell input keyevent KEYCODE_BACK                       # also HOME, APP_SWITCH, ENTER, TAB, DPAD_*, VOLUME_UP
adb shell input keyevent KEYCODE_WAKEUP                     # wake a sleeping screen (KEYCODE_MENU opens the launcher's long-press menu, so avoid 82 on the home screen)
adb shell input roll 0 -5                                   # scroll wheel-ish (rarely useful)
```

Limits: `input` has no multi-touch, so **pinch-zoom cannot be driven from adb**. Verify
pinch with an integration test (`WidgetTester` two-pointer gestures) or the debug overlay's
zoom buttons; use `swipe` for one-finger pan. Keyboard shortcuts from the desktop layout
also work because the AVD has `hw.keyboard=yes`: `adb shell input keyevent KEYCODE_SPACE`.

Faster scripted sequences: write them to a file and run `adb shell < script.sh`, or use
the emulator console (`adb emu …`: `rotate`, `geo fix`, `sms send`, `power capacity 15`).

## 6. Observe

```bash
adb exec-out screencap -p > /tmp/shot.png               # screenshot (then view it with the agent's image reader)
adb shell screenrecord --time-limit 15 --bit-rate 6000000 /sdcard/rec.mp4 && adb pull /sdcard/rec.mp4 /tmp/
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml /tmp/ && grep -o 'text="[^"]*"\|content-desc="[^"]*"' /tmp/ui.xml
adb logcat -c; adb logcat -s flutter                     # Dart prints/exceptions only (Ctrl-C or run in background)
adb logcat '*:E' -d | tail -100                          # errors so far
adb shell dumpsys gfxinfo $APP reset >/dev/null; sleep 10; adb shell dumpsys gfxinfo $APP | grep -E 'Total frames|Janky|90th|99th'   # frame timing over a window
adb shell dumpsys meminfo $APP | head -30
adb shell getprop ro.build.version.release               # Android version
```

`uiautomator dump` lists Flutter widgets **out of the box** (verified on a debug build:
`content-desc="Increment"` etc. appear without extra setup) because Flutter answers the
accessibility query. Every control in this app must carry a semantics label (rule in
`AGENTS.md`), so prefer `scripts/ui_dump.py <label> --tap` over pixel guesses. Screenshots
are the ground truth for visual checks; attach them to the report. Get the Dart VM service
URL for DevTools with `adb logcat -d -s flutter | grep 'VM service'` and expose it with
`adb forward tcp:PORT tcp:PORT`.

## 7. Tests on the device

```bash
fvm flutter test integration_test -d emulator-5554                 # integration_test package, runs on device
fvm flutter test integration_test/smoke_test.dart -d emulator-5554 --dart-define=SEED=42
fvm flutter drive --driver=test_driver/integration_test.dart --target=integration_test/smoke_test.dart -d emulator-5554   # with host-side driver (screenshots via driver)
fvm flutter test                                                    # host-only: unit, widget, goldens (never on the emulator)
```

Integration tests are the right tool for anything that needs pinch, precise world
coordinates, deterministic seeds, or assertions on sim state; adb is for exploratory QA.

## 8. QA session recipe

1. Boot the AVD (§1), wait for `BOOTED`, set the orientation to test (§3); check both.
2. Build + install or `flutter run` (§2); clear app data first if testing first-run flows.
3. Clear logcat, start the flow, screenshot each screen (`/tmp/qa/NN-description.png`).
4. Drive with `tap`/`swipe`/`text` (§5); after each step take a screenshot and read it.
5. Capture `logcat -s flutter` and `gfxinfo` at the end; note any exception or dropped frames.
6. Report: steps, expected vs actual, screenshots, logcat excerpts, device facts; file the
   repro as an integration test when it is a bug.
7. Leave the emulator running if more work follows; otherwise `adb emu kill`.

## 9. Gotchas

- `emulator` is not on PATH: always export the PATH block above.
- Cold boot is forced in the AVD config, so a boot takes 1–2 minutes; wait for
  `sys.boot_completed`, not just `adb devices`.
- `fvm flutter devices` can take >1 minute while it probes simulators; prefer `adb devices`.
- The first `flutter build apk` downloads Gradle and SDK pieces; run it in the background.
- Screenshots from `screencap` are physical pixels; divide by 2.625 for Flutter coordinates.
- After `pm clear`, the app's persisted profile (unlocks, maps, mods) is gone, by design.
- Don't run two emulator instances; the single AVD is the test target. Don't modify the AVD
  config without asking; it is shared with the human developer.
