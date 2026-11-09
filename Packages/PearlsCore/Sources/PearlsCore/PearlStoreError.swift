import Foundation

public enum PearlStoreError: Error, LocalizedError {
    case fileURLRequired
    case invalidSourceURL
    case invalidItem(String)
    case itemNotFound(UUID)
    case itemAlreadyExists(UUID)
    case immutableAttachment
    case unsafeAttachmentPath(String)
    case attachmentMissing(String)
    case attachmentSizeMismatch(String)
    case attachmentTooLarge(Int64)
    case attachmentChangedDuringImport
    case existingAttachmentConflict(String)
    case invalidMetadata(String)
    case unsupportedSchema(Int)
    case metadataUnrecoverable(primary: String, backup: String)
    case missingMetadataWithOriginals
    case invalidArchive(String)
    case archiveTooLarge
    case archiveConflict(UUID)
    case libraryTooLarge
    case fileCoordinationFailed

    public var errorDescription: String? {
        switch self {
        case .fileURLRequired:
            return "Pearls needs a local file location."
        case .invalidSourceURL:
            return "Use a complete http or https link with a host name."
        case .invalidItem(let reason):
            return "This item could not be saved: \(reason)"
        case .itemNotFound:
            return "This item is no longer in the library. Refresh and try again."
        case .itemAlreadyExists:
            return "This capture is already in the library."
        case .immutableAttachment:
            return "An original attachment cannot be changed through a metadata edit. Save it as a new item."
        case .unsafeAttachmentPath:
            return "An attachment path is unsafe. No file was opened or imported."
        case .attachmentMissing(let name):
            return "The original file for \(name) is missing. The saved item has been preserved."
        case .attachmentSizeMismatch(let name):
            return "The original file for \(name) does not match its saved size. Its metadata has been preserved."
        case .attachmentTooLarge:
            return "The first version of Pearls supports originals up to 25 MiB each."
        case .attachmentChangedDuringImport:
            return "The source file changed while it was being copied. Try saving it again."
        case .existingAttachmentConflict:
            return "A different original already exists at this capture location. Both records were left unchanged."
        case .invalidMetadata(let reason):
            return "The library metadata is invalid: \(reason)"
        case .unsupportedSchema(let version):
            return "This library uses format version \(version). Open it with a newer version of Pearls."
        case .metadataUnrecoverable:
            return "The library metadata and its previous copy could not be read. Pearls has preserved the files and has not replaced the library with an empty one."
        case .missingMetadataWithOriginals:
            return "Original files exist, but library metadata is missing. Pearls has preserved the originals and has not created an empty replacement library."
        case .invalidArchive(let reason):
            return "This Pearls archive could not be imported: \(reason)"
        case .archiveTooLarge:
            return "A Pearls archive can be at most 100 MiB, including embedded originals."
        case .archiveConflict:
            return "An item in this archive has the same identity as a different item already saved here. Nothing was imported. Export this library before resolving the conflict."
        case .libraryTooLarge:
            return "The library metadata exceeds this version's supported size. The existing library has been preserved."
        case .fileCoordinationFailed:
            return "Pearls could not safely access the library. Please try again."
        }
    }
}

public struct PearlRecoveryNotice: Equatable, Sendable {
    public let recoveredItemCount: Int
    public let damagedMetadataURL: URL?
    public let message: String
}

public struct PearlImportResult: Equatable, Sendable {
    public let importedCount: Int
    public let skippedCount: Int
    public let repairedCount: Int

    public init(importedCount: Int, skippedCount: Int, repairedCount: Int = 0) {
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.repairedCount = repairedCount
    }
}
