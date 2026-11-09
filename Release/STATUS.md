# Pearls release status

Verified November 8, 2026 on the user's Mac with Xcode 27.2 (27B52).

| Check | Evidence / result |
| --- | --- |
| Core tests | 20 XCTest cases passed, 0 failures |
| Mac Debug compile | Passed |
| iOS Simulator compile | Passed, including embedded PearlsShare extension |
| Mac Release build | Passed |
| Mac local signature | `codesign --verify --deep --strict` passed |
| Mac installation | `/Applications/Developer/Pearls.app`, version 0.1.0 build 1 |
| Mac launch | Opened from the final install location; collection, search, Favorites, Settings and capture controls visible |
| Device archive | iPhoneOS arm64 archive built; reusable upload archive is `build/ios/Pearls-TestFlight-entitlements-build-1.xcarchive` |
| Distribution export | Passed strict signature verification; app and extension signatures and App Store profiles all retain the required App Group, team, and bundle identifiers |
| Development signing | Apple reports no registered devices available to create development provisioning profiles; user selected TestFlight instead |
| Physical iPhone installation | TestFlight build available; installation on the physical phone not yet verified |
| App Store Connect / TestFlight | Upload succeeded at 5:10:47 PM Phoenix. Apple processed version 0.1.0 build 1; the build is assigned to the internal Briggs group. App Store Connect shows the confirmed internal tester as **Invited** on November 8, 2026; group has 1 tester and 1 build. |

The previous native failures were caused by restricted macOS file-coordination, cache, and compiler-plugin access. Re-running with normal native access passed without changing app source.

Mac installation and launch do not establish every runtime acceptance check. The journeys in `DEVICE-CHECKS.md`, physical iPhone behavior, share-extension behavior, accessibility, and TestFlight delivery still need verification.

## Evidence

- Initial native validation: imported source workspace `build/logs/takeover-validation.log`.
- Canonical checkout Mac installation: `build/logs/takeover-install.log`.
- Canonical checkout signing attempt: `build/logs/takeover-archive.log`.
- Distribution export: `build/logs/takeover-testflight-group-export.log`.
- Initial upload attempt: `build/logs/takeover-testflight-upload.log`.
- Successful upload: `build/logs/takeover-testflight-upload-after-app-record.log`.
- TestFlight build: `2aba377c-93d4-4440-b7f7-921f309c5f61`; internal group: `53c9d19e-50ee-4ba6-8550-cf56d5e56438`.

Logs and derived products are local and ignored by Git. No private signing material is committed. Main app library storage remains local to each device; source mirroring to Proton Drive is separate.

## Continuing the release

1. Keep the verified entitlement-preserving archive. The original unsigned archive's first export omitted App Groups and must not be uploaded.
2. App Store Connect record: [Pearls by Briggs Kellogg](https://appstoreconnect.apple.com/apps/6832381625/distribution), app ID `6832381625`.
3. Invitation is verified. The tester can open the email invitation or TestFlight on their iPhone and install **Pearls by Briggs Kellogg**. Record actual phone installation and runtime acceptance separately.
4. Update this record, commit, and run `python3 scripts/sync-project.py --push` followed by `--check`.

## Repository validation

[GitHub Actions validation](https://github.com/briggskellogg/pearls/actions/runs/42538591024) passed for source commit `f4b8567`, including sync safety tests, the core XCTest suite, and both platform builds.
