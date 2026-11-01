---
name: flutter-run-and-hot-reload
description: Run the Flutter app on any target (macOS, iOS Simulator, Android emulator, web) from an agent shell without blocking, hot reload / hot restart it, read its logs and attach DevTools. Use whenever a change needs to be seen running rather than only unit-tested.
---

# flutter run, hot reload and logs (agent-safe)

Agent shells time out after ~2 minutes and cannot hold an interactive `flutter run`
session, so the standard is: **run in the background with a pid file and a log file, drive
it with signals, read the log**.

## Targets on this machine (verified 2026-10-18)

| Target | `-d` value | Notes |
|---|---|---|
| macOS desktop | `macos` | fastest loop; use for most UI work |
| Android emulator | `emulator-5554` | boot first (`android-emulator-qa`) |
| iOS simulator | `"iPhone 17 Pro"` | boot first (`ios-simulator-qa`) |
| Web | `web-server` | **Chrome is not installed**, so `-d chrome` is unavailable; `web-server` serves on a port you open in any browser (the agent's built-in browser works) |
| Devices list | `fvm flutter devices` | slow (can exceed a minute); prefer `adb devices` / `xcrun simctl list devices booted` |

## 1. Start

```bash
cd <repo root>
T=macos                                    # or emulator-5554, "iPhone 17 Pro", web-server
rm -f /tmp/flutter-$T.pid
nohup fvm flutter run -d "$T" --pid-file /tmp/flutter-$T.pid > /tmp/flutter-$T.log 2>&1 &
```
Add `--profile` for performance work, `--dart-define=KEY=VALUE` for flags (e.g.
`DEBUG_OVERLAY=true`, `SEED=42`, `ENHANCED_SKIN=true` for the Enhanced skin), `--web-port 8080`
for web-server. Shader changes (`shaders/*.frag`) and `pubspec.yaml` changes need a full rerun.

Wait for the app: poll the log until it contains `A Dart VM Service on` (debug) or
`Flutter run key commands` and the pid file exists:
```bash
until grep -q "Dart VM Service\|Flutter run key commands" /tmp/flutter-$T.log; do sleep 3; done; tail -5 /tmp/flutter-$T.log
```

## 2. Hot reload / restart / quit (verified on macOS 2026-10-18: `Reloaded 0 libraries in 114ms`, `Restarted application in 229ms`)

```bash
kill -USR1 "$(cat /tmp/flutter-$T.pid)"    # hot reload  (state kept)
kill -USR2 "$(cat /tmp/flutter-$T.pid)"    # hot restart (state reset)
kill -TERM "$(cat /tmp/flutter-$T.pid)"    # quit; app is closed and the tool exits
```
After a reload, `grep -n "Reloaded\|Restarted\|Error\|Exception" /tmp/flutter-$T.log | tail`.
Hot reload cannot apply changes to `main()`, global initialisers, enum/field shape changes
or `const` trees; use hot restart for those. Asset and data JSON changes need a restart
(and `pubspec.yaml` asset list changes need a full rerun).

## 3. Logs and DevTools

```bash
tail -50 /tmp/flutter-$T.log                              # Dart prints, framework exceptions, reload results
grep -o "http://127.0.0.1:[0-9]*/[A-Za-z0-9_=-]*/" /tmp/flutter-$T.log | tail -1   # VM service URL
fvm dart devtools --no-launch-browser                      # DevTools server; open it with the VM service URL (background it)
```
Android extra: `adb logcat -s flutter`. iOS extra: `xcrun simctl spawn "iPhone 17 Pro" log stream --predicate 'process == "Runner"'`.
macOS: the app's own stdout is in the run log already.

## 4. Seeing the result

- macOS/iOS: screenshot with the platform skill (`screencapture -l <windowid>` for the
  macOS window: `osascript -e 'tell app "System Events" to get id of window 1 of process "onslaught3_remastered"'` is unreliable; prefer `screencapture -x /tmp/qa/mac.png` of the full screen, or test the same screen on a simulator).
- Android: `adb exec-out screencap -p > /tmp/qa/shot.png`.
- Web: open `http://localhost:<port>` in the built-in browser and screenshot there.
Always view the screenshot before claiming a visual result.

## 5. Standards

- One running instance per target; stop the old one before starting a new one.
- Never leave a `flutter run` without a log file; never claim a reload worked without reading the log.
- Clean up pid/log files you created when the task ends unless the user wants the app left running.
- For anything a human would "click through", prefer an integration test to a manual run.
