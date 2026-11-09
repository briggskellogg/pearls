# Pearls release status

Current Mac installation and packaged source: **version 0.1.0 build 3**, verified November 8, 2026 with Xcode 27.2 (27B52). Build 3 uses PP Neue Montreal for interface/brand typography and PP Neue York for headings and saved-note reading. Its System/Light/Dark preference remains available and preserved across the upgrade.

**Build 4 is pending:** source work adds optional private saved-content exchange through an explicitly selected iCloud Drive Pearls folder. All 36 core tests pass, including convergence, stale deletion, interrupted transfers, bounded progress, remote-original integrity, metadata capacity, and concurrent draft preservation. The independent review's three findings are resolved with regression coverage. Final native validation passed all 36 core tests, Mac Debug compilation, and iOS Simulator compilation; evidence is `build/logs/build4-validation-final.log`. Mac Release installation/runtime checks and signing/TestFlight delivery remain pending. iPhone and Mac retain local offline libraries; Windows receives JSON/original files through iCloud for Windows, with no native Windows editor. No folder is connected and no live cross-device test has run. The build 3 evidence below remains unchanged.

The iPhone build 3 upload succeeded, Apple processing completed, and the existing Briggs internal group is selected for build 3. Tester availability is verified in App Store Connect; physical iPhone installation remains unverified.

## Build 3 verification

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

## Retained release package

`build/releases/Pearls-0.1.0-build-3/` contains five verified files:

- `Pearls-0.1.0-build-3.ipa`
- `Pearls-0.1.0-build-3-dSYMs.zip`
- `Pearls-0.1.0-build-3.xcarchive.zip`
- `release-manifest.json`
- `SHA256SUMS`

The manifest records the app source and packaging revisions separately, binary/dSYM identities, Apple team/bundle/build metadata, and artifact checksums. No signing keys or personal library are included. The [GitHub prerelease `v0.1.0-build.3`](https://github.com/briggskellogg/pearls/releases/tag/v0.1.0-build.3) is published at app source revision `2f31ec48b07b24c5343a163e5f5cd4022c686d3a`. All five uploaded assets are present, and GitHub-reported SHA-256 digests match the local files. TestFlight availability is verified. PC retrieval and restoration remain unverified.

## Source synchronization and Proton evidence

The app source revision `2f31ec48b07b24c5343a163e5f5cd4022c686d3a` was pushed to GitHub and mirrored to the existing Proton `[projects]/pearls` folder, with 83 source files checked against the local SHA-256 receipt. The native Proton Drive client showed Uploaded/Modified completion checkmarks for the new Pearls files, including fonts, configuration, and `.pearls-project-sync.json`.

This is client-confirmed upload completion for that project source snapshot. It is not an isolated remote download, restore test, personal-library backup, or proof that later receipt changes have uploaded. Verify the final source/documentation commit and its receipt after completing the release.

## Evidence

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

1. Retain the verified build 3 TestFlight delivery and existing tester group assignment. Do not repeat the successful upload or send a duplicate invitation.
2. Retain the published five-file GitHub prerelease and verified digests. Record PC retrieval/restoration only when separately verified; do not recreate the release or upload duplicate assets.
3. Record the final delivery facts, commit the receipt updates, and run `python3 scripts/sync-project.py --push` followed by `--check`. Verify Proton's completion state for that final update.
4. Record actual phone installation and runtime acceptance separately.

App Store Connect record: [Pearls by Briggs Kellogg](https://appstoreconnect.apple.com/apps/6832381625/distribution), app ID `6832381625`. Preserve the established team, bundle IDs, and Briggs group. Keep older valid archives; the original build 1 export that omitted App Groups must not be uploaded.

## Personal app system

`RELEASE_PROMPT.txt` adopts the reusable instructions with explicit public-repository and scoped source-mirror exceptions. `project-destinations.json` records destinations and unknowns; it is not a running backup or release scheduler.

- GitHub source: **VERIFIED** for the recorded app revision; final documentation sync follows release completion.
- TestFlight: build 3 **VERIFIED** processed and assigned to the existing Briggs internal group. Physical iPhone installation is unverified.
- Proton project source: **VERIFIED CLIENT UPLOAD** for the recorded 83-file snapshot, with no remote restore test.
- Private iCloud content sync: **PENDING BUILD 4 / NOT CONNECTED**. User-selected file-based sync is being implemented; no CloudKit database is used, and no live cross-device behavior or independent backup has been verified. Build 3 archive transfer remains manual. See `PRIVATE-SYNC-SETUP.md`.
- PC archive: **PENDING VERIFICATION**. The user reports setup is ready, but no endpoint, exact personal paths, or restore result is available here.
- Proton personal-data/release archive and hosted signing/renewal schedules: **NOT CONFIGURED HERE**. No broad filesystem collection, new schedule, data migration, or pruning was enabled.

`PERSONAL-APP-SYSTEM.md` retains the PC/archive and hosted release prerequisites. The existing project source mirror is separate from those broader backups.

## Public-source privacy guard

The publication guard is implemented and its synthetic checks pass: 10 private-data guard tests, 19 source-sync tests, and 11 release-package tests. Known library/archive/sync documents, original/private trees, malformed identifiable JSON, and signing/local secrets are rejected before source publication or package extraction. The source guard also rejects private data in reachable Git history after a file is deleted from HEAD. Legitimate app artwork/fonts remain accepted. These tests did not read or copy the user's saved contents and are not live cloud-sync tests.
