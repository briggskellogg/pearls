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
| Signed iPhone archive | Blocked: Apple reports no registered devices available to create development provisioning profiles for app and extension |
| Physical iPhone installation | Pending connection/pairing of an unlocked iPhone; only simulators were visible |
| App Store Connect / TestFlight | No upload, processed build, or invitation yet |

The previous native failures were caused by restricted macOS file-coordination, cache, and compiler-plugin access. Re-running with normal native access passed without changing app source.

Mac installation and launch do not establish every runtime acceptance check. The journeys in `DEVICE-CHECKS.md`, physical iPhone behavior, share-extension behavior, accessibility, and TestFlight delivery still need verification.

## Evidence

- Initial native validation: imported source workspace `build/logs/takeover-validation.log`.
- Canonical checkout Mac installation: `build/logs/takeover-install.log`.
- Canonical checkout signing attempt: `build/logs/takeover-archive.log`.

Logs and derived products are local and ignored by Git. No private signing material is committed. Main app library storage remains local to each device; source mirroring to Proton Drive is separate.

## Continuing the release

1. Connect and unlock the user's iPhone, pair/trust it, and confirm device availability.
2. Use the authorized Apple developer team to register/provision the main app, share extension, and shared group; build/install and launch on that phone.
3. Complete relevant device checks. For TestFlight, establish the App Store Connect app record, archive with appropriate signing, upload an unused build, verify processing, and invite the confirmed recipient.
4. Update this record, commit, and run `python3 scripts/sync-project.py --push` followed by `--check`.
