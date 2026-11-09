# Pearls release status

Current source: **version 0.1.0 build 3 in preparation**, with PP Neue Montreal interface/brand typography and PP Neue York headings and saved-note reading. Build 3 must be committed, validated, packaged with its source revision, and delivered before it is described as released.

Latest verified Mac installation and TestFlight release: **version 0.1.0 build 2**, verified November 8, 2026 on the user's Mac with Xcode 27.2 (27B52). The results below describe build 2 unless explicitly marked otherwise.

Build 2 adds System/Light/Dark appearance in Settings. System is the default; the selected choice persists on that device. The main app's privacy manifest declares its app-only UserDefaults preference, while the share extension retains a separate manifest without that API declaration.

| Check | Evidence / result |
| --- | --- |
| Core tests | 20 XCTest cases passed, 0 failures |
| Mac Debug compile | Passed |
| iOS Simulator compile | Passed, including embedded PearlsShare extension |
| Mac Release build | Passed |
| Mac local signature | `codesign --verify --deep --strict` passed |
| Mac installation | `/Applications/Developer/Pearls.app`, version 0.1.0 build 2; previous app retained as a timestamped backup |
| Mac appearance runtime checks | Default System verified; Dark renders and remains selected after quit/relaunch; switching Dark to System immediately follows the current light macOS appearance; Light is selectable. App left on System. |
| Device archive | Build 2 iPhoneOS archive completed: `build/ios/Pearls-TestFlight-build-2.xcarchive` |
| Distribution export | Build 2 passed local verification; both signatures and distribution profiles permit `group.com.briggskellogg.pearls` |
| Development signing | Apple reports no registered devices available to create development provisioning profiles; user selected TestFlight instead |
| Physical iPhone installation | Build 2 is available to the existing internal TestFlight group; installation on the physical phone is not yet verified |
| App Store Connect / TestFlight | Build 2 upload succeeded at 5:33:22 PM Phoenix on November 8, 2026. Apple processed version 0.1.0 build 2, and its detail page shows 1 group: Briggs / Internal / 1 tester. The group assignment and selected checkmark are verified; the tester's existing invitation is retained. |
| TestFlight notes | Saved What to Test: “Settings → Appearance now offers System, Light, and Dark. System follows your device’s appearance, and your choice is remembered when you reopen Pearls.” |

The previous native failures were caused by restricted macOS file-coordination, cache, and compiler-plugin access. Re-running with normal native access passed without changing app source.

The verified Mac appearance checks do not establish every runtime acceptance check. The remaining journeys in `DEVICE-CHECKS.md`, physical iPhone installation and behavior, share-extension behavior, and accessibility still need verification.

## Previous TestFlight release: build 1

Version 0.1.0 build 1 uploaded successfully at 5:10:47 PM Phoenix on November 8, 2026. Apple processed it and assigned it to the internal Briggs group. App Store Connect showed the confirmed internal tester as **Invited**, with 1 tester and 1 build in the group. This is historical evidence for build 1; it does not establish build 2 availability.

## Evidence

- Build 2 core tests and Mac/iOS Simulator compilation: `build/logs/build2-validation.log`.
- Build 2 Mac Release build: `build/logs/build2-mac-release.log`.
- Build 2 Mac installation: `build/logs/build2-mac-install.log`; the installed Info.plist confirms version 0.1.0 build 2, and strict signature verification passed.
- Build 2 archive and verified distribution export: `build/logs/build2-testflight-prepare.log`.
- Build 2 successful upload: `build/logs/build2-testflight-upload.log`; Xcode reported upload success at 5:33:22 PM Phoenix and exited successfully.
- App Store Connect processed build 2 ID: `5395a00e-1e51-4f17-a464-496c88182009`, uploaded November 8 at 5:33 PM Phoenix; Briggs internal group assignment verified in the UI.
- Build 2 TestFlight assignment screenshot: `outputs/pearls-testflight-build-2.png` in the takeover chat workspace, outside this repository.
- Build 2 Mac appearance screenshot: `outputs/pearls-appearance-system.png` in the takeover chat workspace, outside this repository.
- Initial native validation: imported source workspace `build/logs/takeover-validation.log`.
- Canonical checkout Mac installation: `build/logs/takeover-install.log`.
- Canonical checkout signing attempt: `build/logs/takeover-archive.log`.
- Distribution export: `build/logs/takeover-testflight-group-export.log`.
- Initial upload attempt: `build/logs/takeover-testflight-upload.log`.
- Successful upload: `build/logs/takeover-testflight-upload-after-app-record.log`.
- Previous TestFlight build 1: `2aba377c-93d4-4440-b7f7-921f309c5f61`; internal group: `53c9d19e-50ee-4ba6-8550-cf56d5e56438`.

Logs and derived products are local and ignored by Git. No private signing material is committed. Main app library storage remains local to each device; source mirroring to Proton Drive is separate.

## Continuing the release

1. Commit the complete build 3 source before building. Validate, package the signed build/dSYMs/archive with a commit-and-checksum manifest, then deliver that exact revision. Retain the uploaded build 2 archive, `build/ios/Pearls-TestFlight-build-2.xcarchive`; do not repeat its successful upload. The original build 1 unsigned archive's first export omitted App Groups and must not be uploaded.
2. App Store Connect record: [Pearls by Briggs Kellogg](https://appstoreconnect.apple.com/apps/6832381625/distribution), app ID `6832381625`.
3. The already invited tester can install **Pearls by Briggs Kellogg**, version 0.1.0 build 2, through TestFlight. Record actual phone installation and runtime acceptance separately.
4. Update this record, commit, and run `python3 scripts/sync-project.py --push` followed by `--check`.

## Personal app system

The reusable instructions are adopted in `RELEASE_PROMPT.txt`, with the user's explicit public-repository and scoped source-mirror exceptions. `project-destinations.json` records verified non-secret destinations; it is a status map, not an active backup or release scheduler.

- GitHub and the local Proton `[projects]/pearls` source copy: retain the established tracked-source-only workflow and verify each completed commit. No personal app library or ignored local files are copied.
- iCloud runtime sync and independent iPhone-to-iCloud exports: **NOT CONFIGURED**. Existing `.pearlsarchive` export/import is manual.
- PC archive: **PENDING VERIFICATION**. The user reports setup is ready, but this chat has no verified endpoint, exact personal source/target paths, or restore-test result.
- Proton personal-data/release archive: **NOT CONFIGURED HERE**; the existing local source mirror is separate, and its cloud upload has not been independently verified.
- Hosted signing, TestFlight renewal, and backup schedules: **NOT CONFIGURED**. Existing hosted validation remains available.

The remaining source/release artifact plan and hosted release prerequisites are in `PERSONAL-APP-SYSTEM.md`. No broad filesystem collection, new schedule, data migration, or backup pruning was enabled.

## Repository validation

Build 2 source commit `f9e48da31f8b65e16062ba7564855b192544df5a` was pushed to GitHub and mirrored to the local Proton project folder, with 76 source files verified. Proton's subsequent cloud upload remains a separate client operation.

[Build 2 GitHub Actions validation](https://github.com/briggskellogg/pearls/actions/runs/42540982745) is in progress for that source commit. The local tests and platform builds have passed as recorded above. [Earlier GitHub Actions validation](https://github.com/briggskellogg/pearls/actions/runs/42538591024) passed for commit `f4b8567`, including sync safety tests, the core XCTest suite, and both platform builds.
