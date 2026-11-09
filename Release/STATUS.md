# Pearls release status

Current Mac installation and published package: **version 0.1.0 build 4**, from committed source `0238e69f33454c90bf13f0677e68c52d923f4a50`. Build 4 adds optional private iCloud Drive folder sync, retaining each device's offline library and keeping personal contents out of public source/releases and the Proton source mirror.

The build 4 iPhone upload succeeded once on November 8, 2026 at **9:31:11.491 PM America/Phoenix**. Apple processing completed, and build 4 is assigned to the existing Briggs internal group. The build detail page verifies Briggs / Internal / 1 tester, and the What to Test notes were saved. Physical iPhone installation is unverified.

## Build 4 verification

| Check | Evidence / result |
| --- | --- |
| App and packaging source | Clean committed revision `0238e69f33454c90bf13f0677e68c52d923f4a50` |
| Core tests | 36 passed, including convergence, stale deletion, interrupted transfers, bounded progress, remote-original integrity, metadata capacity, and concurrent draft preservation |
| Publication safety tests | 40 passed: 10 private-data guard, 19 source-sync, 11 release-package |
| Native compilation | Mac Debug/Release and iOS Simulator passed |
| Mac installation | `/Applications/Developer/Pearls.app`, exact source revision above; codesign verified; prior app preserved |
| Mac entitlements | Final installed app has sandbox, user-selected read/write access, and app-scoped bookmarks |
| Mac runtime | Settings shows 0.1.0 (4); System appearance choice persisted. Private folder connected; empty collection initialized; provider confirms the empty marker uploaded. |
| Device archive / distribution export | App and share-extension signatures/profiles verified; matching App Groups preserved |
| App Store Connect upload | Succeeded once at 9:31:11.491 PM Phoenix; processing completed; no new invitation sent |
| Tester availability | Build ID `30b33a85-ecad-4f78-98d2-3e8ee1f14023`; detail page verifies Briggs / Internal / 1 tester; What to Test notes saved |
| GitHub package | [Prerelease `v0.1.0-build.4`](https://github.com/briggskellogg/pearls/releases/tag/v0.1.0-build.4), five assets; all server-reported digests match local files |
| CI | [Build 4 source validation](https://github.com/briggskellogg/pearls/actions/runs/42561984530) passed for exact source `0238e69f33454c90bf13f0677e68c52d923f4a50` |
| Physical iPhone / Windows | Installation, live sync, and PC file access remain unverified |

The [build 4 TestFlight detail page](https://appstoreconnect.apple.com/teams/69a6de92-aaed-47e3-e053-5b8c7c11a4d1/apps/6832381625/testflight/ios/30b33a85-ecad-4f78-98d2-3e8ee1f14023) confirms assignment under the unchanged app name **Pearls by Briggs Kellogg**. Saved test instructions cover the private folder, offline edits, conflicts, deletion/restoration, and appearance.

The package at `build/releases/Pearls-0.1.0-build-4/` retains `Pearls-0.1.0-build-4.ipa`, `Pearls-0.1.0-build-4-dSYMs.zip`, `Pearls-0.1.0-build-4.xcarchive.zip`, `release-manifest.json`, and `SHA256SUMS`. Both manifest source fields match the committed build 4 source. No personal library or signing keys are included. PC retrieval/restoration remains unverified.

### Private-folder connection and empty marker upload verified

The dedicated **iCloud Drive/Pearls** folder was created within the explicitly approved scope at 9:18 PM Phoenix. After the user restored foreground interaction, Connect became available and the exact folder was selected. At **9:33 PM Phoenix**, build 4 Settings showed 0 pearls, 0 updates sent/received, **Waiting for iCloud to upload**, and available Disconnect/Reconnect controls. The private folder is connected, its empty collection initialized, and the access bookmark is stored on this device. A subsequent read-only Foundation metadata check of this exact folder’s `pearls-sync.json` reported `isUbiquitousItem=true`, `isUploaded=true`, `isUploading=false`, and no uploading error. This confirms provider upload of the empty collection marker only.

The earlier disabled controls during UI automation were resolved by restoring foreground interaction, without further app source changes. Provider completion is confirmed for the empty marker; the earlier waiting status is retained above as the observed UI sequence. No personal content has been migrated and no live iPhone/Mac/PC transfer has been tested. The local library remains available offline. Windows support is file access through iCloud for Windows, not a native Pearls editor. There is no Proton personal-library backup configured. Follow `PRIVATE-SYNC-SETUP.md` to select the same folder on the phone and verify delivery.

Build 4 evidence: `build/logs/build4-validation-final.log`, `build4-mac-picker-fix.log` (final committed Mac installation), `build4-testflight-prepare.log`, and `build4-testflight-upload.log` in the same log directory; exact artifact hashes are recorded in the release manifest and `release-target.json`.

## Previous build 3 verification

| Check | Evidence / result |
| --- | --- |
| App source | Clean committed revision `2f31ec48b07b24c5343a163e5f5cd4022c686d3a` |
| Packaging implementation | Clean revision `4ad802bcb549ac0fe31abeb80ebe51242f3f5d0e`; recorded separately from the unchanged app source |
| Core tests | 20 XCTest cases passed, 0 failures |
| Mac Debug / Release | Both builds passed |
| iOS Simulator | Passed, including the embedded share extension |
| Fonts | All five registered: PP Neue Montreal Regular/Bold and PP Neue York Normal Light/Medium/Extrabold |
| Mac installation | `/Applications/Developer/Pearls.app`, version 0.1.0 build 3; signature verified and prior app retained as a backup |
| Mac runtime | Light and Dark render correctly; System remains saved through the upgrade and follows the current dark system appearance. App left on System. |
| Device archive / distribution export | Build 3 archive and signature/profile/App Group verification passed |
| App Store Connect upload | Succeeded once on November 8 at 8:44:38 PM Phoenix; no upload errors |
| Apple processing / tester assignment | Build 3 ID `4325f9c0-5220-4c4a-8eb9-8f4833e11d9a` completed processing; the existing Briggs internal group is assigned and its selected state verified in App Store Connect |
| Physical iPhone installation | Unverified |

The verified Mac checks do not establish all journeys in `DEVICE-CHECKS.md`, physical iPhone behavior, share-extension behavior, or accessibility acceptance.

## Retained build 3 release package

`build/releases/Pearls-0.1.0-build-3/` contains five verified files:

- `Pearls-0.1.0-build-3.ipa`
- `Pearls-0.1.0-build-3-dSYMs.zip`
- `Pearls-0.1.0-build-3.xcarchive.zip`
- `release-manifest.json`
- `SHA256SUMS`

The manifest records the app source and packaging revisions separately, binary/dSYM identities, Apple team/bundle/build metadata, and artifact checksums. No signing keys or personal library are included. The [GitHub prerelease `v0.1.0-build.3`](https://github.com/briggskellogg/pearls/releases/tag/v0.1.0-build.3) is published at app source revision `2f31ec48b07b24c5343a163e5f5cd4022c686d3a`. All five uploaded assets are present, and GitHub-reported SHA-256 digests match the local files. TestFlight availability is verified. PC retrieval and restoration remain unverified.

## Source synchronization and Proton evidence

The build 4 app source revision `0238e69f33454c90bf13f0677e68c52d923f4a50` was pushed to GitHub and mirrored to the existing Proton `[projects]/pearls` folder. `sync-project.py --push` and `--check` passed for 91 source files. The native Proton Drive client displayed finished Uploaded/Modified entries for `.pearls-project-sync.json`, the new privacy guard, Settings, LibraryView, and other changed source files.

The earlier build 3 snapshot `2f31ec48b07b24c5343a163e5f5cd4022c686d3a` contained 83 source files and had independently observed client upload-completion checkmarks for its fonts, configuration, and receipt.

This is client-confirmed upload completion for that project source snapshot. It is not an isolated remote download, restore test, personal-library backup, or proof that later receipt changes have uploaded. Verify the final source/documentation commit and its receipt after completing the release.

## Build 3 evidence

- Core tests and Mac/iOS compilation: `build/logs/build3-validation.log`.
- Mac Release build and installation: `build/logs/build3-mac-release.log`, `build/logs/build3-mac-install.log`.
- All five font registrations: `build/logs/build3-font-verification.log`.
- iPhone archive and verified export: `build/logs/build3-testflight-prepare.log`.
- Release package: `build/logs/build3-release-package.log` and the package's `release-manifest.json` / `SHA256SUMS`.
- Successful upload: `build/logs/build3-testflight-upload.log`.
- [Build 3 source CI](https://github.com/briggskellogg/pearls/actions/runs/42557515358): passed for the committed app source.

Build logs and products are ignored by Git. Signing material and personal libraries remain outside the project source mirror.

## Previous verified TestFlight releases

Build 2 uploaded on November 8 at 5:33:22 PM Phoenix, completed Apple processing, and was assigned to Briggs Internal with one tester. Its build ID is `5395a00e-1e51-4f17-a464-496c88182009`. The existing invitation is retained. Build 2 introduced the saved appearance setting and passed Mac appearance/persistence checks. Supporting logs use the `build2-` prefix; the takeover chat's `outputs/pearls-testflight-build-2.png` records assignment.

Build 1 uploaded on November 8 at 5:10:47 PM Phoenix, completed processing, and was assigned to the same internal group. Its ID is `2aba377c-93d4-4440-b7f7-921f309c5f61`. These records do not by themselves establish build 3 availability.

## Remaining delivery steps

1. Retain the verified build 4 delivery and existing Briggs Internal assignment. Do not repeat the successful upload or send a duplicate invitation.
2. Retain the published five-file GitHub prerelease and verified digests. Record PC retrieval/restoration only when separately verified; do not recreate the release or upload duplicate assets.
3. Record the final delivery facts, commit the receipt updates, and run `python3 scripts/sync-project.py --push` followed by `--check`. Verify Proton's completion state for that final update.
4. Select the same private folder on the iPhone and verify saved-content transfer, PC access, and actual phone installation separately.

App Store Connect record: [Pearls by Briggs Kellogg](https://appstoreconnect.apple.com/apps/6832381625/distribution), app ID `6832381625`. Preserve the established team, bundle IDs, and Briggs group. Keep older valid archives; the original build 1 export that omitted App Groups must not be uploaded.

## Personal app system

`RELEASE_PROMPT.txt` adopts the reusable instructions with explicit public-repository and scoped source-mirror exceptions. `project-destinations.json` records destinations and unknowns; it is not a running backup or release scheduler.

- GitHub source: **VERIFIED** for the recorded app revision; final documentation sync follows release completion.
- TestFlight: build 4 **VERIFIED AVAILABLE** to Briggs Internal, one tester; saved testing notes verified. Physical iPhone installation is unverified.
- Proton project source: **VERIFIED CLIENT UPLOAD** for the recorded 91-file snapshot, with no remote restore test.
- Private iCloud content sync: **MAC CONNECTED / EMPTY MARKER UPLOAD VERIFIED**. Provider metadata confirms the initialized empty marker uploaded; saved-content transfer and iPhone/PC delivery remain unverified. No CloudKit database is used, and no independent backup has been verified. See `PRIVATE-SYNC-SETUP.md`.
- PC archive: **PENDING VERIFICATION**. The user reports setup is ready, but no endpoint, exact personal paths, or restore result is available here.
- Proton personal-data/release archive and hosted signing/renewal schedules: **NOT CONFIGURED HERE**. No broad filesystem collection, new schedule, data migration, or pruning was enabled.

`PERSONAL-APP-SYSTEM.md` retains the PC/archive and hosted release prerequisites. The existing project source mirror is separate from those broader backups.

## Public-source privacy guard

The publication guard is implemented and its synthetic checks pass: 10 private-data guard tests, 19 source-sync tests, and 11 release-package tests. Known library/archive/sync documents, original/private trees, malformed identifiable JSON, and signing/local secrets are rejected before source publication or package extraction. The source guard also rejects private data in reachable Git history after a file is deleted from HEAD. Legitimate app artwork/fonts remain accepted. These tests did not read or copy the user's saved contents and are not live cloud-sync tests.
