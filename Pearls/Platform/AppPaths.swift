import Foundation

enum AppPaths {
    static var appGroupIdentifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "PearlsAppGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    static var sharedContainer: URL? {
        guard let identifier = appGroupIdentifier else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func libraryDirectory() throws -> URL {
        // Keep the library in one stable app-container location. The extension
        // only needs the shared inbox, so changing App Group access must not
        // make an existing collection disappear behind a different root.
        let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appendingPathComponent("Pearls", isDirectory: true)
    }

    static func sharedInbox() throws -> URL {
        guard let container = sharedContainer else {
            throw CaptureError.sharedContainerUnavailable
        }
        let directory = container.appendingPathComponent("SharedInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

enum CaptureError: LocalizedError {
    case sharedContainerUnavailable
    case invalidCapture
    case unsupportedContent
    case originalTooLarge

    var errorDescription: String? {
        switch self {
        case .sharedContainerUnavailable:
            return "Sharing is not configured for this build. Open Pearls and use Save or Import instead."
        case .invalidCapture:
            return "This shared item could not be read. Its original has been left in place."
        case .unsupportedContent:
            return "Share text, a web link, an image, a PDF, or a file with Pearls."
        case .originalTooLarge:
            return "Each original can be up to 25 MiB in this first version."
        }
    }
}

/// The extension publishes one immutable capture at a time. Only the main app
/// writes library metadata, preventing an extension from overwriting app edits.
struct PendingCapture: Codable, Sendable {
    let id: UUID
    let kind: String
    let title: String
    let text: String
    let sourceURL: URL?
    let originalFilename: String?
    let contentType: String?
    let createdAt: Date

    static let maximumOriginalBytes = 25 * 1024 * 1024

    func publish(originalData: Data? = nil) throws {
        let needsOriginal = ["image", "file"].contains(kind)
        guard ["note", "link", "image", "file"].contains(kind),
              needsOriginal == (originalData != nil),
              needsOriginal == (originalFilename != nil) else { throw CaptureError.invalidCapture }
        if let originalData, originalData.count > Self.maximumOriginalBytes {
            throw CaptureError.originalTooLarge
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadata = try encoder.encode(self)
        guard metadata.count < 2 * 1024 * 1024 else { throw CaptureError.invalidCapture }
        let inbox = try AppPaths.sharedInbox()
        let directory = inbox.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            if let originalData {
                guard let name = originalFilename, Self.isSafeFilename(name) else {
                    throw CaptureError.invalidCapture
                }
                try originalData.write(to: directory.appendingPathComponent(name), options: .atomic)
            }
            // Publishing metadata last makes incomplete captures invisible.
            try metadata.write(to: directory.appendingPathComponent("capture.json"), options: .atomic)
        } catch {
            // Only this newly created, uncommitted capture directory is removed.
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    static func read(from directory: URL) throws -> PendingCapture {
        let metadata = directory.appendingPathComponent("capture.json")
        let values = try metadata.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let bytes = values.fileSize, bytes < 2 * 1024 * 1024 else { throw CaptureError.invalidCapture }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let capture = try decoder.decode(PendingCapture.self, from: Data(contentsOf: metadata))
        guard capture.id.uuidString.lowercased() == directory.lastPathComponent.lowercased(),
              ["note", "link", "image", "file"].contains(capture.kind),
              ["image", "file"].contains(capture.kind) == (capture.originalFilename != nil) else {
            throw CaptureError.invalidCapture
        }
        return capture
    }

    func originalURL(in directory: URL) throws -> URL? {
        guard let name = originalFilename else { return nil }
        guard Self.isSafeFilename(name) else { throw CaptureError.invalidCapture }
        let original = directory.appendingPathComponent(name)
        let parent = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard original.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(parent) else {
            throw CaptureError.invalidCapture
        }
        return original
    }

    static func isSafeFilename(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && value.lowercased() != "capture.json"
            && !value.contains("/") && !value.contains("\\") && !value.contains("\0")
    }
}
