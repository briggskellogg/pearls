# Pearls release status

**Pearls 0.1.0 build 6** uses committed source `e87c5052ec94fda8d5172978e221fbb58f0d0ff7`. It separates the supplied symbol and PP Neue Montreal name, places the gold maker mark in a lower corner, supplies transparent Mac/opaque iOS icons, and corrects phone-header intrinsic sizing. The original master artwork is retained.

Build 6 uploaded once at **2026-11-08T22:01:40.085-07:00** and is **processed and assigned to Briggs Internal (one tester)**. Testing notes: saved. The existing tester invitation is retained. Physical iPhone installation is unverified.

| Check | Build 6 evidence |
| --- | --- |
| Core tests | 36 passed |
| Python publication checks | 40 passed |
| Native compilation | Final build 6 Mac Release build, Mac/iOS typechecks and iOS Simulator compilation passed |
| Icon packaging | All 28 icon slots and transparency/opacity checks passed during build 5; the same icon pipeline/assets are retained in build 6 |
| Mac installation/runtime | Mac Release build 6 installed at /Applications/Developer/Pearls.app; reopened Settings confirms 0.1.0 (6), persisted System appearance, and retained private-folder connection controls |
| Phone simulator | Intrinsic header sizing correction visually confirmed on iPhone simulator |
| Signed archive/export | Build 6 archive/export and app/share-extension signatures/profiles verified from clean source e87c5052ec94fda8d5172978e221fbb58f0d0ff7 |
| GitHub package | [Five release files present; server digests match the local package](https://github.com/briggskellogg/pearls/releases/tag/v0.1.0-build.6) |
| CI | [Passed](https://github.com/briggskellogg/pearls/actions/runs/42564687485) |

The five-file package is `build/releases/Pearls-0.1.0-build-6/`: IPA, dSYMs ZIP, archive ZIP, manifest and SHA256SUMS. App and packaging source both match `e87c5052ec94fda8d5172978e221fbb58f0d0ff7`; exact fingerprints are in `release-target.json`. No personal library or signing keys are included. PC retrieval/restoration remains unverified.

## Build 5 withheld

Build 5 uploaded once on November 8, 2026 at **21:54:33.660 America/Phoenix** and completed processing as `68395c57-e249-4efc-ad77-492087e032a2`, but was not assigned to Briggs after simulator QA found compressed phone-header text. Zero invitations were confirmed. Build 6 supersedes it. Build 5 passed 36 core and 40 Python tests, native Mac/iOS compilation, all 28 icon slots and alpha/opacity checks, and Mac Light/Dark QA with System restored; these are historical checks, not substitutes for the final build 6 results above.

## Private content boundary

The existing private iCloud Drive/Pearls connection and per-device bookmark are unchanged. Build 4 initialized an empty collection; provider metadata confirmed upload of its empty `pearls-sync.json` marker. This does not verify saved-content transfer, physical iPhone behavior, or PC access. No personal library migration or Proton personal-library backup is claimed. Project-source mirrors and public release assets exclude saved contents. See `PRIVATE-SYNC-SETUP.md`.

## Source synchronization

Source `e87c5052ec94fda8d5172978e221fbb58f0d0ff7` mirrored: 97 files. Exact e87c505 source snapshot check passed for 97 files. Native Proton client showed finished upload entries for the source receipt, install-mac.sh, PearlsTheme.swift, provenance, and branding assets. This records that source snapshot; subsequent documentation receipts are verified by the final sync check.

Client upload confirmation is not a remote restore test. After recording final delivery, commit the receipt updates, run `sync-project.py --push` and `--check`, and verify the Proton client completion state. Do not repeat successful uploads or send duplicate invitations.

## Previous verified releases

- Build 4: app source `0238e69f33454c90bf13f0677e68c52d923f4a50`, packaging source `0238e69f33454c90bf13f0677e68c52d923f4a50`; [retained release](https://github.com/briggskellogg/pearls/releases/tag/v0.1.0-build.4). Complete release evidence remains in `release-target.json`.
- Build 3: app source `2f31ec48b07b24c5343a163e5f5cd4022c686d3a`, packaging source `4ad802bcb549ac0fe31abeb80ebe51242f3f5d0e`; [retained release](https://github.com/briggskellogg/pearls/releases/tag/v0.1.0-build.3). Complete release evidence remains in `release-target.json`.

Builds 1 and 2 remain earlier verified releases; their detailed history remains in earlier committed release documentation. App Store Connect identity, Apple team, bundle IDs, Briggs group, privacy restrictions, and prior backup limits are unchanged.
