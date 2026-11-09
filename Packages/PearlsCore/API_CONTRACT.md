# PearlsCore integration contract

**Stable public API — root app can integrate now.** Pure Foundation, synchronous, Swift 5.9; macOS 14 / iOS 17. `PearlStore` is thread safe within one instance; Apple platforms additionally coordinate file access. An app actor may own it. Share extension writes a separate pending inbox; the app alone owns repository writes.

```swift
let store = try PearlStore(rootDirectory: suppliedDirectory)
let allIncludingTrash = try store.refresh() // load() is an alias
let visible = try store.search("word", favoritesOnly: false, kind: nil)
let alreadyImported = try store.contains(id: captureID)
let existing = try store.item(id: captureID) // Pearl?

let note = try store.addNote(title: "Idea", text: "Body", tags: [],
                             id: captureID, createdAt: captureDate)
let link = try store.addLink(url: sourceURL, title: "Reference", text: "", tags: [],
                             id: captureID, createdAt: captureDate)
let file = try store.addAttachment(
    from: scopedURL, kind: .image, title: "", text: "", sourceURL: nil,
    tags: [], ocrText: "", contentType: "public.jpeg", originalFilename: "Photo.jpg",
    id: captureID, createdAt: captureDate
)
// id and createdAt are optional defaults on all three creates.
// originalFilename is an optional override; default is the source's actual filename.
// A duplicate UUID throws itemAlreadyExists: check contains before retrying ingestion.

var edit = note
edit.title = "Updated"
edit.text = "Thought"
edit.tags = ["Design"]
edit.ocrText = "On-device OCR supplied by the app"
let saved = try store.save(edit)
let favorite = try store.setFavorite(true, for: saved.id)
try store.softDelete(id: saved.id)
try store.restore(id: saved.id)
let originalURL = try store.attachmentURL(for: file) // URL?
let archiveData = try store.exportArchive() // Data for FileDocument
let result = try store.importArchive(archiveData) // importedCount, skippedCount, repairedCount
```

- `PearlKind`: `.note`, `.link`, `.image`, `.file`; `String`, `Codable`, `CaseIterable`, `Hashable`, `Sendable`.
- `Pearl`: `Identifiable`, `Codable`, `Equatable`, `Sendable`. `id`, `kind`, `createdAt`, `attachment` immutable. Mutable `title`, `text`, `sourceURL: URL?`, `tags: [String]`, `ocrText`, `isFavorite`, `updatedAt`, `deletedAt: Date?`. Computed `isDeleted`, `originalFilename: String?`, `attachmentRelativePath: String?`.
- `PearlAttachment`: immutable `relativePath`, `originalFilename`, `contentType: String?`, `byteCount: Int64`.
- `PearlSearch.results(in:query:favoritesOnly:kind:includeDeleted:)` is also available as a pure function. Default filters hide deleted records. `refresh()` deliberately includes them for Trash UI.
- Search covers title, body, original name, source URL, tags and OCR, requires every query token, folds case/diacritics, sorts newest-first with UUID tie-breaker.
- Stable creation ID and date preserve share-capture identity. Millisecond dates are stored. Root must keep security-scoped permission open through the synchronous attachment copy.
- **25 MiB per original; 100 MiB encoded archive**. `PearlStore.maximumAttachmentBytes`, `maximumArchiveBytes`, `archiveFileExtension` public constants. `.pearlsarchive` JSON embeds original bytes as base64 and includes Trash.
- Imports are additive, idempotent for exact identical records, and reject conflicting versions of the same UUID before committing anything. An identical record whose original is missing can be repaired from an archive; a present but changed original is never replaced. `repairedCount` reports repaired records separately from `skippedCount`. `PearlImportResult.init(importedCount:skippedCount:repairedCount:)` defaults `repairedCount` to zero.
- Metadata commits retain `library.previous.json`. On malformed metadata, recover from a valid backup, preserve damaged primary under `Recovery/`, and publish optional `store.recoveryNotice` with message/count/URL. Header versions are checked before decoding items. Unsupported versions in either the primary or recovery copy throw without replacing either. No originals are purged.
- The app provides the Application Support/app-group root. Core does no entitlement lookup, networking, automatic OCR, or cross-device sync.

Status: implementation and 20 XCTest cases compiled and passed on the user's Mac with Xcode 27.2 on November 8, 2026.

Privacy API audit: core reads file size and regular-file status with `URL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])`. Symlink protection uses `resolvingSymlinksInPath()` and `FileManager.destinationOfSymbolicLink(atPath:)`. It does not call `attributesOfItem`, read filesystem creation/modification timestamps, read disk capacity, use UserDefaults, read system uptime, or inspect keyboard settings. Model timestamps come from `Date()` or caller-supplied capture dates. Audit the complete application separately when preparing its privacy manifest.
