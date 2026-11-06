# In-app updates

The macOS app uses Sparkle 2.10.1, pinned by its SwiftPM SHA-256. Settings and the application menu share `InAppUpdater`, a main-actor adapter to `SPUStandardUpdaterController`.

## Update flow

1. Choose **Check for Updates** in Settings or the application menu.
2. Read the localized release notes and choose to download.
3. Confirm installation. Sparkle verifies the archive, quits the current app, replaces it, and relaunches the new version.

Install the app in Applications for updates. Sparkle presents system authorization when the installation location requires it. Older editions with the webpage-based checker can install 1.2 manually once, then use this flow.

## Distribution

- Feed: `https://raw.githubusercontent.com/xincheng1237/drive-battery-health-viewer/main/macos/updates/appcast.xml`.
- Current release: **1.2 / build35**.
- Immutable archive: `DriveBatteryHealthViewer_v1.2_build35_macOS_Universal.zip`.
- Release-note text is exported from the application's actual changelog in all seven languages.
- Users initiate update checks and installation. The updater follows the system's preferred language.

The embedded Ed25519 public key verifies both feed and archive before extraction. `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction` remain enabled. The application uses ad-hoc code signing; Sparkle's EdDSA signature authenticates the update payload.

The publisher's signing key is stored in the login Keychain under account `com.chengxin.drive-battery-health-viewer.sparkle`. Publishing uses that existing key through the official Sparkle signing tool. The public key is embedded in Info.plist; CI verifies signatures using it.

## Publish

Export the actual changelog by running the opt-in test with `DBHV_EXPORT_CHANGELOG=/absolute/path/notes.json`. Use the approved ZIP's original bytes with its immutable filename, then generate the feed:

```sh
python3 macos/scripts/generate-appcast.py \
  --archive /path/to/DriveBatteryHealthViewer_v1.2_build35_macOS_Universal.zip \
  --notes /path/to/notes.json \
  --sign-tool /path/to/Sparkle/bin/sign_update \
  --output macos/updates/appcast.xml
```

The generator validates version/build, all seven languages, archive length, and signatures. Publish the archive before activating its feed. Any feed edit requires a fresh signature. Preserve the same signing key for future releases.

## Verification

Tests cover updater forwarding and retry, build ordering, signed feed bytes, localized descriptions, release metadata, and native window behavior. Signature checks include a modified-byte rejection. A separate local updater fixture has exercised the complete notes, download, verification, process exit, replacement, and relaunch flow using the production updater adapter.

[Sparkle setup](https://sparkle-project.org/documentation/) · [Programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/) · [Publishing](https://sparkle-project.org/documentation/publishing/)
