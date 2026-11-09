import Foundation
import Combine

/// A device-local grant to one explicitly selected private iCloud Drive folder.
/// Library contents never pass through preferences or the project-source mirror.
@MainActor
final class PearlsSyncFolder: ObservableObject {
    @Published private(set) var isConnected: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var status: String
    @Published private(set) var cloudStatus = "Waiting for the next sync check."
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var errorMessage: String?

    private static let bookmarkKey = "pearls.sync.folder.v1"
    private let defaults: UserDefaults
    private var bookmark: Data?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bookmark = defaults.data(forKey: Self.bookmarkKey)
        isConnected = bookmark != nil
        status = bookmark == nil ? "Not connected" : "Waiting to check your Pearls folder."
    }

    func connect(to folder: URL) throws {
        guard !isSyncing else { throw FolderError.busy }
        guard folder.startAccessingSecurityScopedResource() else { throw FolderError.access }
        defer { folder.stopAccessingSecurityScopedResource() }
        try Self.validateFolder(folder)
        let saved = try Self.makeBookmark(folder)
        defaults.set(saved, forKey: Self.bookmarkKey)
        bookmark = saved
        isConnected = true
        lastSyncAt = nil
        errorMessage = nil
        status = "Connected to your Pearls folder."
        cloudStatus = "Waiting for the next sync check."
    }

    /// Disconnecting revokes this device's saved connection, without deleting
    /// either its local library or any files already in iCloud Drive.
    func disconnect() {
        guard !isSyncing else { return }
        defaults.removeObject(forKey: Self.bookmarkKey)
        bookmark = nil
        isConnected = false
        lastSyncAt = nil
        errorMessage = nil
        status = "Not connected"
        cloudStatus = "Your local collection and iCloud files are unchanged."
    }

    func synchronize(using operation: (URL) async throws -> String) async {
        guard let bookmark, !isSyncing else { return }
        isSyncing = true
        errorMessage = nil
        status = "Checking your Pearls folder…"
        defer { isSyncing = false }
        do {
            var stale = false
            #if os(macOS)
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            let folder = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                                 relativeTo: nil, bookmarkDataIsStale: &stale)
            #endif
            guard folder.startAccessingSecurityScopedResource() else { throw FolderError.access }
            defer { folder.stopAccessingSecurityScopedResource() }
            let preparation = Task.detached(priority: .utility) {
                try Self.validateFolder(folder)
                try Self.prepareDownloads(in: folder)
            }
            try await withTaskCancellationHandler {
                try await preparation.value
            } onCancel: {
                preparation.cancel()
            }
            if stale {
                let refreshed = try Self.makeBookmark(folder)
                defaults.set(refreshed, forKey: Self.bookmarkKey)
                self.bookmark = refreshed
            }
            try Task.checkCancellation()
            status = "Syncing your collection…"
            let summary = try await operation(folder)
            lastSyncAt = Date()
            status = summary
            cloudStatus = await Task.detached(priority: .utility) {
                Self.uploadStatus(in: folder)
            }.value
        } catch is CancellationError {
            status = "Sync will resume when Pearls is active."
        } catch {
            status = "Sync paused. Your local collection remains available."
            errorMessage = error.localizedDescription
            cloudStatus = "iCloud upload status is unavailable."
        }
    }

    private static func makeBookmark(_ folder: URL) throws -> Data {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        // iOS document-picker bookmarks retain their implicit security scope.
        let options: URL.BookmarkCreationOptions = .minimalBookmark
        #endif
        return try folder.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private enum FolderError: LocalizedError {
        case busy, access, location, cloud, shared, unrelated, download, conflict, inventory

        var errorDescription: String? {
            switch self {
            case .busy: return "Wait for the current sync to finish before changing the connection."
            case .access: return "Access to the folder expired. Choose your Pearls folder again."
            case .location: return "Choose a dedicated folder named Pearls in iCloud Drive, outside source-code, project, and backup folders."
            case .cloud: return "This folder could not be confirmed as iCloud Drive. Choose Pearls under iCloud Drive in the file picker."
            case .shared: return "Choose a private iCloud Drive folder that is not shared with other people."
            case .unrelated: return "Choose an empty Pearls folder, or the existing folder created by Pearls sync. Other files must stay in a separate folder."
            case .download: return "iCloud is downloading changes. Keep the device online; Pearls will try again while it is open."
            case .conflict: return "iCloud reports an unresolved file conflict. Resolve it in Files or Finder before syncing again. Your local collection is unchanged."
            case .inventory: return "The complete sync folder could not be checked. Try again after iCloud finishes updating."
            }
        }
    }

    nonisolated private static let folderKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey,
        .isUbiquitousItemKey, .ubiquitousItemIsSharedKey,
        .ubiquitousItemHasUnresolvedConflictsKey
    ]
    nonisolated private static let itemKeys: Set<URLResourceKey> = folderKeys.union([
        .isRegularFileKey, .ubiquitousItemDownloadingStatusKey,
        .ubiquitousItemIsDownloadingKey, .ubiquitousItemDownloadingErrorKey,
        .ubiquitousItemIsUploadedKey, .ubiquitousItemIsUploadingKey,
        .ubiquitousItemUploadingErrorKey
    ])
    nonisolated private static let metadataNames: Set<String> = [".DS_Store", "desktop.ini", "Thumbs.db"]

    nonisolated private static func validateFolder(_ folder: URL) throws {
        guard folder.isFileURL, folder.lastPathComponent.lowercased() == "pearls" else { throw FolderError.location }
        let forbidden = Set([".git", ".github", "[projects]", "projects", "github", "codex"])
        for path in [folder.standardizedFileURL, folder.resolvingSymlinksInPath().standardizedFileURL] {
            guard !path.pathComponents.contains(where: {
                let part = $0.lowercased()
                return forbidden.contains(part) || part.hasPrefix("protondrive") || part.hasSuffix(".xcodeproj")
            }) else { throw FolderError.location }
        }
        let values = try folder.resourceValues(forKeys: folderKeys)
        guard values.isDirectory == true, values.isSymbolicLink != true, values.isAliasFile != true else { throw FolderError.location }
        guard values.isUbiquitousItem == true else { throw FolderError.cloud }
        guard values.ubiquitousItemIsShared == false else { throw FolderError.shared }
        guard values.ubiquitousItemHasUnresolvedConflicts != true else { throw FolderError.conflict }

        var ancestor = folder.standardizedFileURL
        while ancestor.path != "/" {
            if FileManager.default.fileExists(atPath: ancestor.appendingPathComponent(".git").path) {
                throw FolderError.location
            }
            ancestor.deleteLastPathComponent()
        }
        let children = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isSymbolicLinkKey, .isAliasFileKey], options: [])
        var names = Set<String>()
        for child in children {
            let flags = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isAliasFileKey])
            guard flags.isSymbolicLink != true, flags.isAliasFile != true else { throw FolderError.location }
            if metadataNames.contains(child.lastPathComponent) || isStagingName(logicalName(child)) {
                try validateIgnoredFile(child)
                continue
            }
            names.insert(logicalName(child))
        }
        guard names.isEmpty || (names.contains("pearls-sync.json") && names.isSubset(of: ["pearls-sync.json", "versions", "originals"])) else {
            throw FolderError.unrelated
        }
        // The core owns bounded marker/schema validation and all merge I/O.
        // The wrapper checks only enough structure to avoid unrelated trees.
    }

    nonisolated private static func logicalName(_ url: URL) -> String {
        let name = url.lastPathComponent
        if name.hasPrefix("."), name.hasSuffix(".icloud") {
            return String(name.dropFirst().dropLast(7))
        }
        return name
    }

    /// Enumerates only the known schema under the user's granted folder. It
    /// never scans iCloud Drive, a home directory, or a project-source tree.
    nonisolated private static func knownItems(in folder: URL) throws -> [URL] {
        var traversalError: Error?
        guard let enumerator = FileManager.default.enumerator(at: folder,
            includingPropertiesForKeys: Array(itemKeys), options: [], errorHandler: { _, error in
                traversalError = error
                return false
            }) else { throw FolderError.inventory }
        var result: [URL] = []
        let deadline = Date().addingTimeInterval(12)
        for case let item as URL in enumerator {
            try Task.checkCancellation()
            guard Date() < deadline else { throw FolderError.inventory }
            let relative = Array(item.pathComponents.dropFirst(folder.pathComponents.count))
            // Original filenames can themselves be metadata-looking names.
            if metadataNames.contains(item.lastPathComponent),
               !(relative.first == "originals" && relative.count == 3) {
                try validateIgnoredFile(item)
                continue
            }
            let names = relative.map { logicalName(URL(fileURLWithPath: $0)) }
            guard let first = names.first, names.count <= 3 else { throw FolderError.unrelated }
            if let name = names.last, isStagingName(name) {
                let allowedParent = names.count == 1 ||
                    (names.count == 3 && first == "versions" && UUID(uuidString: names[1]) != nil) ||
                    (names.count == 3 && first == "originals" && isDigest(names[1]))
                guard allowedParent else { throw FolderError.unrelated }
                try validateIgnoredFile(item)
                continue
            }
            switch first {
            case "pearls-sync.json":
                guard names.count == 1 else { throw FolderError.unrelated }
            case "versions":
                if names.count >= 2, UUID(uuidString: names[1]) == nil { throw FolderError.unrelated }
                if names.count == 3 {
                    guard names[2].hasSuffix(".json"), isDigest(String(names[2].dropLast(5))) else { throw FolderError.unrelated }
                }
            case "originals":
                if names.count >= 2, !isDigest(names[1]) { throw FolderError.unrelated }
            default: throw FolderError.unrelated
            }
            let values = try item.resourceValues(forKeys: itemKeys)
            guard values.isSymbolicLink != true, values.isAliasFile != true else { throw FolderError.location }
            guard values.ubiquitousItemIsShared != true else { throw FolderError.shared }
            guard values.ubiquitousItemHasUnresolvedConflicts != true else { throw FolderError.conflict }
            result.append(item)
            guard result.count <= 100_000 else { throw FolderError.inventory }
        }
        if traversalError != nil { throw FolderError.inventory }
        return result
    }

    nonisolated private static func isDigest(_ text: String) -> Bool {
        text.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    nonisolated private static func isStagingName(_ name: String) -> Bool {
        guard name.hasPrefix("."), name.hasSuffix(".partial") else { return false }
        return UUID(uuidString: String(name.dropFirst().dropLast(8))) != nil
    }

    nonisolated private static func validateIgnoredFile(_ file: URL) throws {
        let flags = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey])
        guard flags.isRegularFile == true, flags.isDirectory != true,
              flags.isSymbolicLink != true, flags.isAliasFile != true else { throw FolderError.location }
    }

    nonisolated private static func prepareDownloads(in folder: URL) throws {
        var waiting = false
        let deadline = Date().addingTimeInterval(12)
        for item in try knownItems(in: folder) {
            try Task.checkCancellation()
            guard Date() < deadline else { throw FolderError.inventory }
            let values = try item.resourceValues(forKeys: itemKeys)
            if values.ubiquitousItemDownloadingError != nil { throw FolderError.download }
            let downloadStatus = values.ubiquitousItemDownloadingStatus
            if values.ubiquitousItemIsDownloading == true ||
                (downloadStatus != nil && downloadStatus != .current) ||
                (item.lastPathComponent.hasPrefix(".") && item.pathExtension == "icloud") {
                let downloadURL = item.deletingLastPathComponent().appendingPathComponent(logicalName(item))
                try FileManager.default.startDownloadingUbiquitousItem(at: downloadURL)
                waiting = true
            }
        }
        if waiting { throw FolderError.download }
    }

    nonisolated private static func uploadStatus(in folder: URL) -> String {
        do {
            var checked = 0
            var pending = false
            for item in try knownItems(in: folder) {
                var fresh = item
                fresh.removeAllCachedResourceValues()
                let values = try fresh.resourceValues(forKeys: itemKeys)
                guard values.isDirectory != true else { continue }
                checked += 1
                if values.ubiquitousItemUploadingError != nil {
                    return "iCloud could not finish uploading. Your local collection is safe."
                }
                if values.ubiquitousItemIsUploaded != true || values.ubiquitousItemIsUploading == true {
                    pending = true
                }
            }
            if checked > 0, !pending {
                return "Saved to iCloud."
            }
            return "Waiting for iCloud to upload."
        } catch {
            return "iCloud upload status is unavailable."
        }
    }
}
