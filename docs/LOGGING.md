# Logging

The app keeps a local log for bug reports. It is never sent anywhere by the app (rule R22): the
player exports it from Settings → Diagnostics and chooses where it goes. Code lives in
`lib/services/logging/`; tests in `test/services/logging/` and `test/app/diagnostics_settings_test.dart`.

## Writing to the log

```dart
import '../services/logging/logging.dart';

const Logger _log = Logger('persistence');   // one per file, named after the area

_log.info('map saved', fields: {'map': map.id, 'mapName': Pii(map.name)});
_log.warning('a stored map cannot be read', error: e, stackTrace: st);
_log.debug(() => 'expensive ${describe(state)}');   // built only when the level keeps it
```

| Level | Use for |
|---|---|
| `trace` | step-by-step detail |
| `debug` | what was loaded or chosen; screen changes, app lifecycle |
| `info` | what the player did or the app decided: game started/over, mod on, map saved |
| `warning` | something failed and the app carried on (no sound, a document reset) |
| `error` | a failure the player may notice (a save failed, resume failed) |
| `fatal` | the app cannot carry on as it was (uncaught errors, game data cannot load) |

Areas in use: `app`, `navigation`, `data`, `persistence`, `maps`, `mods`, `editor`, `game`,
`progress`, `assets`, `audio`, `haptics`, `render`, `settings`, `log`.

## What is logged

| Area | `info` | `debug` | `trace` |
|---|---|---|---|
| `app`, `navigation` | app started | lifecycle changes, screen paths | |
| `data` | mod on | game data load time | |
| `persistence`, `maps` | map saved / deleted | map code made | map code not readable |
| `mods` | mod switched, reset, imported | value changed or refused, renamed, mod code made | mod code not readable |
| `editor` | editor opened, map imported | save refused (problems), saved, play, clear, leave, map actions | |
| `game` | game started / resumed, over, won, freeplay, weapon unlocked, objectives | turret built, upgraded, sold, moved, target mode, joins, combos, freakouts, pause, speed, wave settings, wave started, base hit, command refused, game closed | tutorial cash |
| `progress` | each unlock and completion, challenge result and custom game result (with `newBest`) | | |
| `assets`, `audio`, `render` | | asset pack loaded (sprites, sounds, time) | atlas page loaded, sound loaded |

Failures are `warning` (the app carried on: a sound, a sprite image or a sharper atlas page could
not load, a vibration failed, a stored map or mod reset) or `error` (an asset pack or a needed
atlas page could not load, a save or resume failed). In-game lines carry the game step
(`tick`). Shots, kills, spawns and blasts come many times a second and are not logged
(`lib/features/game/game_event_log.dart`).

Do not log in the simulation's per-step path, and keep `packages/onslaught_core` free of the
logger (it has no Flutter imports, rule R1). The core reports through `GameEvent`s and
exceptions; the app logs those.

## Guarantees

**Never blocks.** `Logger` methods check the level, build a record and queue it; that is all
the caller pays for. Formatting, masking and writing happen in batches (at most 500 records)
on a 500 ms timer, or at once (a microtask) for errors. File I/O is asynchronous; the export's
zip is built in another isolate (`compute`).

**Never fails the caller.** Nothing a log call does throws:

- a message, field or error whose `toString` throws is written as a placeholder;
- a sink that throws or takes longer than 10 s is contained; after 3 failures in a row it rests
  (30 s, doubling to 10 min) and then writes how many records it missed;
- the queue holds at most 5000 records; when the sinks cannot keep up the oldest are dropped and
  the next batch says how many;
- the logger's own problems go to the debug console in debug builds only, never back into the
  log (so a failing log cannot loop).

**Repeats are folded.** A record identical to the one before it (level, area, message, error
type, fields) is counted, not queued: one `the previous message repeated N more times` per batch.

## Personal data

Nothing personal reaches a log file in the clear. Every message, field value, error text and
stack line goes through `PiiRedactor` before any sink sees it:

| Found | Written as |
|---|---|
| `password=…`, `token: …`, `api_key …`, `Authorization: Bearer …` | the value replaced by `********` |
| e-mail address | `j******e@e*****e.com` (top-level domain kept) |
| URL query value | `?user=j***` |
| user name in a home path (`/Users/…`, `/home/…`, `C:\Users\…`) | `/Users/z*********s/…` |
| install id in a path (iOS containers, simulators) | masked |
| IPv4 / IPv6 / MAC address | first part kept (`192.***.*.**`) |
| card number (13–19 digits, Luhn-valid) | last four digits kept |
| phone number (international or grouped) | last two digits kept |

Masking keeps the first and last characters and the length (`Fortress` → `F******s`), so two
lines about the same thing can still be matched. A `FormatException` is written without its
source text (the document being read).

The patterns cannot recognise free text the player typed. Mark it at the call:

- wrap the value in `Pii(...)`, or
- give it a field name with a personal word in it (`name`, `user`, `email`, `phone`, `address`,
  `ip`, `account`, `device`, …): `mapName`, `playerName` are masked automatically; a secret word
  (`password`, `token`, `secret`, `auth`, `cookie`, `apiKey`) hides the value entirely.

## Files and rotation

| | Disk (Android, iOS, macOS, Windows, Linux) | Web |
|---|---|---|
| Where | `<application support>/logs/` | memory (lost on reload) |
| File size | 1 MiB | 256 KiB |
| Files kept | 5 (`app.log`, `app.1.log` … `app.4.log`) | 3 |
| Age limit | 14 days, applied at start-up | — |

A write that would take `app.log` past the size limit first shifts the files along
(`RotatingLogWriter`). Each run starts with an `app started` record: app version and build,
platform, OS version (masked), Dart version, build mode, a random session id and the level.

## Settings → Diagnostics

- **Log detail**: Errors only, Warnings and errors, Normal (`info`), Detailed (`debug`),
  Everything (`trace`). Stored as `Settings.logLevelChoice` (settings v7); unset means the
  build's default, `debug` in debug builds and `info` otherwise.
- **Export logs**: writes what is queued, zips the log files with an `info.json` (app,
  platform, session, level, export time, file list) as `onslaught3-remastered-logs-<UTC time>.zip`, and
  opens the share sheet (a download on the web; on Linux, where the share sheet cannot take
  files, the zip is saved to Downloads and the path shown).
- **Clear logs**: after a confirmation, deletes the log files; logging carries on in a new one.

## What is captured automatically

- Framework errors (`FlutterError.onError`, level `error`) and uncaught asynchronous errors
  (`PlatformDispatcher.onError`, level `fatal`), each with its stack trace; handlers set before
  still run.
- An `error` or `fatal` record logged without a stack trace gets the caller's; frames from the
  logger itself are dropped and at most 40 are written.
- Screen changes (`debug`, path only, never the query) and app lifecycle changes (`debug`);
  the log is written out whenever the app is paused, hidden or closed.

## Tests

A widget test that installs a `LogService` with sinks (for example `AppLogging.memory()`)
must close it at the end (`await tester.runAsync(logging.service.close)`), or the 500 ms flush
timer is reported as pending. The default service before `setUpLogging` has no sinks and sets
no timers, so other tests need nothing.
