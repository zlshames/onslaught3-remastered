---
name: release-build
description: Produce release builds of Onslaught 3 Remastered for Android, iOS, macOS, Windows, Linux and web, bump the version, verify the release checklist and keep signing material out of the repo. Use when cutting a build for testers, a store, or a tagged release.
---

# Release builds

Status: no release has been cut yet; this is the standard the first release must follow.
Signing material (keystores, provisioning profiles, API keys) is **never** committed; it
lives in the developer's keychain / CI secrets and is referenced by environment variables.

## 1. Version

`pubspec.yaml` `version: MAJOR.MINOR.PATCH+BUILD`. Bump `PATCH` for fixes, `MINOR` for
features, `MAJOR` for a new rules profile or save-format break; `BUILD` increases on every
store upload. Tag `vMAJOR.MINOR.PATCH` after the build is verified. `CHANGELOG.md` gets a
section per version listing player-visible changes and any `docs/DEVIATIONS.md` additions.

## 2. Pre-flight (must be green)

```bash
fvm flutter --version                    # matches .fvmrc
fvm dart format --set-exit-if-changed . && fvm flutter analyze
fvm flutter test && (cd packages/onslaught_core && fvm dart test)
(cd packages/onslaught_core && fvm dart test test/balance)   # full bot roster
(cd packages/onslaught_core && fvm dart test --run-skipped -t soak)   # 3× soak to wave 300 (headless)
fvm flutter test integration_test -d emulator-5554 && fvm flutter test integration_test -d "iPhone 17 Pro"
```
Plus: device soak (`fvm flutter test integration_test/soak_test.dart -d emulator-5554`, 3× to
wave 300), goldens at large text (part of `fvm flutter test`), a manual play-through
of the tutorial and one challenge on a phone, licence/credits screen shows the original attribution.

## 3. Build commands

```bash
fvm flutter build appbundle --release --obfuscate --split-debug-info=build/symbols/android   # Play Store (.aab)
fvm flutter build apk --release --split-per-abi                                               # sideload/testers
fvm flutter build ipa --release --obfuscate --split-debug-info=build/symbols/ios --export-options-plist=ios/ExportOptions.plist
fvm flutter build macos --release
fvm flutter build windows --release        # on a Windows runner
fvm flutter build linux --release          # on a Linux runner
fvm flutter build web --release --wasm     # fall back to --no-wasm if a dependency lacks wasm support; serve with correct COOP/COEP headers
```
Keep `build/symbols/*` for every shipped build (crash symbolication).

Android signing: `android/key.properties` (git-ignored) pointing at the keystore; the
release `build.gradle.kts` reads it. iOS: automatic signing with the team id from an
env var in CI, manual export options in `ios/ExportOptions.plist`.

## 4. Post-build checks

- Install the release build on the AVD and the iPhone simulator; verify first-run flow,
  orientation switching (portrait ↔ landscape mid-game), audio, persistence survives relaunch, and that `--obfuscate` did not
  break data loading (JSON keys are strings, not Dart symbols).
- Size check: note APK/IPA size in the changelog; investigate jumps > 20 % (usually atlases).
- Web: load in the built-in browser, confirm assets load from the deployed base href and
  that persistence (IndexedDB via hive) works.
- Web on GitHub Pages: `.github/workflows/pages.yml` rebuilds and deploys on every push to
  `main` (or by hand). It uses the JS build and a relative `<base href="./">`, so it works
  under `/<repo>/`; enable it once with Settings → Pages → Source: GitHub Actions.

## 5. Checklist (copy into the release PR)

- [ ] version + build bumped, tag planned
- [ ] CHANGELOG updated, deviations listed
- [ ] pre-flight green (link CI run)
- [ ] builds produced for: android / ios / macos / windows / linux / web
- [ ] symbols archived
- [ ] manual smoke on phone + tablet, large text
- [ ] credits/licences current
- [ ] no secrets in the diff (`git diff --stat` + grep for `key.properties`, `*.p12`, `*.mobileprovision`)
