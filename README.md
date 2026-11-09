# Pearls — native first version

Pearls is a focused place for notes, links, images, and files. This project contains a shared SwiftUI app for **Mac and iPhone**, a local Foundation storage package, and an iPhone share extension.

**Delivery status (November 8, 2026):** 20 core tests pass; Mac and iOS Simulator builds pass. Pearls 0.1.0 (1) is installed and launches at `/Applications/Developer/Pearls.app` on the user's Mac. The user selected TestFlight for iPhone delivery; distribution signing and App Store Connect delivery remain in progress. See [current release evidence](Release/STATUS.md).

## Project synchronization

The canonical repository is [briggskellogg/pearls](https://github.com/briggskellogg/pearls). Completed work is committed, pushed, and mirrored to the user's Proton Drive `[projects]/pearls` folder using `python3 scripts/sync-project.py --push`; `--check` verifies the GitHub commit and mirrored source hashes. Configure the destination in the ignored `.pearls-sync.local.json` as `{"destination":"/absolute/path/to/[projects]/pearls"}`. Conflicting mirror edits stop the sync. The Proton client performs the subsequent cloud upload. See [project instructions](AGENTS.md).

This workflow synchronizes project source. Each device's personal Pearls library still uses the local storage and archive-transfer behavior below.

## The first version

- Save a note or complete web address; import original images, PDFs, and other regular files.
- Browse a quiet collection grid, search saved content, and mark favorites.
- Search image text with on-device Vision recognition and extract searchable text from PDFs. Text indexing runs after the original is saved. This implementation reads up to 200 PDF pages and indexes up to 500,000 characters per original.
- Open focused details, edit notes, view images and PDFs, and share originals.
- Save to the iPhone app from the system share sheet. Captures wait safely in the shared App Group inbox until the app next opens or becomes active.
- Move items to Recently Deleted and restore them, including after relaunch.
- Export and import a `.pearlsarchive` collection containing metadata and original files, including Recently Deleted. Imports are additive and refuse conflicting versions of an existing item.

The presentation follows the supplied Bard references: PP Neue York typography, a pale neutral sidebar, a clean canvas, and generous space. Main destination icons remain filled and colored; selection adds a subdued neutral row and stronger label. Utility icons use neutral outlines. Favorites switch from an outline to a filled gold star. The supplied Pearls artwork is bundled unchanged and mechanically packaged into app icon sizes at build time.

### Scope and limits

This build stores data **on each device**. It has no automatic cross-device sync, account system, analytics, remote AI service, automatic web-page scraping, or cloud backup. Export/import provides manual transfer. Saving a link stores its address; it does not download the linked page. Documents other than supported images/PDFs are kept as original files and can be shared/opened with an appropriate app.

Originals are limited to **25 MiB each**. A complete encoded collection archive is limited to **100 MiB**, including base64 overhead. Libraries that exceed the export limit remain saved locally, but this first version cannot export them as one archive. The iPhone share extension accepts up to 10 providers per capture session and bounds shared text. Automatic image recognition depends on what Vision can read; the original is retained when recognition fails.

## Mac: build and install

Requirements: a Mac running macOS 14 or later, full Xcode with its command-line tools selected, and enough local space for an Xcode build. The local Mac build uses an ad-hoc signature and does not require a paid developer membership. It is intended for the Mac where it is built; it is not a notarized installer for general distribution.

1. Unzip this project on your Mac.
2. Run `Install-Pearls.command`, or in Terminal use:

   ```bash
   cd /path/to/PearlsNative
   bash scripts/install-mac.sh --developer
   ```

   `--developer` is the default and installs to `/Applications/Developer/Pearls.app`. Use `--user` for `~/Applications` or `--system` for `/Applications`. The command file chooses `/Applications/Developer` when `/Applications` is writable and otherwise uses your user folder. No `sudo` or automatic privilege escalation is used.

3. The installer builds the app, verifies its local signature, preserves any existing same-identity Pearls app as a timestamped backup, then installs the new app. It refuses to overwrite a different app with the same filename. Quit a running Pearls instance before installing.

The command file opens the app after a successful installation. If macOS blocks a downloaded command file, open Terminal and invoke it with `bash Install-Pearls.command`; read the script first if you want to inspect its actions.

## iPhone: Xcode and TestFlight

Open **`Pearls.xcodeproj`** and choose **`Pearls-iOS`**. The minimum supported OS is iOS 17. The project also supports iPad layouts, though the initial UI direction is centered on iPhone.

Before a signed device archive, select the correct Apple Developer team and register/provision the main app, share extension, and App Group. Proposed identifiers are:

| Component | Default identifier |
| --- | --- |
| Mac/iPhone app | `com.briggskellogg.pearls` |
| iPhone share extension | `com.briggskellogg.pearls.share` |
| Shared iPhone container | `group.com.briggskellogg.pearls` |

These are project defaults, **not a claim that identifiers have been registered**. If an identifier is unavailable, change the bundle base and group consistently in `Configuration/Local.xcconfig`; use the provided example. Never put signing keys or passwords into the project.

The iPhone app and share extension must both belong to the same registered App Group. A missing group leaves in-app saving available but causes share-sheet saving to display a configuration error. Both main apps keep their libraries in their own Application Support directory; only the iPhone capture inbox uses the App Group. Adding or changing App Group access therefore does not switch an existing collection to a different root. The local ad-hoc Mac build does not claim an unprovisioned App Group.

### Validate before distribution

```bash
bash scripts/validate-apple.sh
```

This runs the storage XCTest suite, compiles the Mac target, and compiles the iOS Simulator target without distribution signing. Then run the manual device checks in `Release/DEVICE-CHECKS.md`.

### Archive and upload

The signed release path requires current full Xcode, Apple Developer/App Store Connect access, an app record, correct signing, and an unused build number. Authenticate with Xcode's signed-in account or an App Store Connect API key as described in `Release/README.md`.

For a team already signed in to Xcode:

```bash
TEAM_ID=YOURTEAMID APPLE_AUTH_MODE=xcode-account BUILD_NUMBER=1 \
  bash scripts/prepare-testflight.sh

TEAM_ID=YOURTEAMID APPLE_AUTH_MODE=xcode-account \
  bash scripts/upload-testflight.sh "$PWD/build/ios/Pearls-TestFlight-build-1.xcarchive"
```

Replace `YOURTEAMID` with the actual 10-character team ID and use an unuploaded build number. Preparation creates a device archive, preserves the app and share extension's source entitlements, and verifies a local App Store distribution export. It does not need a registered iPhone and does not upload. Existing archive/export paths are never overwritten. `archive-ios.sh` remains available for the separate development-signing path. See `Release/STATUS.md` for the current release attempt and next step.

After upload, App Store Connect must finish processing. Assign the processed build to the appropriate TestFlight group and invite the verified tester email. An eligible App Store Connect account can use internal testing; external testing may require beta review. Neither uploading nor creating this project sends an invitation. See `Release/README.md` for verified Apple links and the exact handoff sequence.

## Project layout

| Path | Responsibility |
| --- | --- |
| `Pearls/App` | App entry point, actor-isolated repository adapter, import/export, restoration |
| `Pearls/UI` and `Pearls/Theme` | Shared Mac/iPhone screens, icon states, typography, previews |
| `Pearls/Platform` | App Group inbox, on-device text indexing, document export, bundled fonts |
| `PearlsShare` | iPhone share-sheet capture and explicit save |
| `Packages/PearlsCore` | Local store, metadata recovery, safe original-file handling, portable archives, tests |
| `Configuration` | Info plists, entitlements, shared settings; optional local team override |
| `BuildSupport` | App icon packaging and deterministic Xcode-project generator |
| `scripts` and `Release` | Mac install, validation, iPhone archive/upload, release evidence |

No third-party package download is required by this project. System frameworks include SwiftUI, Foundation, AppKit/UIKit, PDFKit, Vision, CoreText, and ImageIO. `PearlsCore` is a local Swift package.

The checked-in project can be regenerated after adding/removing source files:

```bash
python3 BuildSupport/generate-project.py
```

The generator does not compile the code. Use the Xcode checks above for actual build validation.

## Data and recovery

The store retains originals and writes versioned JSON metadata atomically. It keeps the previous valid metadata copy. If both metadata copies are unusable, it preserves the files and refuses to silently replace the collection with an empty library. An unsupported newer schema must be opened by a compatible version rather than rolled back.

Share captures use stable identities. Only the main app updates library metadata; the extension writes immutable capture folders and publishes metadata last. The main app removes a capture only after its identity has been saved, so an interrupted cleanup can be retried without duplicating it. A failed capture remains in the inbox while other independent captures can continue importing.

There is no automatic time-based purge of Recently Deleted in this first version. A full export includes those records and originals. The app currently provides restoration, not permanent deletion or automatic retention policies.

Fonts and source artwork came from the supplied identity and the user's Bard assets. Preserve their existing licensing when distributing beyond this private test project.
