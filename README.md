# Pearls — native first version

Pearls is a focused place for notes, links, images, and files. This project contains a shared SwiftUI app for **Mac and iPhone**, a local Foundation storage package, and an iPhone share extension.

**Delivery status (November 8, 2026):** Pearls 0.1.0 build 4 is installed at `/Applications/Developer/Pearls.app`; Settings shows build 4 and the System appearance choice is preserved. All 36 core tests, 40 publication-safety tests, Mac builds, and iOS Simulator compilation pass. The signed iPhone archive/export is verified, and its upload succeeded once at 9:31:11 PM Phoenix. Apple processing completed, and build 4 is assigned to the existing Briggs Internal group with one tester. The [build 4 prerelease](https://github.com/briggskellogg/pearls/releases/tag/v0.1.0-build.4) retains five verified release files at source `0238e69f33454c90bf13f0677e68c52d923f4a50`. Build 4 is available through TestFlight; physical iPhone installation remains unverified. See [current release evidence](Release/STATUS.md).

**Private content sync is connected on the Mac:** iPhone and Mac can exchange changes through the same user-selected private iCloud Drive Pearls folder while the app is active, keeping local content available offline. The dedicated iCloud Drive/Pearls folder is connected and an empty collection is initialized. Settings reports 0 sent/received updates, and iCloud provider metadata confirms the empty collection marker uploaded. No personal content or live cross-device transfer has been verified. Windows can access JSON records and original files through iCloud for Windows; there is no native Windows Pearls editor. Follow the [private sync setup guide](Release/PRIVATE-SYNC-SETUP.md).

## Project synchronization

The canonical repository is [briggskellogg/pearls](https://github.com/briggskellogg/pearls). Completed work is committed, pushed, and mirrored to the user's Proton Drive `[projects]/pearls` folder using `python3 scripts/sync-project.py --push`; `--check` verifies the GitHub commit and mirrored source hashes. Configure the destination in the ignored `.pearls-sync.local.json` as `{"destination":"/absolute/path/to/[projects]/pearls"}`. Conflicting mirror edits stop the sync. The Proton client performs the subsequent cloud upload. See [project instructions](AGENTS.md).

This workflow synchronizes project source only. Personal saved content is excluded from GitHub and the Proton project-source mirror. Build 4's optional private iCloud folder is a separate destination, chosen inside the app; build 3 still uses local storage and manual archive transfer.

The adopted [release prompt](RELEASE_PROMPT.txt) and [destination map](project-destinations.json) retain the user's explicit public-repository and scoped Pearls-source-mirror permissions. These files do not connect a personal iCloud folder or activate broader backups. The user reports the PC setup is ready, but its archive and restore results are not accessible here. The [personal app system handoff](Release/PERSONAL-APP-SYSTEM.md) records the exact remaining work without treating it as configured.

## The first version

- Save a note or complete web address; import original images, PDFs, and other regular files.
- Browse a quiet collection grid, search saved content, and mark favorites.
- Search image text with on-device Vision recognition and extract searchable text from PDFs. Text indexing runs after the original is saved. This implementation reads up to 200 PDF pages and indexes up to 500,000 characters per original.
- Open focused details, edit notes, view images and PDFs, and share originals.
- Save to the iPhone app from the system share sheet. Captures wait safely in the shared App Group inbox until the app next opens or becomes active.
- Move items to Recently Deleted and restore them, including after relaunch.
- Choose System, Light, or Dark in Settings. The choice is saved on each device; System is the default and follows that device's current appearance.
- Export and import a `.pearlsarchive` collection containing metadata and original files, including Recently Deleted. Imports are additive and refuse conflicting versions of an existing item.

The presentation follows the supplied Bard references: PP Neue Montreal for interface controls and brand text, PP Neue York for headings and saved-note reading, a neutral sidebar, a clean canvas, and generous space. Five font files are bundled: Montreal Regular and Bold, plus Neue York Normal Light, Medium, and Extrabold. Main destination icons remain filled and colored; selection adds a subdued neutral row and stronger label. Utility icons use neutral outlines. Favorites switch from an outline to a filled gold star. The supplied Pearls artwork is bundled unchanged and mechanically packaged into app icon sizes at build time.

### Scope and limits

The released build 3 stores data **on each device**, with manual archive import/export. Build 4 keeps that offline library and adds optional private iCloud folder exchange; it does not make GitHub a data backend or add a native Windows editor. Sync checks require Pearls to be open and active, and provider upload/download completion is separate from a local merge. No account system, analytics, remote AI service, automatic web-page scraping, or Proton personal-library backup is configured. Saving a link stores its address; it does not download the linked page. Documents other than supported images/PDFs are kept as original files and can be shared/opened with an appropriate app.

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
