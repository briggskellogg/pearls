# Privacy manifest review — Pearls 0.1

## What was inspected

Source review updated on 2026-11-08 for the per-device iCloud folder bookmark and appearance preference, following the earlier review of file-attribute queries. The reviewed source includes the Foundation storage and immutable-file sync package, shared app Swift files, and `PearlsShare/ShareViewController.swift`. The extension compiles that controller together with the shared `AppPaths.swift` pending-capture writer/reader. This review cannot substitute for building and inspecting the final app and embedded extension on a Mac.

The Mac/iPhone app manifest at `Pearls/Resources/PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` for its own appearance setting and security-scoped folder bookmark. No new reason is needed for the additional app-only preference. The share extension has a separate manifest at `PearlsShare/PrivacyInfo.xcprivacy` with no required-reason APIs: it does not read these preferences or use UserDefaults. Both manifests continue to declare no tracking or collected data types. The project generator assigns the correct manifest to each target.

## Observed calls and the Apple categories

| Source behavior | Observed calls | Assessment |
| --- | --- | --- |
| Bounds checks on library JSON, user-picked files, temporary copies, and capture JSON | `URL.resourceValues(forKeys:)` using `fileSizeKey` and `isRegularFileKey` | No named timestamp accessor was found. File-size metadata alone is not a blanket reason to claim every file API category. |
| Reject symlinks, verify ordinary files/directories | `isRegularFileKey`, `isDirectoryKey`, `isSymbolicLinkKey`, `contentTypeKey`, and `destinationOfSymbolicLink(atPath:)` | File validation; no explicit file timestamp query found. |
| Library creation/edit dates | `Date` values stored in the app’s own model | These model timestamps are not filesystem timestamp API calls. |
| Appearance setting | `@AppStorage("pearls.appearance")` backed by standard app UserDefaults | Persists the app’s own System/Light/Dark choice. Declared as app-only access under `CA92.1`; the app does not read system preference keys or use an App Group defaults suite. |
| Device-local folder connection | Standard `UserDefaults.data`, `set`, and `removeObject` for `pearls.sync.folder.v1` | Stores only the app’s security-scoped bookmark to the explicitly picked folder. The bookmark is not sent through sync, exports, the App Group, GitHub, or the source mirror. The same `CA92.1` reason applies. |
| Private iCloud folder exchange | User-selected folder URL; bookmark creation/resolution; balanced scoped access; `NSFileCoordinator`; narrow ubiquitous-item sharing, conflict, download, and upload resource keys | Sync reads/writes only the selected dedicated folder and the app’s local library/cache. The inspected calls do not request filesystem timestamps, disk capacity, or device inventory. Provider metadata checks distinguish local writes from reported uploads. |
| App Group shared inbox | `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`, capture files in that container; main libraries remain in each app’s Application Support directory | File-based capture exchange, independent of appearance preferences. The share extension does not use `UserDefaults`, `@AppStorage`, or `@SceneStorage`. |
| Share-extension originals | `NSItemProvider` object/file/data representations, security-scoped file access, and bounded `FileHandle` reads | The extension stages originals in its temporary directory, then publishes into the App Group. No file timestamp or device-inventory accessor was found. |
| Boot time, disk capacity, keyboard inventory | None found in reviewed source | Do not add these declarations without actual use. |

Apple’s current [required-reason API reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) lists specific timestamp accessors and functions such as `stat`, `fstat`, `lstat`, and `getattrlist`. The inspected code does not directly name these. The previous broad `attributesOfItem(atPath:)` calls have been replaced by narrow file-size/regular-file checks and a symlink check. Framework internals and final linked dependencies have not been audited here. A source search is not evidence of App Store validation success.

## Exact reason mapping if a listed file-metadata API is used

For `NSPrivacyAccessedAPICategoryFileTimestamp`, reason `C617.1` fits metadata access within the app or App Group container. Reason `3B52.1` fits metadata access to files or directories explicitly granted by the user, such as a document-picker selection. These are separate scopes. Use only the reasons matching the actual target’s behavior.

`PrivacyInfo-file-metadata.template.xcprivacy` supplies those two entries as a **conditional template**, not as an automatically included app resource. If a final source or binary review identifies this category, merge the justified entries into that target’s real `PrivacyInfo.xcprivacy`; preserve all other legitimate declarations. Ensure both app and share extension include their respective manifest resources. Do not add the template as a second manifest or assert that every target has the same use.

Apple’s current reference maps `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` to reading and writing data accessible only to the app. This covers the stored appearance choice and the per-device folder bookmark. System appearance is inherited through SwiftUI rather than reading system UserDefaults keys. Reason `1C8F.1` would cover defaults shared among App Group members; it is not declared because capture exchange uses files and these preferences are app-only.

The optional sync feature writes the user’s saved content to their own selected private iCloud Drive folder; it adds no developer-operated service, analytics, or third-party data recipient. This is distinct from the app-only UserDefaults access reason. Apple’s [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) distinguishes data collected by the developer or its partners from data collected by Apple. Reassess the collection declarations if the app later adds developer access, telemetry, a server, or another recipient. Do not describe the runtime dataset as public source, a completed backup, or end-to-end encrypted based only on this manifest.

Both Mac signing templates, `Configuration/Pearls-Mac.entitlements` and `Release/Pearls-Local-Mac.entitlements`, include user-selected read/write access and `com.apple.security.files.bookmarks.app-scope`. The local Mac build script selects the latter template. Verify the entitlements on the actual installed app as well as the project configuration; persistent folder access must survive relaunch. iOS retains access through document-picker bookmarks and does not use the Mac-only bookmark option.

## Release check

On a Mac, inspect the final target sources and dependencies, archive Pearls, generate the Xcode privacy report, and verify the app/extension manifests included in the archive. Reconcile any App Store Connect required-reason notice with the actual use and an approved reason before resubmission. Privacy manifests and App Store Connect privacy/compliance answers are separate requirements; neither proves the other is complete.
