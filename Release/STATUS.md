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
| Physical iPhone installation | Pending TestFlight delivery; no USB connection requested |
| App Store Connect / TestFlight | Initial upload attempt stopped before transmission because the app record was missing; creation of the approved “Pearls by Briggs Kellogg” record is in progress. No processed build or invitation yet. |

The previous native failures were caused by restricted macOS file-coordination, cache, and compiler-plugin access. Re-running with normal native access passed without changing app source.

Mac installation and launch do not establish every runtime acceptance check. The journeys in `DEVICE-CHECKS.md`, physical iPhone behavior, share-extension behavior, accessibility, and TestFlight delivery still need verification.

## Evidence

- Initial native validation: imported source workspace `build/logs/takeover-validation.log`.
- Canonical checkout Mac installation: `build/logs/takeover-install.log`.
- Canonical checkout signing attempt: `build/logs/takeover-archive.log`.
- Distribution export: `build/logs/takeover-testflight-group-export.log`.
- Initial upload attempt: `build/logs/takeover-testflight-upload.log`.

Logs and derived products are local and ignored by Git. No private signing material is committed. Main app library storage remains local to each device; source mirroring to Proton Drive is separate.

## Continuing the release

1. Keep the verified entitlement-preserving archive. The original unsigned archive's first export omitted App Groups and must not be uploaded.
2. Complete the App Store Connect app record in the authenticated account and relevant release checks.
3. Upload an unused build, verify processing, assign the TestFlight build, and invite the confirmed recipient. The user selected TestFlight rather than direct USB installation.
4. Update this record, commit, and run `python3 scripts/sync-project.py --push` followed by `--check`.
