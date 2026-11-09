import Foundation
import CryptoKit

enum PearlSyncFiles {
    static let markerName = "pearls-sync.json"
    static let maximumVersionBytes = 2 * 1024 * 1024
    static let maximumMetadataBytes = 64 * 1024 * 1024
    static let maximumVersions = 10_000
    static let maximumOriginalBytesPerPass = 256 * 1024 * 1024
    static let ignoredNames: Set<String> = [".DS_Store", "desktop.ini", "Thumbs.db"]

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func isHash(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func canonicalDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL,
              (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) == nil else { throw PearlSyncError.unsafePath }
        // The selected directory is the access boundary; normal system aliases
        // in its ancestors (such as /var) are canonicalized once.
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        try rejectSymlink(canonical)
        return canonical
    }

    static func rejectSymlink(_ url: URL) throws {
        let path = url.standardizedFileURL
        guard path.resolvingSymlinksInPath().path == path.path,
              (try? FileManager.default.destinationOfSymbolicLink(atPath: path.path)) == nil else { throw PearlSyncError.unsafePath }
        if (try? path.resourceValues(forKeys: [.isAliasFileKey]).isAliasFile) == true { throw PearlSyncError.unsafePath }
    }

    private static func coordinated<T>(_ url: URL, writing: Bool, enabled: Bool, operation: () throws -> T) throws -> T {
        #if canImport(Darwin)
        if enabled {
            var error: NSError?
            var result: Result<T, Error>?
            let coordinator = NSFileCoordinator(filePresenter: nil)
            if writing {
                coordinator.coordinate(writingItemAt: url, options: .forMerging, error: &error) { _ in result = Result { try operation() } }
            } else {
                coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { _ in result = Result { try operation() } }
            }
            if let result { return try result.get() }
            if let error { throw error }
            throw PearlSyncError.changedFile
        }
        #endif
        return try operation()
    }

    static func ensureDirectory(_ url: URL, coordination: Bool = false) throws {
        try coordinated(url, writing: true, enabled: coordination) { try ensureDirectoryUncoordinated(url) }
    }

    private static func ensureDirectoryUncoordinated(_ url: URL) throws {
        try rejectSymlink(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try rejectSymlink(url)
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw PearlSyncError.unsafePath }
    }

    static func children(_ directory: URL, limit: Int = maximumVersions, coordination: Bool = false) throws -> [URL] {
        if !FileManager.default.fileExists(atPath: directory.path) { try rejectSymlink(directory); return [] }
        return try coordinated(directory, writing: false, enabled: coordination) { try childrenUncoordinated(directory, limit: limit) }
    }

    private static func childrenUncoordinated(_ directory: URL, limit: Int) throws -> [URL] {
        try rejectSymlink(directory)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw PearlSyncError.unsafePath }
        var enumerationError: Error?
        guard let enumeration = FileManager.default.enumerator(at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsSubdirectoryDescendants], errorHandler: { _, error in
                enumerationError = error
                return false
            }) else { throw PearlSyncError.unsafePath }
        var result: [URL] = []
        for case let url as URL in enumeration {
            guard result.count < limit else { throw PearlSyncError.capacityExceeded }
            result.append(url)
        }
        if let enumerationError { throw enumerationError }
        return result.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func read(_ url: URL, maximum: Int, coordination: Bool = false) throws -> Data {
        try coordinated(url, writing: false, enabled: coordination) { try readUncoordinated(url, maximum: maximum) }
    }

    private static func readUncoordinated(_ url: URL, maximum: Int) throws -> Data {
        try rejectSymlink(url)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size >= 0, size <= maximum else { throw PearlSyncError.changedFile }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var result = Data()
        while result.count <= maximum {
            let part = try handle.read(upToCount: min(64 * 1024, maximum - result.count + 1)) ?? Data()
            if part.isEmpty { break }
            result.append(part)
        }
        try rejectSymlink(url)
        guard result.count == size, result.count <= maximum else { throw PearlSyncError.changedFile }
        return result
    }

    @discardableResult
    static func writeImmutable(_ data: Data, to url: URL, coordination: Bool = false) throws -> Bool {
        try ensureDirectory(url.deletingLastPathComponent(), coordination: coordination)
        return try coordinated(url, writing: true, enabled: coordination) { try writeImmutableUncoordinated(data, to: url) }
    }

    private static func writeImmutableUncoordinated(_ data: Data, to url: URL) throws -> Bool {
        try rejectSymlink(url)
        try ensureDirectory(url.deletingLastPathComponent())
        if FileManager.default.fileExists(atPath: url.path) {
            guard try read(url, maximum: data.count) == data else { throw PearlSyncError.changedFile }
            return false
        }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        do {
            // moveItem refuses an existing destination. Never atomically replace
            // an immutable remote file, even if another writer races us.
            try FileManager.default.moveItem(at: temporary, to: url)
            return true
        } catch {
            guard FileManager.default.fileExists(atPath: url.path),
                  try read(url, maximum: data.count) == data else { throw error }
            return false
        }
    }

    static func marker(in directory: URL) throws -> PearlSyncMarker? {
        let entries = try children(directory, limit: 64, coordination: true)
        var meaningful: [URL] = []
        for entry in entries {
            if ignoredNames.contains(entry.lastPathComponent) { continue }
            if try isStagingFile(entry) { continue }
            meaningful.append(entry)
        }
        guard !meaningful.isEmpty else { return nil }
        let allowed: Set<String> = [markerName, "versions", "originals"]
        guard meaningful.allSatisfy({ allowed.contains($0.lastPathComponent) }),
              meaningful.contains(where: { $0.lastPathComponent == markerName }) else { throw PearlSyncError.invalidDirectory }
        for entry in meaningful {
            try rejectSymlink(entry)
            if entry.lastPathComponent != markerName {
                guard try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw PearlSyncError.invalidDirectory }
            }
        }
        let result: PearlSyncMarker
        do { result = try PearlDocumentCoding.decoder().decode(PearlSyncMarker.self, from: read(directory.appendingPathComponent(markerName), maximum: 4096, coordination: true)) }
        catch { throw PearlSyncError.invalidMarker }
        guard result.format == "com.pearls.sync", result.schemaVersion == 1 else { throw PearlSyncError.invalidMarker }
        return result
    }

    static func openCollection(_ directory: URL) throws -> PearlSyncMarker {
        if let marker = try marker(in: directory) { return marker }
        try ensureDirectory(directory, coordination: true)
        let created = PearlSyncMarker()
        let data = try PearlDocumentCoding.encoder().encode(created)
        do { try writeImmutable(data, to: directory.appendingPathComponent(markerName), coordination: true) }
        catch { throw PearlSyncError.initializationConflict }
        guard let published = try marker(in: directory), published.collectionID == created.collectionID else { throw PearlSyncError.initializationConflict }
        return published
    }

    static func isStagingFile(_ url: URL) throws -> Bool {
        let name = url.lastPathComponent
        guard name.hasPrefix("."), name.hasSuffix(".partial"),
              UUID(uuidString: String(name.dropFirst().dropLast(".partial".count))) != nil else { return false }
        try rejectSymlink(url)
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw PearlSyncError.unsafePath }
        return true
    }

    static func versionURL(root: URL, itemID: UUID, revision: String) -> URL {
        root.appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(itemID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(revision + ".json")
    }

    static func originalURL(root: URL, original: PearlSyncOriginal) -> URL {
        root.appendingPathComponent("originals", isDirectory: true)
            .appendingPathComponent(original.sha256, isDirectory: true)
            .appendingPathComponent(original.filename)
    }
}
