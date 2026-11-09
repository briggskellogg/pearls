import Foundation

/// A presentation snapshot. The app's repository remains the source of truth.
struct PearlsDisplayItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var kind: PearlsItemKind
    var text: String
    var sourceURL: URL?
    var attachmentURL: URL?
    var originalFilename: String?
    var createdAt: Date
    var isFavorite: Bool
    var recognizedText: String

    init(
        id: UUID,
        title: String,
        kind: PearlsItemKind,
        text: String = "",
        sourceURL: URL? = nil,
        attachmentURL: URL? = nil,
        originalFilename: String? = nil,
        createdAt: Date,
        isFavorite: Bool = false,
        recognizedText: String = ""
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.text = text
        self.sourceURL = sourceURL
        self.attachmentURL = attachmentURL
        self.originalFilename = originalFilename
        self.createdAt = createdAt
        self.isFavorite = isFavorite
        self.recognizedText = recognizedText
    }

    var displayTitle: String {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? kind.untitledLabel : cleaned
    }

    var sourceLabel: String? {
        guard let host = sourceURL?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let haystack = [title, text, sourceURL?.absoluteString ?? "", originalFilename ?? "", recognizedText]
            .joined(separator: "\n")
        return terms.allSatisfy { haystack.localizedStandardContains($0) }
    }
}

enum PearlsItemKind: String, Hashable, Sendable, CaseIterable {
    case note, link, image, file

    var label: String {
        switch self {
        case .note: return "Note"
        case .link: return "Link"
        case .image: return "Image"
        case .file: return "File"
        }
    }

    var symbol: String {
        switch self {
        case .note: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var untitledLabel: String { "Untitled \(label.lowercased())" }
}

struct PearlsDraft: Sendable {
    var title: String
    var text: String

    /// Only a single, complete HTTP(S) address is treated as a link.
    var sourceURL: URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: \.isWhitespace),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty else { return nil }
        return components.url
    }
}
