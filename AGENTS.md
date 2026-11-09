# Pearls project instructions

## Product

Pearls is a native Mac/iPhone collection for notes, links, images, and files. Preserve the supplied visual identity and existing app/library data. Main library storage is local Application Support; the iPhone App Group is only a capture inbox. Project-source mirroring does not add app-library cloud sync.

## Required synchronization

The user requires completed Pearls work to stay synchronized between this checkout, `https://github.com/briggskellogg/pearls`, and Proton Drive `[projects]/pearls`.

1. At the start of work inspect `git status`, fetch `origin`, and reconcile remote changes with a fast-forward when possible. Never discard uncommitted work or force-push.
2. Read the current `Release/STATUS.md`. Check the Proton mirror for external changes before replacing anything. Reconcile conflicts explicitly; preserve both versions where needed.
3. Complete relevant tests, update release status when it changes, review the exact diff, and commit the finished work.
4. Run `python3 scripts/sync-project.py --push`. The local ignored `.pearls-sync.local.json` supplies the Proton destination; alternatively pass `--destination /absolute/path/to/[projects]/pearls`.
5. Run `python3 scripts/sync-project.py --check`. Report any incomplete GitHub push, mirror conflict, or unverified Proton cloud transfer truthfully.

The sync command mirrors committed source with a SHA-256 receipt, excludes Git internals and ignored build/signing files, and refuses to overwrite conflicting mirror edits. A successful local mirror check is not proof that the Proton client has uploaded it. Never put credentials, signing keys, provisioning profiles, or personal app libraries into GitHub or the project mirror.

No recurring background task has been configured. These instructions apply whenever work is done on Pearls.

## Validation and release

- `bash scripts/validate-apple.sh`: core XCTest suite plus Mac/iOS Simulator compilation.
- `python3 scripts/test-sync-project.py`: project-sync safety checks.
- `bash scripts/install-mac.sh --developer`: guarded installation into `/Applications/Developer`; preserves an existing app as a backup and leaves library data alone. This is the user's requested Mac destination.
- `Release/README.md` and `Release/DEVICE-CHECKS.md`: signing, archive, upload, and runtime checks.

Xcode needs normal macOS cache, compiler-plugin, and file-coordination service access. If a restrictive execution sandbox blocks those services, request the supported execution escalation rather than removing file coordination or SwiftUI state from the code.

Do not call a compile check a device test, a local copy a completed cloud upload, or an archive a TestFlight release. Keep release evidence current and distinguish upload, Apple processing, beta review, and invitation state.
