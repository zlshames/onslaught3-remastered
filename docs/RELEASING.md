# Releasing

How a build reaches players through GitHub. `.github/workflows/release.yml` does the work; the
`release-build` skill holds the checklist.

## One-time setup

1. Create the repository on GitHub as `zlshames/onslaught3-remastered`, the name the README's
   links and badges use, and push `main`. Keep it **public**: GitHub's ARM runners
   (`windows-11-arm`, `ubuntu-22.04-arm`) are free only for public repositories, and free Pages
   needs it too.
2. Settings → Pages → Source: **GitHub Actions**. `pages.yml` then publishes the current `main` on
   every push. Its first run fails if this is not set.
3. Create the Android signing key and store it as secrets. A tagged build refuses to run
   without it, because a debug key changes on every runner, so each build would refuse to
   install over the last and players would have to uninstall and lose their saves.

   ```bash
   keytool -genkeypair -v -keystore upload.jks -keyalg RSA -keysize 4096 -validity 10000 -alias upload
   ```

   ```bash
   gh secret set ANDROID_KEYSTORE_BASE64 < <(base64 -i upload.jks)
   ```

   ```bash
   gh secret set ANDROID_KEYSTORE_PASSWORD
   ```

   ```bash
   gh secret set ANDROID_KEY_PASSWORD
   ```

   ```bash
   gh secret set ANDROID_KEY_ALIAS --body upload
   ```

   Keep `upload.jks` and its passwords backed up outside the repository. If the key is lost,
   installed copies can never be updated.

## Cutting a release

Versions look like `1.0.0-beta.1+1`. The part after `+` must increase on every release, because
Android refuses to install a lower number over a higher one. A hyphen in the version marks the
GitHub release as a pre-release.

1. Set `version` in `pubspec.yaml`, and give `CHANGELOG.md` a `## 1.0.0-beta.1` section. That
   section becomes the release notes, and the workflow fails without it.
2. Run the local pre-flight in the `release-build` skill: tests, and the device checks CI cannot
   do.
3. Commit, then tag that commit and push the tag. The tag must equal `v` plus the version
   without the `+` part, or the workflow fails.

   ```bash
   git tag v1.0.0-beta.1
   ```

   ```bash
   git push origin main v1.0.0-beta.1
   ```

4. The workflow runs the PR gate and the 3× soak, builds every platform, and creates a **draft**
   release with the downloads, `SHA256SUMS.txt` and the notes attached.
5. Install the draft's downloads, try them (`release-build` §4), and press **Publish**. Only then
   do players see it.

To try the builds without a release, run the workflow by hand from the Actions tab. That builds
everything, publishes nothing and allows a debug-signed APK.

## What gets built

| Download | Built on | Signing |
| --- | --- | --- |
| `onslaught3-remastered-<version>-android-{arm64-v8a,armeabi-v7a,x86_64,universal}.apk` | `ubuntu-latest` | upload key from secrets |
| `onslaught3-remastered-<version>-macos-universal.zip` (x86_64 + arm64) | `macos-latest` | ad hoc; not notarized |
| `onslaught3-remastered-<version>-windows-x64.zip` | `windows-latest` | none |
| `onslaught3-remastered-<version>-windows-arm64.zip` | `windows-11-arm` | none |
| `onslaught3-remastered-<version>-linux-x64.tar.gz` | `ubuntu-22.04` | none |
| `onslaught3-remastered-<version>-linux-arm64.tar.gz` | `ubuntu-22.04-arm` | none |
| `onslaught3-remastered-<version>-web.zip` (relative base href) | `ubuntu-latest` | none |

Run artifacts that are not published: `android-store` (the `.aab` and Dart symbols for the Play
Store and crash symbolication) and `ios-symbols` (iOS is built unsigned, only to prove that it
builds). Keep the symbols of every shipped build.

The ARM desktop builds clone Flutter at the pinned tag, because the stable SDK archives are x64
only. They are allowed to fail for now (`continue-on-error`): a failure leaves that download out
of the draft instead of holding back the release, so check the draft's file list against this
table. Remove the `continue-on-error` lines once they have proved reliable.

## The web build

There are two: `pages.yml` deploys the current `main` to GitHub Pages on every push, and each
release attaches a `web.zip` of the tagged commit. The live site can therefore be newer than the
latest release.
