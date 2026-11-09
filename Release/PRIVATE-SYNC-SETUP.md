# Private saved-content sync — build 4

Build 4 is installed on the Mac; 36 core tests and both platform compilations pass. The iPhone upload completed processing, and build 4 is assigned to Briggs Internal in TestFlight; physical installation remains unverified. The Mac is connected to the dedicated private **iCloud Drive/Pearls** folder, and its empty collection is initialized. At 9:33 PM Phoenix on November 8, Settings showed 0 pearls, 0 updates sent/received, and **Waiting for iCloud to upload**. A subsequent read-only provider metadata check confirmed `pearls-sync.json` uploaded successfully. That proves upload of the empty marker only: no personal content has been migrated and live iPhone/Mac/Windows delivery remains unverified. The access bookmark is stored per device.

Folder selection succeeded after the user restored foreground interaction. Reuse this exact connected folder on the phone; do not create a second independent collection.

## Choose the same private folder on iPhone and Mac

After installing a build that includes this feature:

1. Use your intended personal iCloud account on both Apple devices. In iCloud Drive, create a dedicated, empty folder named **Pearls**, or reuse the folder already created by Pearls sync. Keep it private and unshared.
2. In Pearls, open **Settings → Private iCloud folder → Choose iCloud folder…** and select that folder. Choosing it connects the local collection and starts a sync check.
3. Repeat on the other Apple device, selecting the **same** iCloud Drive folder. Do not create a second independent folder with the same name.
4. Leave Pearls open and active with an internet connection while iCloud exchanges files. Use **Sync now** when needed and inspect the sync/provider status. Saving locally or completing a local merge does not prove that another device has received the change.
5. Verify a small note and an original attachment cross devices, then quit/reopen Pearls and check them again. This verification is still outstanding for the user's devices.

Use the private iCloud Drive folder, not the Git checkout or Proton Drive `[projects]/pearls`. The latter holds public project source. The app rejects project/backup locations, folders shared with other people, and unrelated existing contents. Access is saved per device; use **Reconnect…** if iCloud or file-picker access changes.

## Offline use, conflicts, and disconnecting

Each device retains its local working collection while offline. When the selected folder is accessible and Pearls is active, the app checks for changes again. It does not promise continuous background execution on a closed or suspended iPhone app.

The private folder stores a collection marker (`pearls-sync.json`), immutable JSON versions under `versions/`, and original bytes under `originals/`. Treat these as app-managed personal data. Review any conflict or incomplete-download notice in Pearls; do not edit protocol files to resolve it. The feature's real cross-device behavior still requires verification.

**Disconnect** removes this device's saved connection. It preserves both the local collection and files already in iCloud Drive. Deleting the cloud folder, version history, or original files is not a safe reset or storage-pruning procedure. No automatic historical pruning or Proton library backup has been configured.

## Windows access

With iCloud for Windows configured for the same personal Apple Account, the PC can download the same private folder through File Explorer's iCloud Drive. Follow [Apple's iCloud for Windows setup instructions](https://support.apple.com/en-gb/118443) and [iCloud Drive guide](https://support.apple.com/en-gb/guide/icloud/mm203b05aec8/1.0/icloud). The folder contains readable JSON metadata and original attachments; it is not a Windows application or a native Pearls editing interface. Use Pearls on iPhone/Mac for edits, and keep the app-managed files unchanged on Windows.

Complete downloads before inspecting or archiving files. A cloud placeholder is not the file's contents. This chat has not verified the PC's iCloud configuration, downloads, archive destination, or restoration. The source/release archive plan in `PERSONAL-APP-SYSTEM.md` is separate from live library sync.

## Keep personal content out of public source

Never put the private folder, `.pearlsarchive` exports, library metadata, originals, or saved notes into GitHub, GitHub release assets, or the Proton project-source mirror. Source and release publication guards reject recognized Pearls documents, private trees, signing/local secrets, and private data hidden inside ZIP inputs; source synchronization also checks reachable Git history. These checks are an additional safeguard, not permission to stage personal files for publication.

No CloudKit database or app-specific CloudKit credentials are used by this folder-based design. iCloud Drive carries the user-selected files. Do not describe the feature as an independently verified backup, remote restore, or end-to-end encryption system.
