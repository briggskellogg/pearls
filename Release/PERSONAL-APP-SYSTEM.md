# Pearls personal app system handoff

Adopted November 8, 2026. `../RELEASE_PROMPT.txt` contains the reusable instructions and the controlling project-specific exceptions. `../project-destinations.json` records verified identifiers and explicit unknowns. Neither file activates a cloud service or scheduled job.

## Confirmed project scope

Keep the existing public repository `briggskellogg/pearls`, branch `main`, and the established Proton Drive `[projects]/pearls` project-source folder. The user explicitly reaffirmed these destinations after the broader cloud-system discussion. The public Apple name is **Pearls by Briggs Kellogg**; retain the existing app record, bundle IDs, team, and Briggs internal tester group.

The existing sync script mirrors only committed Git-tracked Pearls source and validates a SHA-256 receipt. Its private local configuration identifies the exact Proton folder. The exception permits this particular project source mirror from the Mac; it does not permit whole-Mac backups, collection of ignored/unrelated files, personal app libraries, credentials, or signing secrets. Preserve existing Proton files and reconcile conflicts rather than deleting or relocating the mirror.

The generic kit's private-repository default and prohibition on work-Mac filesystem backups do not revoke these explicit source-only permissions. They still govern all broader backup work. Broader data backup execution stays disabled because exact approved PC/iCloud sources and archive paths are not established in this chat. The user reports the PC setup is ready; that report is not a completed backup or restore test.

## Current implementation and remaining work

| Stage | Current evidence | Remaining work |
| --- | --- | --- |
| GitHub source | Existing personal repository and main branch; source changes are committed and pushed | Verify the final commit after each release |
| Proton project source | Existing `[projects]/pearls` local mirror with committed-source hashes | Verify the new local receipt after source changes; remote Proton upload remains separately unverified |
| TestFlight | Version 0.1.0 build 2 processed and assigned to Briggs Internal; physical phone installation unverified | Build 3 is preparing; validate and deliver from its committed revision |
| iCloud runtime data | Main library is local Application Support; no iCloud entitlement or CloudKit implementation | Verify the intended personal account/container, implement offline changes/conflicts/deletions/assets, and verify production behavior across devices |
| Portable personal exports | Manual `.pearlsarchive` includes records and originals, limited to 100 MiB; imports reject differing same-ID records | Add complete versioned/checksummed exports to a verified personal iCloud Drive destination, produced by iPhone without the Mac; do not claim current manual import is cloud conflict resolution |
| PC archive | User reports setup ready; no accessible endpoint, approved source paths, archive paths, or restore evidence here | Read only the approved project setup when access is available and verify its exact scope, hydration, snapshots, and restoration |
| Proton data/release backup | No verified PC upload job or remote archive receipt in this chat | Use approved PC staging and official Proton tooling; verify remote completion and isolated restore |
| Hosted Apple release | macOS validation workflow exists; signed releases currently use local Xcode access | Establish secure hosted signing/API access, immutable source provenance, artifact retention, and TestFlight processing/group verification |

Existing personal data remains in its current location. No automatic library migration is authorized by this handoff, and no app data is copied during project-source synchronization.

## Source and release artifacts for the PC

These are proposed relative conventions, not verified or created PC directories:

| Content | Proposed PC archive location | Proposed Proton location after root verification |
| --- | --- | --- |
| Approved personal dataset exports | `<approved-PC-archive-root>/pearls/DataBackups/<source-time>/<snapshot-id>/` | `<approved-Proton-archive-root>/pearls/DataBackups/` |
| Exact personal Git revision | `<approved-PC-archive-root>/pearls/SourceBackups/<git-sha>/` | `<approved-Proton-archive-root>/pearls/SourceBackups/` |
| Signed build and recovery artifacts | `<approved-PC-archive-root>/pearls/Releases/<version>/<build>/<git-sha>/` | `<approved-Proton-archive-root>/pearls/Releases/` |

Keep the PC archive outside live iCloud and Proton source folders. Do not infer these roots from the existing Mac source-mirror path or create them until the actual PC configuration is available. Do not relocate the already authorized source mirror to adopt this layout.

The PC should retrieve only this approved repository/revision and its verified release artifacts through authenticated GitHub access. Never enumerate and archive every accessible repository. Source backups should retain the exact commit, repository identity, source archive or Git bundle, and checksums. Releases should retain the signed IPA or supported app package, dSYMs, commit/build manifest, SHA-256 checksums, release receipt, and practical `.xcarchive`. Do not include `.p8`/`.p12` signing secrets, keychains, credentials, or personal libraries in code or release packages.

Build from a clean committed source revision and record the SHA before compiling. Package the exact verified outputs; an archive or successful upload alone does not establish tester availability. Verify source/build/manifest consistency before staging to the PC, validate downloaded bytes there, then upload only that approved staging scope to Proton. Record the source-data time, backup-job time, Git SHA, app version/build, artifact hashes, and remote verification separately. Test restoration into isolated locations; never overwrite a live library or propagate deletions into historical snapshots.

## Hosted release prerequisites

The existing `.github/workflows/apple-validation.yml` compiles and tests on `macos-latest`; it does not sign, upload, retain a release artifact set, or renew TestFlight builds.

Before activating hosted releases:

1. Verify the authorized hosted macOS runner and Xcode version, then make toolchain selection explicit.
2. Configure secure Apple signing/App Store Connect access for the verified team and app. The local Xcode account is not a hosted credential store. Do not copy the work Mac's keychain or personal credential files into the repository.
3. Build a clean immutable commit, allocate an unused build number, preserve app/share-extension entitlements, run existing validation, and verify the exported signatures and profiles.
4. Retain the artifact set and checksums in authenticated artifact storage with an explicit retention period. Confirm the PC can retrieve them before temporary artifacts expire.
5. Verify upload, Apple processing, and existing-group assignment separately. Keep the public name **Pearls by Briggs Kellogg** and avoid duplicate uploads or invitations.
6. Read actual Apple build expiration, establish the approved renewal time and notification channel, and only then activate a renewal job. The kit's approximately 60-day renewal target is a proposal; no daily renewal schedule is active.

No new services, paid capacity, repository visibility changes, or App Store publication are implied.

## Backup prerequisites and reporting

Reuse verified existing PC configuration when it becomes accessible. Broader backup jobs require an exact personal account/source allowlist, resolved paths, non-overlapping destinations, complete provider-file hydration, approved retention, and an authorized notification channel. Reject links/junctions and unknown reparse behavior; denials override allowances. Empty or ambiguous scope keeps execution disabled, and no backup pruning occurs without an explicit retention policy.

Hourly snapshots and nightly Proton uploads remain proposed, not installed schedules. Use America/Phoenix for user-facing times. Report GitHub, TestFlight, iCloud, PC archive, and Proton backup separately as VERIFIED, PENDING, BLOCKED, or NOT CONFIGURED, with evidence appropriate to each. A local source mirror is not proof of off-site upload or a restorable personal-data backup.
