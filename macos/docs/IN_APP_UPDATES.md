# In-app updates

The macOS application uses the official Sparkle 2.10.1 binary distribution, pinned by SwiftPM SHA-256. `InAppUpdater` is a main-actor adapter to `SPUStandardUpdaterController`. The existing menu and About button use this single service. The former GitHub-page sheet is removed.

## User flow

A manual check displays localized release notes in the native update window. The user chooses to download; Sparkle displays progress and verifies the archive, then offers Install and Relaunch. Confirmation terminates the old host normally, replaces the app bundle and relaunches it. Sparkle requests system authorization if the installation directory requires it. Read-only/translocated applications need to be installed in a writable application location first. A synchronized File Provider directory can also refuse replacement; that error must remain visible rather than bypassing filesystem protections.

Automatic checks, automatic installation and profiling are disabled by default. No separate root updater or shell replacement script is introduced. The charge Helper remains managed by its existing explicit authorization flow if a later application update changes its bytes.

The standard updater follows macOS's preferred language. All seven app languages are embedded in the signed feed as localized plain-text descriptions exported from the actual in-app changelog. No remote JavaScript or browser navigation is needed to read them.

## Trust and publishing

- Production feed: `https://raw.githubusercontent.com/xincheng1237/drive-battery-health-viewer/main/macos/updates/appcast.xml`.
- The public Ed25519 key is embedded in Info.plist. `SURequireSignedFeed`, `SUVerifyUpdateBeforeExtraction` and a zero signature-failure expiration interval require validation before showing notes or extracting code.
- The private key is kept only in the publisher's macOS login Keychain, account `com.chengxin.drive-battery-health-viewer.sparkle`. It is not in the repository, application, feed or CI. Keychain access dialogs belong to the signing tools used for publishing; end users do not receive them.
- `CFBundleVersion` increases independently of the public version. This revision is 1.1.2/build 17. Update enclosures use immutable build-specific ZIP names; generic DMG/ZIP names remain convenient manual downloads.
- Official framework symlinks and nested signatures are preserved when embedding. The host retains the project's ad-hoc signing; EdDSA signatures authenticate updates. This does not constitute Developer ID notarization.

For a release, first run tests with `DBHV_EXPORT_CHANGELOG=/absolute/path/notes.json`. After building the final ZIP, copy it to the immutable `DriveBatteryHealthViewer_vVERSION_buildBUILD_macOS_Universal.zip` name, then run:

```sh
python3 macos/scripts/generate-appcast.py \
  --archive /path/to/DriveBatteryHealthViewer_vVERSION_buildBUILD_macOS_Universal.zip \
  --notes /path/to/notes.json \
  --sign-tool /path/to/official/Sparkle/bin/sign_update \
  --output macos/updates/appcast.xml
```

The generator reads version/build from Info.plist, requires the seven matching languages, signs the archive and feed with the Keychain key, then verifies the feed. Upload the exact immutable ZIP before making its feed live. Any subsequent change to the feed requires re-signing. CI can build and test without private signing material; publishing needs the existing Keychain key. Preserve that key for future releases.

Already distributed 1.1.2/build 16 contains the old webpage-based checker. It cannot acquire this new engine before replacement; users of that build need to install build 17 manually once. Future signed updates are then handled in-app, including higher-build revisions with the same public version.

## Validation

Local Swift Testing covers updater entry-point forwarding, duplicate checks, retry after startup failure, same-version build ordering, signed-feed/archive settings, seven-language changelog shape and native narrow-window geometry. An opt-in native test renders the actual RootView with an isolated preference/history directory and read-only hardware scan.

A separate QA application compiled the exact production updater adapter against the official framework. A loopback test source demonstrated valid signed notes → download → verification → old process exit → replacement from build 16 to build 17 → automatic new-process launch. A corrupted archive and a tampered signed feed were rejected while preserving build 16. The production application, Helper and user configuration were not replaced by these tests. HTTP/ATS exceptions are confined to the unshipped QA fixture; production uses HTTPS.

Sources: [Apple full-size content layout](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/fullsizecontentview), [Apple titlebar background](https://developer.apple.com/documentation/appkit/nswindow/titlebarappearstransparent), [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [signed publishing and localization](https://sparkle-project.org/documentation/publishing/).
