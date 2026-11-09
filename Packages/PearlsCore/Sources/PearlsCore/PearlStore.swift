import Foundation

/// A synchronous store. Use a background queue for bulk work; use `refresh()` after inbox ingestion.
/// All mutation transactions reload current metadata before writing. Apple file coordination also
/// protects cooperating store instances. No network, cloud account, or cross-device sync is implied.
public final class PearlStore: @unchecked Sendable {
    public static let maximumAttachmentBytes: Int64 = 25 * 1024 * 1024
    public static let maximumArchiveBytes = 100 * 1024 * 1024
    public static let archiveFileExtension = "pearlsarchive"
    public static let manifestFilename = "library.json"
    public static let backupFilename = "library.previous.json"
    private static let maximumMetadataBytes = 32 * 1024 * 1024

    public let rootDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var lastRecoveryNotice: PearlRecoveryNotice?

    private var manifestURL: URL { rootDirectory.appendingPathComponent(Self.manifestFilename) }
    private var backupURL: URL { rootDirectory.appendingPathComponent(Self.backupFilename) }
    private var originalsDirectory: URL { rootDirectory.appendingPathComponent("attachments", isDirectory: true) }

    public var recoveryNotice: PearlRecoveryNotice? {
        lock.lock()
        defer { lock.unlock() }
        return lastRecoveryNotice
    }

    public init(rootDirectory: URL) throws {
        guard rootDirectory.isFileURL else { throw PearlStoreError.fileURLRequired }
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        try withCoordinatedAccess {
            try ensureSafeDirectory(originalsDirectory)
            _ = try readLibrary()
        }
    }

    /// Includes soft-deleted records so a Trash view can offer restoration.
    public func refresh() throws -> [Pearl] {
        try withCoordinatedAccess { try readLibrary().items.sorted(by: PearlSearch.newestFirst) }
    }

    public func load() throws -> [Pearl] { try refresh() }

    public func search(_ query: String, favoritesOnly: Bool = false, kind: PearlKind? = nil, includeDeleted: Bool = false) throws -> [Pearl] {
        PearlSearch.results(in: try refresh(), query: query, favoritesOnly: favoritesOnly, kind: kind, includeDeleted: includeDeleted)
    }

    public func item(id: UUID) throws -> Pearl? {
        try withCoordinatedAccess { try readLibrary().items.first { $0.id == id } }
    }

    /// Useful for idempotent share-inbox ingestion. Keep the capture UUID until this returns true.
    public func contains(id: UUID) throws -> Bool { try item(id: id) != nil }

    @discardableResult
    public func addNote(title: String = "", text: String, tags: [String] = [], id: UUID = UUID(), createdAt: Date = Date()) throws -> Pearl {
        let now = Self.timestamp(createdAt)
        let pearl = Pearl(id: id, kind: .note, title: Self.title(title, fallback: "Untitled note"), text: text, tags: Self.normalizedTags(tags), createdAt: now)
        return try insertNew(pearl)
    }

    @discardableResult
    public func addLink(url: URL, title: String = "", text: String = "", tags: [String] = [], id: UUID = UUID(), createdAt: Date = Date()) throws -> Pearl {
        try Self.validateSourceURL(url)
        let now = Self.timestamp(createdAt)
        let pearl = Pearl(id: id, kind: .link, title: Self.title(title, fallback: url.host ?? "Saved link"), text: text, sourceURL: url, tags: Self.normalizedTags(tags), createdAt: now)
        return try insertNew(pearl)
    }

    /// The caller must keep any security-scoped permission active until this synchronous copy returns.
    /// A supplied stable ID allows interrupted inbox captures to be checked using `contains(id:)`.
    @discardableResult
    public func addAttachment(
        from fileURL: URL,
        kind: PearlKind,
        title: String = "",
        text: String = "",
        sourceURL: URL? = nil,
        tags: [String] = [],
        ocrText: String = "",
        contentType: String? = nil,
        originalFilename: String? = nil,
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) throws -> Pearl {
        guard fileURL.isFileURL else { throw PearlStoreError.fileURLRequired }
        guard kind == .image || kind == .file else { throw PearlStoreError.invalidItem("Only images and files can have an original attachment.") }
        if let sourceURL { try Self.validateSourceURL(sourceURL) }
        let source = fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let resourceValues = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard resourceValues.isRegularFile == true, let fileSize = resourceValues.fileSize else {
            throw PearlStoreError.invalidItem("Choose a regular file.")
        }
        let byteCount = Int64(fileSize)
        guard byteCount <= Self.maximumAttachmentBytes else { throw PearlStoreError.attachmentTooLarge(byteCount) }
        let filename = originalFilename ?? source.lastPathComponent
        guard !filename.isEmpty else { throw PearlStoreError.invalidItem("The original filename is missing.") }
        let relativePath = "attachments/\(id.uuidString.lowercased())/\(Self.safeFilename(filename))"
        let attachment = PearlAttachment(relativePath: relativePath, originalFilename: filename, contentType: contentType, byteCount: byteCount)
        let now = Self.timestamp(createdAt)
        let pearl = Pearl(id: id, kind: kind, title: Self.title(title, fallback: filename), text: text, sourceURL: sourceURL, tags: Self.normalizedTags(tags), ocrText: ocrText, createdAt: now, attachment: attachment)

        return try withCoordinatedAccess {
            var document = try readLibrary()
            guard !document.items.contains(where: { $0.id == id }) else { throw PearlStoreError.itemAlreadyExists(id) }
            try validate(pearl)
            document.items.append(pearl)
            let manifestData = try encodedLibrary(document)
            let destination = try safeOriginalURL(relativePath: relativePath, itemID: id)
            let created = try copyOriginal(from: source, to: destination, expectedBytes: byteCount)
            do {
                try commit(manifestData)
                return pearl
            } catch {
                if created { try? fileManager.removeItem(at: destination) }
                throw error
            }
        }
    }

    /// Saves metadata only. Existing originals and creation dates are preserved.
    /// For a new UUID this accepts notes and links; use `addAttachment` for originals.
    @discardableResult
    public func save(_ pearl: Pearl) throws -> Pearl {
        try withCoordinatedAccess {
            var document = try readLibrary()
            let index = document.items.firstIndex { $0.id == pearl.id }
            let existing = index.map { document.items[$0] }
            if let existing {
                guard existing.kind == pearl.kind, existing.attachment == pearl.attachment else { throw PearlStoreError.immutableAttachment }
            } else if pearl.attachment != nil {
                throw PearlStoreError.immutableAttachment
            }
            let createdAt = existing?.createdAt ?? Self.timestamp(pearl.createdAt)
            let updatedAt = max(createdAt, Self.timestamp())
            let stored = Pearl(
                id: pearl.id, kind: pearl.kind,
                title: Self.title(pearl.title, fallback: Self.defaultTitle(for: pearl.kind)),
                text: pearl.text, sourceURL: pearl.sourceURL, tags: Self.normalizedTags(pearl.tags),
                ocrText: pearl.ocrText, isFavorite: pearl.isFavorite, createdAt: createdAt,
                updatedAt: updatedAt, deletedAt: pearl.deletedAt.map(Self.timestamp), attachment: existing?.attachment
            )
            try validate(stored)
            if let index { document.items[index] = stored } else { document.items.append(stored) }
            try commit(try encodedLibrary(document))
            return stored
        }
    }

    @discardableResult
    public func setFavorite(_ favorite: Bool, for id: UUID) throws -> Pearl {
        try mutate(id: id) { $0.isFavorite = favorite }
    }

    public func softDelete(id: UUID) throws {
        _ = try mutate(id: id) { item in
            if item.deletedAt == nil { item.deletedAt = Self.timestamp() }
        }
    }

    public func restore(id: UUID) throws {
        _ = try mutate(id: id) { $0.deletedAt = nil }
    }

    /// Atomically compares an editor's baseline before saving. A concurrent
    /// update/deletion is retained and the user's draft becomes a separate note.
    @discardableResult
    public func saveNoteDraft(id: UUID, title: String, text: String, originalTitle: String, originalText: String) throws -> Pearl {
        try withCoordinatedAccess {
            var document = try readLibrary()
            let index = document.items.firstIndex { $0.id == id }
            let existing = index.map { document.items[$0] }
            let stored: Pearl
            if var current = existing, current.kind == .note, !current.isDeleted,
               current.title == originalTitle, current.text == originalText {
                current.title = Self.title(title, fallback: "Untitled note")
                current.text = text
                current.updatedAt = max(current.createdAt, Self.timestamp())
                stored = current
                document.items[index!] = current
            } else {
                stored = Pearl(kind: .note, title: Self.title(title, fallback: "Untitled note") + " (edit copy)",
                               text: text, createdAt: Self.timestamp())
                document.items.append(stored)
            }
            try validate(stored)
            try commit(try encodedLibrary(document))
            return stored
        }
    }

    /// Original bytes remain available for deleted records so restoring never requires a download.
    public func attachmentURL(for pearl: Pearl) throws -> URL? {
        try withCoordinatedAccess {
            guard let attachment = pearl.attachment else { return nil }
            let url = try safeOriginalURL(relativePath: attachment.relativePath, itemID: pearl.id)
            try validateOriginal(at: url, attachment: attachment)
            return url
        }
    }

    /// A single JSON document with base64 originals. Includes deleted records and their originals.
    public func exportArchive() throws -> Data {
        try withCoordinatedAccess {
            let items = try readLibrary().items.sorted(by: PearlSearch.newestFirst)
            var payloads: [PearlArchiveAttachment] = []
            // Check encoded sizes before loading originals. The final exact encoded size is also checked.
            var estimatedSize = try PearlDocumentCoding.encoder().encode(PearlArchiveDocument(items: items, attachments: [])).count
            for item in items {
                guard let attachment = item.attachment else { continue }
                let encodedBytes = ((attachment.byteCount + 2) / 3) * 4
                guard encodedBytes <= Int64(Self.maximumArchiveBytes - estimatedSize) else { throw PearlStoreError.archiveTooLarge }
                estimatedSize += Int(encodedBytes) + attachment.relativePath.utf8.count + 1024
                guard estimatedSize <= Self.maximumArchiveBytes else { throw PearlStoreError.archiveTooLarge }
                let url = try safeOriginalURL(relativePath: attachment.relativePath, itemID: item.id)
                try validateOriginal(at: url, attachment: attachment)
                let data = try Data(contentsOf: url)
                guard Int64(data.count) == attachment.byteCount else { throw PearlStoreError.attachmentSizeMismatch(attachment.originalFilename) }
                payloads.append(PearlArchiveAttachment(itemID: item.id, relativePath: attachment.relativePath, data: data))
            }
            let data = try PearlDocumentCoding.encoder().encode(PearlArchiveDocument(items: items, attachments: payloads))
            guard data.count <= Self.maximumArchiveBytes else { throw PearlStoreError.archiveTooLarge }
            return data
        }
    }

    /// All-or-nothing additive import. Same-ID conflicts leave this library unchanged.
    /// Identical records/originals are skipped. An identical record with a missing original
    /// can be repaired from the archive; a present but different original is never replaced.
    @discardableResult
    public func importArchive(_ data: Data) throws -> PearlImportResult {
        guard data.count <= Self.maximumArchiveBytes else { throw PearlStoreError.archiveTooLarge }
        let archive: PearlArchiveDocument
        do { archive = try PearlDocumentCoding.decoder().decode(PearlArchiveDocument.self, from: data) }
        catch { throw PearlStoreError.invalidArchive("The JSON or embedded file data is not valid.") }
        guard archive.format == "com.pearls.archive" else { throw PearlStoreError.invalidArchive("The format identifier is not recognized.") }
        guard archive.schemaVersion == 1 else { throw PearlStoreError.unsupportedSchema(archive.schemaVersion) }
        try validateItems(archive.items)
        var payloads: [UUID: PearlArchiveAttachment] = [:]
        for payload in archive.attachments {
            guard payloads[payload.itemID] == nil else { throw PearlStoreError.invalidArchive("An original appears more than once.") }
            guard Int64(payload.data.count) <= Self.maximumAttachmentBytes else { throw PearlStoreError.attachmentTooLarge(Int64(payload.data.count)) }
            payloads[payload.itemID] = payload
        }
        let expectedIDs = Set(archive.items.filter { $0.attachment != nil }.map(\.id))
        guard Set(payloads.keys) == expectedIDs else { throw PearlStoreError.invalidArchive("Original files are missing or unreferenced.") }
        for item in archive.items {
            guard let attachment = item.attachment, let payload = payloads[item.id] else { continue }
            guard payload.relativePath == attachment.relativePath, Int64(payload.data.count) == attachment.byteCount else {
                throw PearlStoreError.invalidArchive("An embedded original does not match its metadata.")
            }
        }

        return try withCoordinatedAccess {
            var document = try readLibrary()
            let existingByID = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0) })
            var newItems: [Pearl] = []
            var repairs: [(Pearl, PearlArchiveAttachment)] = []
            var skippedCount = 0
            // Resolve every conflict before writing any new original or manifest.
            for item in archive.items {
                if let existing = existingByID[item.id] {
                    guard existing == item else { throw PearlStoreError.archiveConflict(item.id) }
                    if let payload = payloads[item.id], let attachment = item.attachment {
                        let url = try safeOriginalURL(relativePath: attachment.relativePath, itemID: item.id)
                        if !fileManager.fileExists(atPath: url.path) {
                            repairs.append((item, payload))
                            continue
                        }
                        try validateOriginal(at: url, attachment: attachment)
                        guard try Data(contentsOf: url) == payload.data else { throw PearlStoreError.archiveConflict(item.id) }
                    }
                    skippedCount += 1
                } else { newItems.append(item) }
            }
            guard !newItems.isEmpty || !repairs.isEmpty else {
                return PearlImportResult(importedCount: 0, skippedCount: skippedCount)
            }
            document.items.append(contentsOf: newItems)
            // Restoring missing bytes does not change the saved records or rotate their backup.
            let manifestData: Data?
            if newItems.isEmpty { manifestData = nil }
            else { manifestData = try encodedLibrary(document) }
            var createdOriginals: [URL] = []
            do {
                for item in newItems {
                    guard let payload = payloads[item.id] else { continue }
                    let destination = try safeOriginalURL(relativePath: payload.relativePath, itemID: item.id)
                    if try writeOriginal(payload.data, to: destination) { createdOriginals.append(destination) }
                }
                for (item, payload) in repairs {
                    let destination = try safeOriginalURL(relativePath: payload.relativePath, itemID: item.id)
                    if try writeOriginal(payload.data, to: destination) { createdOriginals.append(destination) }
                }
                if let manifestData { try commit(manifestData) }
                return PearlImportResult(importedCount: newItems.count, skippedCount: skippedCount, repairedCount: repairs.count)
            } catch {
                for url in createdOriginals { try? fileManager.removeItem(at: url) }
                throw error
            }
        }
    }

    // MARK: - Transactions

    /// Internal synchronization boundary. Public archive import keeps its strict
    /// same-ID conflict behavior; only the causal sync engine uses this path.
    func syncTransaction<T>(_ operation: (inout PearlLibraryDocument) throws -> T) throws -> T {
        try withCoordinatedAccess {
            var document = try readLibrary()
            let oldItems = document.items
            let oldState = document.syncState
            let result = try operation(&document)
            if document.items != oldItems || document.syncState != oldState {
                try commit(try encodedLibrary(document))
            }
            return result
        }
    }

    func syncValidate(_ item: Pearl) throws { try validate(item) }

    func syncOriginalData(_ item: Pearl) throws -> Data? {
        guard let attachment = item.attachment else { return nil }
        let url = try safeOriginalURL(relativePath: attachment.relativePath, itemID: item.id)
        try validateOriginal(at: url, attachment: attachment)
        let data = try PearlSyncFiles.read(url, maximum: Int(Self.maximumAttachmentBytes))
        guard Int64(data.count) == attachment.byteCount else { throw PearlStoreError.attachmentChangedDuringImport }
        return data
    }

    func syncOriginalIsPresent(_ item: Pearl) throws -> Bool {
        guard let attachment = item.attachment else { return true }
        let url = try safeOriginalURL(relativePath: attachment.relativePath, itemID: item.id)
        guard fileManager.fileExists(atPath: url.path) else { return false }
        try validateOriginal(at: url, attachment: attachment)
        return true
    }

    func syncInstallOriginal(_ item: Pearl, data: Data) throws {
        try validate(item)
        guard let attachment = item.attachment, Int64(data.count) == attachment.byteCount else {
            throw PearlStoreError.invalidItem("The synchronized original does not match its metadata.")
        }
        let destination = try safeOriginalURL(relativePath: attachment.relativePath, itemID: item.id)
        _ = try writeOriginal(data, to: destination)
    }

    static func syncSafeFilename(_ filename: String) -> String {
        // Leave room for a complete SHA-256 prefix in the local filename.
        var name = safeFilename(filename)
        while name.utf8.count > 180 { name.removeLast() }
        return name
    }

    private func insertNew(_ pearl: Pearl) throws -> Pearl {
        try withCoordinatedAccess {
            var document = try readLibrary()
            guard !document.items.contains(where: { $0.id == pearl.id }) else { throw PearlStoreError.itemAlreadyExists(pearl.id) }
            try validate(pearl)
            document.items.append(pearl)
            try commit(try encodedLibrary(document))
            return pearl
        }
    }

    private func mutate(id: UUID, change: (inout Pearl) -> Void) throws -> Pearl {
        try withCoordinatedAccess {
            var document = try readLibrary()
            guard let index = document.items.firstIndex(where: { $0.id == id }) else { throw PearlStoreError.itemNotFound(id) }
            let original = document.items[index]
            change(&document.items[index])
            guard document.items[index] != original else { return original }
            document.items[index].updatedAt = max(document.items[index].createdAt, Self.timestamp())
            try validate(document.items[index])
            try commit(try encodedLibrary(document))
            return document.items[index]
        }
    }

    private func withCoordinatedAccess<T>(_ operation: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        #if canImport(Darwin)
        var coordinationError: NSError?
        var result: Result<T, Error>?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: rootDirectory, options: .forMerging, error: &coordinationError) { _ in
            result = Result { try operation() }
        }
        if let result { return try result.get() }
        if let coordinationError { throw coordinationError }
        throw PearlStoreError.fileCoordinationFailed
        #else
        // The portable fallback protects this instance; Apple platforms additionally coordinate files.
        return try operation()
        #endif
    }

    private func readLibrary() throws -> PearlLibraryDocument {
        if fileManager.fileExists(atPath: manifestURL.path) {
            let data = try readMetadata(at: manifestURL)
            do { return try decodedLibrary(data) }
            catch let error as PearlStoreError {
                if case .unsupportedSchema = error { throw error }
                return try recoverLibrary(primaryProblem: error.localizedDescription, damagedPrimary: true)
            }
            catch { return try recoverLibrary(primaryProblem: error.localizedDescription, damagedPrimary: true) }
        }
        if fileManager.fileExists(atPath: backupURL.path) {
            return try recoverLibrary(primaryProblem: "The current metadata file is missing.", damagedPrimary: false)
        }
        if !(try fileManager.contentsOfDirectory(atPath: originalsDirectory.path)).isEmpty {
            throw PearlStoreError.missingMetadataWithOriginals
        }
        let document = PearlLibraryDocument(items: [])
        try encodedLibrary(document).write(to: manifestURL, options: .atomic)
        return document
    }

    private func recoverLibrary(primaryProblem: String, damagedPrimary: Bool) throws -> PearlLibraryDocument {
        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw PearlStoreError.metadataUnrecoverable(primary: primaryProblem, backup: "No previous metadata copy exists.")
        }
        let backupData: Data
        let document: PearlLibraryDocument
        do {
            backupData = try readMetadata(at: backupURL)
            document = try decodedLibrary(backupData)
        } catch let error as PearlStoreError {
            // An unreadable primary does not authorize replacing a newer backup either.
            if case .unsupportedSchema = error { throw error }
            throw PearlStoreError.metadataUnrecoverable(primary: primaryProblem, backup: error.localizedDescription)
        } catch {
            throw PearlStoreError.metadataUnrecoverable(primary: primaryProblem, backup: error.localizedDescription)
        }
        var damagedURL: URL?
        if damagedPrimary {
            let recoveryDirectory = rootDirectory.appendingPathComponent("Recovery", isDirectory: true)
            try ensureSafeDirectory(recoveryDirectory)
            let destination = recoveryDirectory.appendingPathComponent("library-damaged-\(UUID().uuidString.lowercased()).json")
            try fileManager.copyItem(at: manifestURL, to: destination)
            damagedURL = destination
        }
        try backupData.write(to: manifestURL, options: .atomic)
        lastRecoveryNotice = PearlRecoveryNotice(
            recoveredItemCount: document.items.count,
            damagedMetadataURL: damagedURL,
            message: damagedPrimary
                ? "Pearls recovered the previous saved library. The most recent edit may be missing. Original files and a copy of the damaged metadata were preserved."
                : "Pearls recovered the previous saved library because the current metadata file was missing. The most recent edit may be missing. Original files were preserved."
        )
        return document
    }

    private func readMetadata(at url: URL) throws -> Data {
        try rejectSymlink(at: url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else {
            throw PearlStoreError.invalidMetadata("The metadata is not a regular file.")
        }
        guard size <= Self.maximumMetadataBytes else { throw PearlStoreError.libraryTooLarge }
        return try Data(contentsOf: url)
    }

    private func decodedLibrary(_ data: Data) throws -> PearlLibraryDocument {
        let header: PearlDocumentHeader
        do { header = try PearlDocumentCoding.decoder().decode(PearlDocumentHeader.self, from: data) }
        catch { throw PearlStoreError.invalidMetadata("The library format header could not be decoded.") }
        guard header.format == "com.pearls.library" else { throw PearlStoreError.invalidMetadata("The format identifier is not recognized.") }
        guard header.schemaVersion == 1 else { throw PearlStoreError.unsupportedSchema(header.schemaVersion) }

        let document: PearlLibraryDocument
        do { document = try PearlDocumentCoding.decoder().decode(PearlLibraryDocument.self, from: data) }
        catch { throw PearlStoreError.invalidMetadata("The JSON document could not be decoded.") }
        try validateItems(document.items)
        return document
    }

    private func encodedLibrary(_ document: PearlLibraryDocument) throws -> Data {
        try validateItems(document.items)
        var updated = document
        updated.savedAt = Self.timestamp()
        updated.items.sort(by: PearlSearch.newestFirst)
        let data = try PearlDocumentCoding.encoder().encode(updated)
        guard data.count <= Self.maximumMetadataBytes else { throw PearlStoreError.libraryTooLarge }
        return data
    }

    /// Previous validated metadata is written before the current snapshot is atomically replaced.
    private func commit(_ data: Data) throws {
        if fileManager.fileExists(atPath: manifestURL.path) {
            let previous = try readMetadata(at: manifestURL)
            _ = try decodedLibrary(previous)
            try rejectSymlink(at: backupURL)
            try previous.write(to: backupURL, options: .atomic)
        }
        try data.write(to: manifestURL, options: .atomic)
    }

    // MARK: - Validation and originals

    private func validateItems(_ items: [Pearl]) throws {
        var ids = Set<UUID>()
        var paths = Set<String>()
        for item in items {
            guard ids.insert(item.id).inserted else { throw PearlStoreError.invalidMetadata("Duplicate item identities were found.") }
            try validate(item)
            if let path = item.attachmentRelativePath {
                guard paths.insert(path).inserted else { throw PearlStoreError.invalidMetadata("Two items refer to the same original.") }
            }
        }
    }

    private func validate(_ item: Pearl) throws {
        guard item.createdAt.timeIntervalSinceReferenceDate.isFinite,
              item.updatedAt.timeIntervalSinceReferenceDate.isFinite,
              item.updatedAt >= item.createdAt,
              item.deletedAt?.timeIntervalSinceReferenceDate.isFinite != false else {
            throw PearlStoreError.invalidItem("The dates are invalid.")
        }
        if let sourceURL = item.sourceURL { try Self.validateSourceURL(sourceURL) }
        if item.kind == .link && item.sourceURL == nil { throw PearlStoreError.invalidItem("A saved link needs its original URL.") }
        let requiresOriginal = item.kind == .image || item.kind == .file
        guard requiresOriginal == (item.attachment != nil) else { throw PearlStoreError.invalidItem("The saved content and its original file do not match.") }
        if let attachment = item.attachment {
            guard attachment.byteCount >= 0, !attachment.originalFilename.isEmpty else { throw PearlStoreError.invalidItem("The original file metadata is incomplete.") }
            guard attachment.byteCount <= Self.maximumAttachmentBytes else { throw PearlStoreError.attachmentTooLarge(attachment.byteCount) }
            _ = try safeOriginalURL(relativePath: attachment.relativePath, itemID: item.id)
        }
    }

    private func safeOriginalURL(relativePath: String, itemID: UUID) throws -> URL {
        let parts = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts[0] == "attachments", parts[1] == itemID.uuidString.lowercased(),
              !parts[2].isEmpty, parts[2] != ".", parts[2] != "..",
              !relativePath.contains("\\"), !relativePath.contains("\0"), !parts[2].contains(":"),
              !parts[2].unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw PearlStoreError.unsafeAttachmentPath(relativePath)
        }
        let candidate = rootDirectory.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
        let allowedPrefix = originalsDirectory.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(allowedPrefix) else { throw PearlStoreError.unsafeAttachmentPath(relativePath) }
        try rejectSymlink(at: originalsDirectory)
        try rejectSymlink(at: candidate.deletingLastPathComponent())
        try rejectSymlink(at: candidate)
        return candidate
    }

    private func rejectSymlink(at url: URL) throws {
        let normalized = url.standardizedFileURL
        guard normalized.resolvingSymlinksInPath().path == normalized.path else { throw PearlStoreError.unsafeAttachmentPath(url.lastPathComponent) }
        // Also reject a dangling symbolic link (resolvingSymlinksInPath may leave it unresolved).
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            throw PearlStoreError.unsafeAttachmentPath(url.lastPathComponent)
        }
    }

    private func ensureSafeDirectory(_ directory: URL) throws {
        try rejectSymlink(at: directory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try rejectSymlink(at: directory)
    }

    private func validateOriginal(at url: URL, attachment: PearlAttachment) throws {
        guard fileManager.fileExists(atPath: url.path) else { throw PearlStoreError.attachmentMissing(attachment.originalFilename) }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else { throw PearlStoreError.attachmentMissing(attachment.originalFilename) }
        guard Int64(size) == attachment.byteCount else { throw PearlStoreError.attachmentSizeMismatch(attachment.originalFilename) }
    }

    /// Reuses an identical orphan from an interrupted transaction; never overwrites different bytes.
    private func copyOriginal(from source: URL, to destination: URL, expectedBytes: Int64) throws -> Bool {
        try ensureSafeDirectory(destination.deletingLastPathComponent())
        if fileManager.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = values.fileSize, Int64(size) == expectedBytes else {
                throw PearlStoreError.attachmentChangedDuringImport
            }
            guard fileManager.contentsEqual(atPath: source.path, andPath: destination.path) else { throw PearlStoreError.existingAttachmentConflict(destination.lastPathComponent) }
            return false
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: temporary) }
        try fileManager.copyItem(at: source, to: temporary)
        let values = try temporary.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, Int64(size) == expectedBytes,
              fileManager.contentsEqual(atPath: source.path, andPath: temporary.path) else {
            throw PearlStoreError.attachmentChangedDuringImport
        }
        try fileManager.moveItem(at: temporary, to: destination)
        return true
    }

    private func writeOriginal(_ data: Data, to destination: URL) throws -> Bool {
        try ensureSafeDirectory(destination.deletingLastPathComponent())
        if fileManager.fileExists(atPath: destination.path) {
            guard try Data(contentsOf: destination) == data else { throw PearlStoreError.existingAttachmentConflict(destination.lastPathComponent) }
            return false
        }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try fileManager.moveItem(at: temporary, to: destination)
        return true
    }

    private static func validateSourceURL(_ url: URL) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else {
            throw PearlStoreError.invalidSourceURL
        }
    }

    private static func timestamp(_ date: Date = Date()) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000)
    }

    private static func title(_ title: String, fallback: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func defaultTitle(for kind: PearlKind) -> String {
        switch kind {
        case .note: return "Untitled note"
        case .link: return "Saved link"
        case .image: return "Saved image"
        case .file: return "Saved file"
        }
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(PearlSearch.folded(cleaned)).inserted else { return nil }
            return cleaned
        }
    }

    private static func safeFilename(_ original: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let sanitized = original.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined()
        var result = ""
        for character in sanitized {
            let next = result + String(character)
            if next.utf8.count > 200 { break }
            result = next
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty || result == "." || result == ".." { result = "original" }
        if result.hasPrefix(".") { result = "original-" + result }
        return result
    }
}
