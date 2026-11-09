# Pearls native release

This folder contains the release handoff for the first Pearls Mac and iPhone apps. The original source was prepared on Linux. On November 8, 2026, all 20 core tests and both platform compile checks passed on the user's Mac, and the local Mac app was installed and launched from `/Applications/Developer/Pearls.app`. Physical iPhone signing/install and TestFlight delivery remain pending. [STATUS.md](STATUS.md) records current evidence and blockers; the commands below describe the release process.

Version 0.1 stores each device’s main library in the app’s own `Application Support/Pearls` directory. Archive import/export is the transfer mechanism; there is no automatic cloud synchronization. The iOS App Group holds only the shared capture inbox used by Pearls and its share extension. Enabling or changing App Group access does not switch the main library’s storage path.

## Project and commands

The project is `Pearls.xcodeproj`. Its shared schemes are `Pearls-Mac` and `Pearls-iOS`; the iPhone app embeds the `PearlsShare` extension. The app product is `Pearls.app` on both platforms.

Run all commands from the directory containing `Pearls.xcodeproj`:

```bash
bash scripts/validate-apple.sh
bash scripts/install-mac.sh --developer
```

| Script | Purpose |
| --- | --- |
| `scripts/validate-apple.sh` | Run the Foundation package tests and compile the Mac and iOS Simulator app targets without distribution signing |
| `scripts/build-mac.sh` | Build and verify an ad-hoc signed local Mac app |
| `scripts/install-mac.sh --developer` | Build and install to `/Applications/Developer/Pearls.app` (default) |
| `scripts/install-mac.sh --user` | Build and install to the current user’s `~/Applications/Pearls.app` |
| `scripts/install-mac.sh --system` | Build and install to `/Applications/Pearls.app` if that folder is already writable |
| `scripts/archive-ios.sh` | Create a signed device archive using the selected team and authentication |
| `scripts/upload-testflight.sh /absolute/path/to/archive.xcarchive` | Export and upload that exact archive to App Store Connect |

The build scripts first run `BuildSupport/prepare-assets.sh` to generate the required Apple icon assets from the bundled artwork. They fail before build or upload on a non-Mac host. Full Xcode must be installed and opened once to complete setup. Command Line Tools alone are insufficient. If several Xcode installations exist, set `DEVELOPER_DIR` to the intended installation’s `Contents/Developer` directory.

Apple currently requires iOS apps and extensions submitted to App Store Connect to be built with Xcode 26 or later. The submission scripts enforce that minimum; check Apple’s [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) page again when releasing.

## Mac installation

```bash
bash scripts/install-mac.sh --developer
open /Applications/Developer/Pearls.app
```

The default `--developer` destination is `/Applications/Developer`. Use `--user` for `~/Applications` or `--system` for `/Applications`; the selected folder must be writable. The installer never invokes `sudo`, stops no running processes, and refuses to replace an app with a different bundle identifier. Quit Pearls first. When replacing an existing Pearls app, it moves the old app to a timestamped `Pearls-backup-….app` next to the new one. If moving the new build fails, it attempts to restore the old app. User library data is outside the app bundle and is not touched by installation.

The local build uses an ad-hoc code signature. It overrides the project’s entitlements with `Release/Pearls-Local-Mac.entitlements`, keeping App Sandbox and user-selected file access while clearing `PEARLS_APP_GROUP`. The Mac app keeps the same app-container `Application Support/Pearls` library used by signed builds. Clearing the group avoids claiming an App Group reserved to a signed developer team; it does not choose a different library location. Apple describes the signing and provisioning distinction in [App Groups: macOS vs iOS](https://developer.apple.com/forums/thread/721701). The iPhone app and extension use their provisioned App Group only for the shared capture inbox.

This Mac build is intended to run on the Mac where it was built after verification. Public Mac distribution requires a separate Apple distribution signing and notarization workflow. A successful local build does not establish notarization or compatibility on a different Mac.

## Apple identifiers and access

These are proposed defaults in the source, not evidence of registered identifiers or ownership:

| Item | Default / required value |
| --- | --- |
| Main app bundle identifier | `com.briggskellogg.pearls` |
| Share extension bundle identifier | `com.briggskellogg.pearls.share` |
| iOS App Group | `group.com.briggskellogg.pearls` |
| Signing team | Actual 10-character Apple Developer Team ID, supplied as `TEAM_ID` |
| App Store Connect app record | A Pearls iOS app record associated with the chosen app bundle identifier |
| App Store Connect numerical app ID | Assigned by Apple when that record is created; not the Team ID or API key issuer |
| Marketing version | The chosen `MARKETING_VERSION` in the project |
| Build number | A new positive integer supplied as `BUILD_NUMBER`; must not repeat an uploaded build for that version |
| Tester | Briggs’s verified TestFlight email and the correct internal or external group |

Before an archive, select the correct team in Xcode and register the main app identifier, extension identifier, and App Group in that team. Enable the same App Group for the app and extension. The `PEARLS_APP_GROUP` build setting and embedded Info/entitlements values must agree. If the defaults are unavailable, change the identifiers consistently in the project before generating provisioning profiles.

Create the App Store Connect app record before uploading, with the correct iOS platform, bundle identifier, name, primary language, and unique SKU. An active Apple Developer Program membership and authorized App Store Connect access are needed for TestFlight. Review any outstanding agreements with the account owner. Apple documents the setup in [App Store Connect workflow](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow/) and [Distributing your app](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).

## Signing and upload

The default authentication method uses a locally stored App Store Connect **team** API key. Supply paths and identifiers in your Mac’s shell; never commit the `.p8` contents, copy it into this project, or paste its contents into a chat.

```bash
export TEAM_ID='<actual 10-character team ID>'
export ASC_KEY_PATH="$HOME/.private_keys/AuthKey_<key-id>.p8"
export ASC_KEY_ID='<actual key identifier>'
export ASC_ISSUER_ID='<actual team issuer UUID>'
export BUILD_NUMBER='1'
bash scripts/archive-ios.sh
```

Replace the placeholders. API access must permit the app and provisioning actions being performed. The script uses `-allowProvisioningUpdates` and the `-authenticationKeyPath`, `-authenticationKeyID`, and `-authenticationKeyIssuerID` options. These options authorize Xcode; they do not waive Apple role restrictions, certificate requirements, registered identifiers, or capability provisioning. Apple describes the options in [Xcode 13 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-13-release-notes) and API-key uploads in [Xcode 15 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes).

Alternatively, after explicitly signing into the correct Apple account in Xcode Settings, choose that authentication method:

```bash
unset ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID
export APPLE_AUTH_MODE=xcode-account
export TEAM_ID='<actual 10-character team ID>'
export BUILD_NUMBER='1'
bash scripts/archive-ios.sh
```

Archives default to `build/ios/Pearls-build-<number>.xcarchive`. Existing archives are never overwritten. Set `ARCHIVE_PATH` to an absolute `.xcarchive` path to choose a different output. App and extension must share the same marketing version/build and be signed for the selected team.

After validating the exact archive, upload it:

```bash
bash scripts/upload-testflight.sh "$PWD/build/ios/Pearls-build-1.xcarchive"
```

The uploader checks that the archive contains an iPhone device app and the expected bundle identifier. If the bundle identifier was customized, set `EXPECTED_IOS_BUNDLE_ID` to that exact value. The uploader creates a fresh export directory and an `ExportOptions.plist` using `method=app-store-connect`, `destination=upload`, automatic signing, and the selected team. It preserves the archive’s version/build rather than allowing an automatic bump. It also verifies that the installed Xcode advertises the export method in `xcodebuild -help`. Apple documents the [export options file](https://help.apple.com/xcode/mac/current/en.lproj/deva1f2ab5a2.html).

An upload receipt means the upload completed; App Store Connect still needs to process it. Keep the archive and export logs. A failed or uncertain upload should first be reconciled in App Store Connect before attempting the same build again.

## TestFlight invitation

After processing, resolve any export-compliance questions for the actual implementation, provide beta test information, and select the processed build for the intended group. Do not infer compliance answers from the app’s name or assume a source privacy manifest replaces App Store Connect information.

If Briggs already has an eligible App Store Connect role and access to Pearls, add that user to an internal testing group. Apple supports up to 100 internal testers. Internal testers are App Store Connect users, not arbitrary email recipients. See [Add internal testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).

Otherwise, use a private external group and invite Briggs at the verified email. The first external build requires TestFlight App Review before it can be distributed; external groups can contain up to 10,000 testers. No public testing link is needed for a personal invitation. See [Invite external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/).

The supplied scripts do not create tester accounts or send invitations. The release is complete only after the processed build is assigned, any required beta review has cleared, the invitation is sent to the verified recipient, and the recipient can install through TestFlight. Record the app ID, version, build, group, recipient, and confirmed invitation state in the release log.

## Verification before inviting

Run the package tests and unsigned platform compilation with `validate-apple.sh`, then launch both apps on Apple hardware or Simulator. Check capture and editing, link/image/file handling, searching, Favorites and Archive, persistence after quitting, and complete archive export/import including attachments. Exercise an invalid import and confirm the existing library remains intact. Verify app-group capture through the iOS share sheet and repeated sharing while the main app is open. Check compact phone screens, large accessibility text, VoiceOver labels, keyboard focus and shortcuts on Mac, and icon states without relying solely on color.

Check the archived app and extension’s identifiers, build/version, entitlements, signing/provisioning, app icons, and privacy manifests. An empty required-reason API list is appropriate only if the final code and dependencies use none of Apple’s listed APIs. See `PRIVACY-REVIEW.md` for the source inspection and reason mapping, and `PROJECT-REVIEW.md` for the static project review.

## GitHub Actions validation

`.github/workflows/apple-validation.yml` runs validation in the Pearls repository; `Release/apple-validation.yml` retains the supplied template. It assumes the repository root contains `Pearls.xcodeproj`. It uses a GitHub-hosted Mac, runs the core tests, and compiles Mac and iOS Simulator targets with code signing disabled. It requires no Apple certificate, provisioning profile, or App Store Connect secret. It does not produce an installable iPhone release or submit anything to Apple.

GitHub documents its [hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners). Runner images evolve; the workflow prints the selected Xcode/SDK versions. No GitHub Actions run was started in the source-preparation workspace, so the included workflow is not evidence of passing Apple compilation.

## Confirmed TestFlight recipient

Briggs explicitly confirmed **briggs@kellogg.co** for the Pearls TestFlight invitation on November 8, 2026. The address is recorded in `release-target.json`. The authenticated Mac signing certificate identifies team `24KAG7M42P`; Xcode reached that team during provisioning. No invitation has been sent. Current delivery state is recorded in `STATUS.md`.
