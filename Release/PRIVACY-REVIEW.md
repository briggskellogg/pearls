# Privacy manifest review — Pearls 0.1

## What was inspected

Source review updated on 2026-11-08 for the System/Light/Dark appearance preference, following the earlier review of file-attribute queries. The reviewed source includes the Foundation storage package, shared app Swift files, and `PearlsShare/ShareViewController.swift`. The extension compiles that controller together with the shared `AppPaths.swift` pending-capture writer/reader. This review cannot substitute for building and inspecting the final app and embedded extension on a Mac.

The Mac/iPhone app manifest at `Pearls/Resources/PrivacyInfo.xcprivacy` declares `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1` for its own persisted appearance setting. The share extension has a separate manifest at `PearlsShare/PrivacyInfo.xcprivacy` with no required-reason APIs: it does not read that preference or use UserDefaults. Both manifests continue to declare no tracking or collected data types. The project generator assigns the correct manifest to each target.

## Observed calls and the Apple categories

| Source behavior | Observed calls | Assessment |
| --- | --- | --- |
| Bounds checks on library JSON, user-picked files, temporary copies, and capture JSON | `URL.resourceValues(forKeys:)` using `fileSizeKey` and `isRegularFileKey` | No named timestamp accessor was found. File-size metadata alone is not a blanket reason to claim every file API category. |
| Reject symlinks, verify ordinary files/directories | `isRegularFileKey`, `isDirectoryKey`, `isSymbolicLinkKey`, `contentTypeKey`, and `destinationOfSymbolicLink(atPath:)` | File validation; no explicit file timestamp query found. |
| Library creation/edit dates | `Date` values stored in the app’s own model | These model timestamps are not filesystem timestamp API calls. |
| Appearance setting | `@AppStorage("pearls.appearance")` backed by standard app UserDefaults | Persists the app’s own System/Light/Dark choice. Declared as app-only access under `CA92.1`; the app does not read system preference keys or use an App Group defaults suite. |
| App Group shared inbox | `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`, capture files in that container; main libraries remain in each app’s Application Support directory | File-based capture exchange, independent of appearance preferences. The share extension does not use `UserDefaults`, `@AppStorage`, or `@SceneStorage`. |
| Share-extension originals | `NSItemProvider` object/file/data representations, security-scoped file access, and bounded `FileHandle` reads | The extension stages originals in its temporary directory, then publishes into the App Group. No file timestamp or device-inventory accessor was found. |
| Boot time, disk capacity, keyboard inventory | None found in reviewed source | Do not add these declarations without actual use. |

Apple’s current [required-reason API reference](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) lists specific timestamp accessors and functions such as `stat`, `fstat`, `lstat`, and `getattrlist`. The inspected code does not directly name these. The previous broad `attributesOfItem(atPath:)` calls have been replaced by narrow file-size/regular-file checks and a symlink check. Framework internals and final linked dependencies have not been audited here. A source search is not evidence of App Store validation success.

## Exact reason mapping if a listed file-metadata API is used

For `NSPrivacyAccessedAPICategoryFileTimestamp`, reason `C617.1` fits metadata access within the app or App Group container. Reason `3B52.1` fits metadata access to files or directories explicitly granted by the user, such as a document-picker selection. These are separate scopes. Use only the reasons matching the actual target’s behavior.

`PrivacyInfo-file-metadata.template.xcprivacy` supplies those two entries as a **conditional template**, not as an automatically included app resource. If a final source or binary review identifies this category, merge the justified entries into that target’s real `PrivacyInfo.xcprivacy`; preserve all other legitimate declarations. Ensure both app and share extension include their respective manifest resources. Do not add the template as a second manifest or assert that every target has the same use.

Apple’s current reference maps `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1` to reading and writing data accessible only to the app. This covers the stored appearance choice. System appearance is inherited through SwiftUI rather than reading system UserDefaults keys. Reason `1C8F.1` would cover defaults shared among App Group members; it is not declared because the capture exchange uses files and the appearance preference is app-only.

## Release check

On a Mac, inspect the final target sources and dependencies, archive Pearls, generate the Xcode privacy report, and verify the app/extension manifests included in the archive. Reconcile any App Store Connect required-reason notice with the actual use and an approved reason before resubmission. Privacy manifests and App Store Connect privacy/compliance answers are separate requirements; neither proves the other is complete.
