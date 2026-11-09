import Foundation

public struct PearlSyncResult: Equatable, Sendable {
    public var uploadedVersionCount = 0
    public var downloadedVersionCount = 0
    public var conflictCopyCount = 0
    public var deferredFileCount = 0
    public var issues: [String] = []
    public init() {}
}

public enum PearlSyncError: Error, LocalizedError {
    case invalidDirectory
    case invalidMarker
    case initializationConflict
    case unsafePath
    case invalidVersion
    case changedFile
    case limitExceeded
    case capacityExceeded

    public var errorDescription: String? {
        switch self {
        case .invalidDirectory: return "Choose an empty dedicated Pearls folder or an existing Pearls sync collection. Other files were left untouched."
        case .invalidMarker: return "This folder's Pearls sync format is missing, damaged, or unsupported. No collection was replaced."
        case .initializationConflict: return "Another device initialized or changed this sync folder. Try again after the cloud drive finishes updating."
        case .unsafePath: return "A sync path is unsafe or is a symbolic link. No file at that path was used."
        case .invalidVersion: return "A synchronized record is malformed or does not match its checksum. Its files were preserved."
        case .changedFile: return "A sync file is incomplete, changed, or has different bytes at an immutable location. It was not overwritten."
        case .limitExceeded: return "This sync pass reached its transfer allowance. Files and local changes remain saved; later passes continue verification."
        case .capacityExceeded: return "This collection exceeds the supported history or collection capacity. Files remain saved; repeating sync will not increase that capacity."
        }
    }
}

struct PearlSyncState: Codable, Equatable {
    var collections: [String: PearlSyncCollectionState] = [:]
}

struct PearlSyncCollectionState: Codable, Equatable {
    var observed: [String: PearlSyncObserved] = [:]
    var verificationCursor: String?
}

struct PearlSyncObserved: Codable, Equatable {
    let fingerprint: String
    let heads: [String]
}

struct PearlSyncMarker: Codable {
    let format: String
    let schemaVersion: Int
    let collectionID: UUID
    init(collectionID: UUID = UUID()) {
        format = "com.pearls.sync"
        schemaVersion = 1
        self.collectionID = collectionID
    }
}

struct PearlSyncOriginal: Codable, Equatable {
    let sha256: String
    let filename: String
}

struct PearlSyncVersion: Codable {
    let format: String
    let schemaVersion: Int
    let item: Pearl
    let parents: [String]
    let original: PearlSyncOriginal?

    init(item: Pearl, parents: [String], original: PearlSyncOriginal?) {
        format = "com.pearls.sync.version"
        schemaVersion = 1
        self.item = item
        self.parents = parents.sorted()
        self.original = original
    }
}
