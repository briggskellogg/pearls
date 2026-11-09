import Foundation

public enum PearlKind: String, Codable, CaseIterable, Hashable, Sendable {
    case note
    case link
    case image
    case file
}

/// The original bytes stay in the store; metadata contains only a safe relative path.
public struct PearlAttachment: Codable, Equatable, Sendable {
    public let relativePath: String
    public let originalFilename: String
    public let contentType: String?
    public let byteCount: Int64

    public init(relativePath: String, originalFilename: String, contentType: String? = nil, byteCount: Int64) {
        self.relativePath = relativePath
        self.originalFilename = originalFilename
        self.contentType = contentType
        self.byteCount = byteCount
    }
}

/// One saved thought or original. `ocrText` is indexed text, never a replacement for image bytes.
public struct Pearl: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: PearlKind
    public var title: String
    public var text: String
    public var sourceURL: URL?
    public var tags: [String]
    public var ocrText: String
    public var isFavorite: Bool
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
    public let attachment: PearlAttachment?

    public var isDeleted: Bool { deletedAt != nil }
    public var originalFilename: String? { attachment?.originalFilename }
    public var attachmentRelativePath: String? { attachment?.relativePath }

    public init(
        id: UUID = UUID(),
        kind: PearlKind,
        title: String,
        text: String = "",
        sourceURL: URL? = nil,
        tags: [String] = [],
        ocrText: String = "",
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        attachment: PearlAttachment? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.text = text
        self.sourceURL = sourceURL
        self.tags = tags
        self.ocrText = ocrText
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.deletedAt = deletedAt
        self.attachment = attachment
    }
}

/// Search has stable order and no network or generated classifications.
public enum PearlSearch {
    public static func results(
        in items: [Pearl],
        query: String = "",
        favoritesOnly: Bool = false,
        kind: PearlKind? = nil,
        includeDeleted: Bool = false
    ) -> [Pearl] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { folded(String($0)) }
        return items.filter { item in
            guard includeDeleted || !item.isDeleted else { return false }
            guard !favoritesOnly || item.isFavorite else { return false }
            guard kind == nil || item.kind == kind else { return false }
            let fields = [item.title, item.text, item.ocrText, item.sourceURL?.absoluteString ?? "", item.originalFilename ?? ""] + item.tags
            let searchableText = folded(fields.joined(separator: "\n"))
            return terms.allSatisfy { searchableText.contains($0) }
        }.sorted(by: newestFirst)
    }

    static func newestFirst(_ lhs: Pearl, _ rhs: Pearl) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
        return lhs.id.uuidString.lowercased() < rhs.id.uuidString.lowercased()
    }

    static func folded(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
