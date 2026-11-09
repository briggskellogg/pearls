import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let pearlsArchive = UTType(exportedAs: "com.briggskellogg.pearls.archive", conformingTo: .data)
}

struct PearlsArchiveDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pearlsArchive, .json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
