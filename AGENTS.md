# Pearls project instructions

## Product

Pearls is a native Mac/iPhone collection for notes, links, images, and files. Preserve the supplied visual identity and existing app/library data. The local Application Support library remains the offline working copy; the iPhone App Group is only a capture inbox. Build 4 adds optional private content exchange through one explicitly chosen iCloud Drive Pearls folder. It is separate from project-source mirroring. The Mac has connected the dedicated private iCloud Drive/Pearls folder and initialized an empty collection; provider upload of the empty marker is confirmed, while saved-content transfer and iPhone/PC delivery remain unverified. Each device must explicitly select the same private folder.

Saved notes, links, images, PDFs, originals, library metadata, private sync versions, and collection exports must never enter the public GitHub repository, a GitHub release, or the Proton project-source mirror. Windows has file access through iCloud for Windows, not a native Pearls editor. Follow `Release/PRIVATE-SYNC-SETUP.md`; do not choose a private sync folder on the user's behalf or point it at this source repository/Proton project folder.

## Required synchronization

The user requires completed Pearls work to stay synchronized between this checkout, `https://github.com/briggskellogg/pearls`, and Proton Drive `[projects]/pearls`.

Read `RELEASE_PROMPT.txt` and `project-destinations.json` for the adopted personal-app-system instructions and verified destination map. Preserve the explicit project exceptions: the existing repository remains public by prior user authorization, and the latest instruction authorizes this specific Git-tracked Pearls source mirror from the Mac to the established Proton folder. Do not change repository visibility, relocate the source mirror, or ask again about those already confirmed destinations.

This exception covers only this project's committed source. It does not authorize a work-Mac backup, personal-library migration, signing-secret transfer, or collection of ignored/unrelated files. The PC setup is reported ready by the user, but its endpoint, exact personal source allowlist, archive paths, and restore results are unverified here. Broader backup execution remains disabled. See `Release/PERSONAL-APP-SYSTEM.md` for the pending PC/archive and hosted release work.

The user's later private-content-sync request separately authorizes the app's scoped iCloud folder feature. Connecting through the app grants access to that dedicated folder; it does not broaden source publication or filesystem backup scope. Keep local content when disconnected, preserve cloud files, and never prune the private version/original trees manually.

1. At the start of work inspect `git status`, fetch `origin`, and reconcile remote changes with a fast-forward when possible. Never discard uncommitted work or force-push.
2. Read the current `Release/STATUS.md`. Check the Proton mirror for external changes before replacing anything. Reconcile conflicts explicitly; preserve both versions where needed.
3. Complete relevant tests, update release status when it changes, review the exact diff, and commit the finished work.
4. Run `python3 scripts/sync-project.py --push`. The local ignored `.pearls-sync.local.json` supplies the Proton destination; alternatively pass `--destination /absolute/path/to/[projects]/pearls`.
5. Run `python3 scripts/sync-project.py --check`. Report any incomplete GitHub push, mirror conflict, or unverified Proton cloud transfer truthfully.

The sync command mirrors committed source with a SHA-256 receipt, excludes Git internals and ignored build/signing files, and refuses to overwrite conflicting mirror edits. A successful local mirror check is not proof that the Proton client has uploaded it. Never put credentials, signing keys, provisioning profiles, or personal app libraries into GitHub or the project mirror.

If GitHub is temporarily unavailable or awaiting an explicit publishing decision, `python3 scripts/sync-project.py --mirror-only` can complete the local Proton copy. It performs no network calls and does not verify or claim a GitHub sync.

No recurring background task has been configured. These instructions apply whenever work is done on Pearls.

## Validation and release

- `bash scripts/validate-apple.sh`: core XCTest suite plus Mac/iOS Simulator compilation.
- `python3 scripts/test-sync-project.py`: project-sync safety checks.
- `python3 scripts/test-private-data-guard.py` and `python3 scripts/test-release-package.py`: synthetic checks that recognizable private collections, exports, sync records, originals, and secrets are rejected from source history and release inputs.
- `bash scripts/install-mac.sh --developer`: guarded installation into `/Applications/Developer`; preserves an existing app as a backup and leaves library data alone. This is the user's requested Mac destination.
- `Release/README.md` and `Release/DEVICE-CHECKS.md`: signing, archive, upload, and runtime checks.

Use the public Apple app naming convention `[app name] by Briggs Kellogg`; the existing record is `Pearls by Briggs Kellogg`. Preserve its team, bundle IDs, App Store Connect app ID, and existing tester group. Commit the intended source before producing the next native release, record its exact Git SHA in the release artifact manifest, and do not re-upload an already delivered build for documentation-only changes.

Xcode needs normal macOS cache, compiler-plugin, and file-coordination service access. If a restrictive execution sandbox blocks those services, request the supported execution escalation rather than removing file coordination or SwiftUI state from the code.

Do not call a compile check a device test, a local copy a completed cloud upload, or an archive a TestFlight release. Keep release evidence current and distinguish upload, Apple processing, beta review, and invitation state.
