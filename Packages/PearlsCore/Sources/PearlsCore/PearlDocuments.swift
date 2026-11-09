import Foundation

/// Decode version information before attempting to understand version-specific item fields.
struct PearlDocumentHeader: Decodable {
    let format: String
    let schemaVersion: Int
}

struct PearlLibraryDocument: Codable {
    let format: String
    let schemaVersion: Int
    var savedAt: Date
    var items: [Pearl]

    init(items: [Pearl], savedAt: Date = Date()) {
        format = "com.pearls.library"
        schemaVersion = 1
        self.savedAt = savedAt
        self.items = items
    }
}

struct PearlArchiveDocument: Codable {
    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let items: [Pearl]
    let attachments: [PearlArchiveAttachment]

    init(items: [Pearl], attachments: [PearlArchiveAttachment]) {
        format = "com.pearls.archive"
        schemaVersion = 1
        exportedAt = Date()
        self.items = items
        self.attachments = attachments
    }
}

struct PearlArchiveAttachment: Codable {
    let itemID: UUID
    let relativePath: String
    let data: Data
}

/// Metadata and portable archives share the same millisecond date encoding.
enum PearlDocumentCoding {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
