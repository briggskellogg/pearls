import Foundation

extension PearlStore {
    /// Read-only destination validation. The caller owns file-provider download
    /// readiness and security-scoped access. No account/container is inferred.
    public static func validateSyncDirectory(_ directory: URL) throws {
        let root = try PearlSyncFiles.canonicalDirectory(directory)
        _ = try PearlSyncFiles.marker(in: root)
    }

    /// Reconciles immutable versions in a user-selected dedicated folder.
    /// Run off the main thread on the same serial owner as the local store.
    /// Local edits remain usable offline; no remote/history file is deleted.
    public func synchronize(with directory: URL) throws -> PearlSyncResult {
        try synchronize(with: directory, maximumOriginalBytesPerPhase: PearlSyncFiles.maximumOriginalBytesPerPass,
                        maximumMetadataBytes: PearlSyncFiles.maximumMetadataBytes)
    }

    // Smaller budgets exercise continuation without allocating large fixtures.
    // Production callers always use the fixed, bounded defaults above.
    func synchronize(with directory: URL, maximumOriginalBytesPerPhase: Int,
                     maximumMetadataBytes: Int = PearlSyncFiles.maximumMetadataBytes) throws -> PearlSyncResult {
        guard (1...PearlSyncFiles.maximumOriginalBytesPerPass).contains(maximumOriginalBytesPerPhase),
              (1...PearlSyncFiles.maximumMetadataBytes).contains(maximumMetadataBytes) else { throw PearlSyncError.limitExceeded }
        let remote = try PearlSyncFiles.canonicalDirectory(directory)
        guard remote != rootDirectory, !remote.path.hasPrefix(rootDirectory.path + "/"),
              !rootDirectory.path.hasPrefix(remote.path + "/") else { throw PearlSyncError.invalidDirectory }
        return try syncTransaction { document in
            let engine = try PearlSyncEngine(store: self, remote: remote, document: document,
                maximumOriginalBytesPerPhase: maximumOriginalBytesPerPhase, maximumMetadataBytes: maximumMetadataBytes)
            return try engine.run(document: &document)
        }
    }
}

private struct PearlSyncEntry {
    let revision: String
    let version: PearlSyncVersion
    let data: Data
}

private final class PearlSyncEngine {
    private let store: PearlStore
    private let remote: URL
    private let cache: URL
    private let collectionID: UUID
    private let maximumOriginalBytesPerPhase: Int
    private let maximumMetadataBytes: Int
    private var collection: PearlSyncCollectionState
    private var result = PearlSyncResult()
    private var entries: [String: PearlSyncEntry] = [:]
    private var remoteRevisions = Set<String>()
    private var blocked = Set<UUID>()
    private var metadataBytes = 0
    private var chargedMetadata = Set<String>()
    private var originalBytes = 0
    private var chargedOriginals = Set<String>()

    init(store: PearlStore, remote: URL, document: PearlLibraryDocument,
         maximumOriginalBytesPerPhase: Int, maximumMetadataBytes: Int) throws {
        self.store = store
        self.remote = remote
        self.maximumOriginalBytesPerPhase = maximumOriginalBytesPerPhase
        self.maximumMetadataBytes = maximumMetadataBytes
        let marker = try PearlSyncFiles.openCollection(remote)
        collectionID = marker.collectionID
        let key = marker.collectionID.uuidString.lowercased()
        let collections = document.syncState?.collections ?? [:]
        guard collections[key] != nil || collections.count < 16 else { throw PearlSyncError.capacityExceeded }
        collection = collections[key] ?? PearlSyncCollectionState()
        cache = store.rootDirectory.appendingPathComponent("Sync", isDirectory: true).appendingPathComponent(key, isDirectory: true)
        try PearlSyncFiles.ensureDirectory(cache)
        for root in [cache, remote] {
            try PearlSyncFiles.ensureDirectory(root.appendingPathComponent("versions", isDirectory: true), coordination: root == remote)
            try PearlSyncFiles.ensureDirectory(root.appendingPathComponent("originals", isDirectory: true), coordination: root == remote)
        }
    }

    func run(document: inout PearlLibraryDocument) throws -> PearlSyncResult {
        try scan(root: cache, isRemote: false)
        // Parents come exclusively from this collection's previously committed
        // projection, never from remote changes the user has not yet observed.
        for item in document.items.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let key = item.id.uuidString.lowercased()
            if collection.observed[key]?.fingerprint == (try fingerprint(item)) { continue }
            do {
                let parents = collection.observed[key]?.heads ?? []
                guard parents.allSatisfy({ entries[$0] != nil }) else { throw PearlSyncError.invalidVersion }
                let version = try localVersion(item, parents: parents)
                _ = try retain(version)
            } catch {
                deferItem(item.id, error: error)
            }
        }
        resetBudget()
        try scan(root: remote, isRemote: true)

        // Forks become independent, deterministic records. Their source dates,
        // content and IDs stay stable, so repeat sync never manufactures copies.
        var graph = completeHeads()
        var copiesCreated = 0
        for id in graph.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard !blocked.contains(id), let heads = graph[id], heads.count > 1 else { continue }
            let winner = selected(heads)
            for entry in heads where entry.revision != winner.revision {
                guard copiesCreated < 256 else { deferItem(id, error: PearlSyncError.limitExceeded); break }
                do {
                    let copy = conflictCopy(entry)
                    if try retain(copy) {
                        result.conflictCopyCount += 1
                        copiesCreated += 1
                    }
                } catch { deferItem(id, error: error) }
            }
        }
        graph = completeHeads()

        // Publish originals first and metadata last. Existing hash paths can
        // only be reused when the bytes match; old versions are never removed.
        resetBudget()
        for entry in entries.values.sorted(by: { $0.revision < $1.revision }) where !remoteRevisions.contains(entry.revision) {
            do {
                if let original = entry.version.original {
                    let data = try originalData(entry.version, root: cache)
                    try PearlSyncFiles.writeImmutable(data, to: PearlSyncFiles.originalURL(root: remote, original: original), coordination: true)
                }
                if try PearlSyncFiles.writeImmutable(entry.data, to: PearlSyncFiles.versionURL(root: remote, itemID: entry.version.item.id, revision: entry.revision), coordination: true) {
                    result.uploadedVersionCount += 1
                }
            } catch { deferItem(entry.version.item.id, error: error) }
        }

        resetBudget()
        var current = Dictionary(uniqueKeysWithValues: document.items.map { ($0.id, $0) })
        var ids = graph.keys.sorted { $0.uuidString.lowercased() < $1.uuidString.lowercased() }
        if let cursor = collection.verificationCursor {
            ids = ids.filter { $0.uuidString.lowercased() > cursor } + ids.filter { $0.uuidString.lowercased() <= cursor }
        }
        for (index, id) in ids.enumerated() {
            guard !blocked.contains(id), let heads = graph[id], !heads.isEmpty else { continue }
            let winner = selected(heads)
            let item = winner.version.item
            do {
                // Recheck current remote originals even for cached revisions.
                // Each bounded verification pass rotates through the library;
                // known corrupt remote bytes are never reported as healthy.
                if item.attachment != nil {
                    let data = try originalData(winner.version, root: cache)
                    guard try originalData(winner.version, root: remote) == data else { throw PearlSyncError.changedFile }
                    if try store.syncOriginalIsPresent(item) {
                        let local = try readStoreOriginal(item)
                        guard local == data else { throw PearlSyncError.changedFile }
                    } else {
                        try store.syncInstallOriginal(item, data: data)
                    }
                }
                try store.syncValidate(item)
                current[id] = item
                collection.observed[id.uuidString.lowercased()] = PearlSyncObserved(
                    fingerprint: try fingerprint(item), heads: heads.map(\.revision).sorted())
                collection.verificationCursor = id.uuidString.lowercased()
            } catch PearlSyncError.limitExceeded {
                result.deferredFileCount += ids.count - index
                appendIssue(PearlSyncError.limitExceeded.localizedDescription)
                break
            } catch { deferItem(id, error: error) }
        }
        guard try PearlSyncFiles.marker(in: remote)?.collectionID == collectionID else { throw PearlSyncError.initializationConflict }
        document.items = current.values.sorted(by: PearlSearch.newestFirst)
        if !collection.observed.isEmpty || document.syncState?.collections[collectionID.uuidString.lowercased()] != nil {
            var state = document.syncState ?? PearlSyncState()
            state.collections[collectionID.uuidString.lowercased()] = collection
            document.syncState = state
        }
        return result
    }

    private func fingerprint(_ item: Pearl) throws -> String {
        PearlSyncFiles.hash(try PearlDocumentCoding.encoder().encode(item))
    }

    private func charge(_ url: URL, bytes: Int64) throws {
        guard bytes >= 0, bytes <= PearlStore.maximumAttachmentBytes else { throw PearlSyncError.invalidVersion }
        if chargedOriginals.insert(url.path).inserted {
            guard bytes <= Int64(maximumOriginalBytesPerPhase - originalBytes) else {
                chargedOriginals.remove(url.path)
                throw PearlSyncError.limitExceeded
            }
            originalBytes += Int(bytes)
        }
    }

    private func resetBudget() {
        // Four bounded phases permit progress when a large offline collection
        // exceeds one phase's transfer allowance. No phase buffers all originals.
        originalBytes = 0
        chargedOriginals.removeAll()
    }

    private func chargeMetadata(_ revision: String, bytes: Int) throws {
        if !chargedMetadata.contains(revision) {
            guard bytes <= maximumMetadataBytes - metadataBytes else { throw PearlSyncError.capacityExceeded }
            metadataBytes += bytes
            chargedMetadata.insert(revision)
        }
    }

    private func readStoreOriginal(_ item: Pearl) throws -> Data {
        guard let attachment = item.attachment else { throw PearlSyncError.invalidVersion }
        try charge(store.rootDirectory.appendingPathComponent(attachment.relativePath), bytes: attachment.byteCount)
        guard let data = try store.syncOriginalData(item) else { throw PearlSyncError.invalidVersion }
        return data
    }

    private func originalData(_ version: PearlSyncVersion, root: URL) throws -> Data {
        guard let original = version.original, let attachment = version.item.attachment else { throw PearlSyncError.invalidVersion }
        let url = PearlSyncFiles.originalURL(root: root, original: original)
        try charge(url, bytes: attachment.byteCount)
        let data = try PearlSyncFiles.read(url, maximum: Int(PearlStore.maximumAttachmentBytes), coordination: root == remote)
        guard Int64(data.count) == attachment.byteCount, PearlSyncFiles.hash(data) == original.sha256 else { throw PearlSyncError.changedFile }
        return data
    }

    private func localVersion(_ item: Pearl, parents: [String]) throws -> PearlSyncVersion {
        var original: PearlSyncOriginal?
        if let attachment = item.attachment {
            let data = try readStoreOriginal(item)
            original = PearlSyncOriginal(sha256: PearlSyncFiles.hash(data), filename: PearlStore.syncSafeFilename(attachment.originalFilename))
            try PearlSyncFiles.writeImmutable(data, to: PearlSyncFiles.originalURL(root: cache, original: original!))
        }
        let normalized = normalizedItem(item, id: item.id, title: item.title, original: original)
        return PearlSyncVersion(item: normalized, parents: parents, original: original)
    }

    private func normalizedItem(_ item: Pearl, id: UUID, title: String, original: PearlSyncOriginal?) -> Pearl {
        let attachment: PearlAttachment?
        if let source = item.attachment, let original {
            attachment = PearlAttachment(relativePath: "attachments/\(id.uuidString.lowercased())/\(original.sha256)-\(original.filename)",
                originalFilename: source.originalFilename, contentType: source.contentType, byteCount: source.byteCount)
        } else { attachment = nil }
        return Pearl(id: id, kind: item.kind, title: title, text: item.text, sourceURL: item.sourceURL, tags: item.tags,
                     ocrText: item.ocrText, isFavorite: item.isFavorite, createdAt: item.createdAt,
                     updatedAt: item.updatedAt, deletedAt: item.deletedAt, attachment: attachment)
    }

    private func conflictCopy(_ entry: PearlSyncEntry) -> PearlSyncVersion {
        let hex = PearlSyncFiles.hash(Data(("pearls-conflict:" + entry.version.item.id.uuidString.lowercased() + ":" + entry.revision).utf8))
        let chars = Array(hex.prefix(32))
        let uuid = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
        let id = UUID(uuidString: uuid)!
        let item = normalizedItem(entry.version.item, id: id, title: entry.version.item.title + " (conflict copy)", original: entry.version.original)
        return PearlSyncVersion(item: item, parents: [], original: entry.version.original)
    }

    @discardableResult
    private func retain(_ version: PearlSyncVersion) throws -> Bool {
        try validate(version)
        let data = try PearlDocumentCoding.encoder().encode(version)
        guard data.count <= PearlSyncFiles.maximumVersionBytes else { throw PearlSyncError.capacityExceeded }
        let revision = PearlSyncFiles.hash(data)
        if entries[revision] != nil { return false }
        guard entries.count < PearlSyncFiles.maximumVersions else { throw PearlSyncError.capacityExceeded }
        try chargeMetadata(revision, bytes: data.count)
        try PearlSyncFiles.writeImmutable(data, to: PearlSyncFiles.versionURL(root: cache, itemID: version.item.id, revision: revision))
        entries[revision] = PearlSyncEntry(revision: revision, version: version, data: data)
        return true
    }

    private func validate(_ version: PearlSyncVersion) throws {
        guard version.parents.count <= 128 else { throw PearlSyncError.capacityExceeded }
        guard version.format == "com.pearls.sync.version", version.schemaVersion == 1,
              version.parents == Array(Set(version.parents)).sorted(),
              version.parents.allSatisfy(PearlSyncFiles.isHash) else { throw PearlSyncError.invalidVersion }
        try store.syncValidate(version.item)
        if let attachment = version.item.attachment {
            guard let original = version.original, PearlSyncFiles.isHash(original.sha256),
                  original.filename == PearlStore.syncSafeFilename(attachment.originalFilename),
                  attachment.relativePath == "attachments/\(version.item.id.uuidString.lowercased())/\(original.sha256)-\(original.filename)" else { throw PearlSyncError.invalidVersion }
        } else if version.original != nil { throw PearlSyncError.invalidVersion }
    }

    private func scan(root: URL, isRemote: Bool) throws {
        let versionRoot = root.appendingPathComponent("versions", isDirectory: true)
        var fileCount = 0
        for itemDirectory in try PearlSyncFiles.children(versionRoot, coordination: isRemote) {
            if PearlSyncFiles.ignoredNames.contains(itemDirectory.lastPathComponent) { continue }
            guard let id = UUID(uuidString: itemDirectory.lastPathComponent),
                  itemDirectory.lastPathComponent == id.uuidString.lowercased() else {
                result.deferredFileCount += 1
                appendIssue("An unrecognized sync record folder was left untouched.")
                continue
            }
            do {
                for path in try PearlSyncFiles.children(itemDirectory, coordination: isRemote) {
                    if PearlSyncFiles.ignoredNames.contains(path.lastPathComponent) { continue }
                    if try PearlSyncFiles.isStagingFile(path) { continue }
                    fileCount += 1
                    guard fileCount <= PearlSyncFiles.maximumVersions else { throw PearlSyncError.capacityExceeded }
                    do {
                        let revision = path.deletingPathExtension().lastPathComponent
                        guard path.pathExtension == "json", PearlSyncFiles.isHash(revision) else { throw PearlSyncError.invalidVersion }
                        let data = try PearlSyncFiles.read(path, maximum: PearlSyncFiles.maximumVersionBytes, coordination: isRemote)
                        guard PearlSyncFiles.hash(data) == revision else { throw PearlSyncError.invalidVersion }
                        try chargeMetadata(revision, bytes: data.count)
                        let version = try PearlDocumentCoding.decoder().decode(PearlSyncVersion.self, from: data)
                        guard version.item.id == id else { throw PearlSyncError.invalidVersion }
                        try validate(version)
                        if isRemote {
                            if entries[revision] != nil {
                                // The rotating projection pass rechecks current
                                // remote content. Missing originals can be
                                // republished from the validated local cache.
                                if let original = version.original {
                                    let url = PearlSyncFiles.originalURL(root: remote, original: original)
                                    try PearlSyncFiles.rejectSymlink(url)
                                    if !FileManager.default.fileExists(atPath: url.path) { continue }
                                }
                                remoteRevisions.insert(revision)
                                continue
                            }
                            if let original = version.original {
                                let data = try originalData(version, root: remote)
                                try PearlSyncFiles.writeImmutable(data, to: PearlSyncFiles.originalURL(root: cache, original: original))
                            }
                            if try retain(version) { result.downloadedVersionCount += 1 }
                            remoteRevisions.insert(revision)
                        } else {
                            guard entries.count < PearlSyncFiles.maximumVersions else { throw PearlSyncError.capacityExceeded }
                            entries[revision] = PearlSyncEntry(revision: revision, version: version, data: data)
                        }
                    } catch PearlSyncError.limitExceeded { throw PearlSyncError.limitExceeded }
                    catch PearlSyncError.capacityExceeded { throw PearlSyncError.capacityExceeded }
                    catch { deferItem(id, error: error) }
                }
            } catch PearlSyncError.limitExceeded {
                // Metadata enumeration limits stop the pass before projection;
                // bounded transfer limits leave the affected item for retry.
                throw PearlSyncError.limitExceeded
            } catch PearlSyncError.capacityExceeded {
                throw PearlSyncError.capacityExceeded
            } catch { deferItem(id, error: error) }
        }
    }

    private func completeHeads() -> [UUID: [PearlSyncEntry]] {
        let groups = Dictionary(grouping: entries.values, by: { $0.version.item.id })
        var result: [UUID: [PearlSyncEntry]] = [:]
        for (id, nodes) in groups {
            var remaining: [String: Int] = [:]
            var descendants: [String: [String]] = [:]
            var parents = Set<String>()
            var invalid = false
            for node in nodes {
                remaining[node.revision] = node.version.parents.count
                var hasCompatibleParent = node.version.parents.isEmpty
                for parent in node.version.parents {
                    guard let previous = entries[parent], previous.version.item.id == id else { invalid = true; continue }
                    if previous.version.item.kind == node.version.item.kind,
                       previous.version.item.createdAt == node.version.item.createdAt,
                       previous.version.item.attachment == node.version.item.attachment,
                       previous.version.original == node.version.original { hasCompatibleParent = true }
                    descendants[parent, default: []].append(node.revision)
                    parents.insert(parent)
                }
                // Observed conflicting roots can be resolved by a metadata edit
                // of the selected record. Its original must come from a parent;
                // all other parents and their conflict copies remain retained.
                if !hasCompatibleParent { invalid = true }
            }
            // Iterative topological validation bounds work and cannot overflow
            // the call stack on deep histories or cycle-shaped hostile input.
            var ready = remaining.filter { $0.value == 0 }.map(\.key)
            var visited = 0
            while let current = ready.popLast() {
                visited += 1
                for child in descendants[current] ?? [] {
                    remaining[child, default: 0] -= 1
                    if remaining[child] == 0 { ready.append(child) }
                }
            }
            if invalid || visited != nodes.count {
                deferItem(id, error: PearlSyncError.invalidVersion)
                continue
            }
            result[id] = nodes.filter { !parents.contains($0.revision) }.sorted { $0.revision < $1.revision }
        }
        return result
    }

    private func selected(_ heads: [PearlSyncEntry]) -> PearlSyncEntry {
        // An unseen deletion never revives the original during an edit/delete
        // fork. The concurrent live content is retained as its own conflict copy.
        heads.filter { $0.version.item.isDeleted }.min { $0.revision < $1.revision }
            ?? heads.min { $0.revision < $1.revision }!
    }

    private func deferItem(_ id: UUID, error: Error) {
        blocked.insert(id)
        result.deferredFileCount += 1
        appendIssue(error is DecodingError ? PearlSyncError.invalidVersion.localizedDescription : error.localizedDescription)
    }

    private func appendIssue(_ message: String) {
        if result.issues.count < 16 && !result.issues.contains(message) { result.issues.append(message) }
    }
}
