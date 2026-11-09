import Foundation
import XCTest
@testable import PearlsCore

final class PearlStoreTests: XCTestCase {
    private var temporaryDirectory: URL!
    private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PearlsCoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try FileManager.default.removeItem(at: temporaryDirectory) }
        temporaryDirectory = nil
    }

    private func store(_ name: String = "Library") throws -> PearlStore {
        try PearlStore(rootDirectory: temporaryDirectory.appendingPathComponent(name, isDirectory: true))
    }

    private func source(_ name: String = "original.txt", bytes: Data = Data("Unmodified original\n".utf8)) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name)
        try bytes.write(to: url, options: .atomic)
        return url
    }

    func testReloadPreservesEditedMetadataSourceAndFavorite() throws {
        let originalStore = try store()
        let item = try originalStore.addLink(
            url: URL(string: "https://example.com/reading?chapter=2#note")!,
            title: " Reading ", text: "Original thought", tags: ["Design", "design", "  "],
            createdAt: fixedDate
        )
        var edit = item
        edit.text = "Revised thought"
        edit.ocrText = "Recognized text"
        edit.isFavorite = true
        let saved = try originalStore.save(edit)
        let reopened = try PearlStore(rootDirectory: originalStore.rootDirectory)

        XCTAssertEqual(try reopened.item(id: saved.id), saved)
        XCTAssertEqual(saved.createdAt, fixedDate)
        XCTAssertEqual(saved.title, "Reading")
        XCTAssertEqual(saved.tags, ["Design"])
        XCTAssertEqual(saved.sourceURL?.absoluteString, "https://example.com/reading?chapter=2#note")
        XCTAssertEqual(try reopened.search("", favoritesOnly: true).map(\.id), [saved.id])
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalStore.rootDirectory.appendingPathComponent(PearlStore.backupFilename).path))
    }

    func testStableCaptureIdentityAndCreationDateSurviveRetry() throws {
        let repository = try store()
        let captureID = UUID()
        let first = try repository.addNote(text: "Shared idea", id: captureID, createdAt: fixedDate)
        XCTAssertTrue(try repository.contains(id: captureID))
        XCTAssertEqual(first.createdAt, fixedDate)
        XCTAssertThrowsError(try repository.addNote(text: "Shared idea", id: captureID, createdAt: fixedDate)) { error in
            guard case let PearlStoreError.itemAlreadyExists(id) = error, id == captureID else {
                return XCTFail("Expected duplicate identity protection, got \(error)")
            }
        }
        XCTAssertEqual(try repository.refresh().count, 1)
    }

    func testSearchIncludesURLFilenameOCRAndDiacriticsWithStableOrdering() throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let first = Pearl(id: firstID, kind: .link, title: "Café", text: "Quiet rooms", sourceURL: URL(string: "https://example.com/architecture")!, tags: ["Interiors"], createdAt: fixedDate)
        let second = Pearl(id: secondID, kind: .image, title: "Library", ocrText: "Sunlit reading space", createdAt: fixedDate,
                           attachment: PearlAttachment(relativePath: "attachments/\(secondID.uuidString.lowercased())/Paris.jpg", originalFilename: "Paris.jpg", byteCount: 12))
        let input = [second, first]

        XCTAssertEqual(PearlSearch.results(in: input).map(\.id), [firstID, secondID])
        XCTAssertEqual(PearlSearch.results(in: input, query: "CAFE architecture interiors").map(\.id), [firstID])
        XCTAssertEqual(PearlSearch.results(in: input, query: "paris SUNLIT").map(\.id), [secondID])
        XCTAssertTrue(PearlSearch.results(in: input, query: "cafe unmatched").isEmpty)
        XCTAssertEqual(PearlSearch.results(in: input, kind: .image).map(\.id), [secondID])
    }

    func testAttachmentsUseRelativeSafePathsAndKeepOriginalBytesAndFilename() throws {
        let repository = try store()
        let bytes = Data([0, 1, 2, 255, 0, 42])
        let captureID = UUID()
        let item = try repository.addAttachment(from: source(bytes: bytes), kind: .file, originalFilename: "Draft: one/part.txt", id: captureID, createdAt: fixedDate)
        let originalURL = try XCTUnwrap(repository.attachmentURL(for: item))

        XCTAssertEqual(item.id, captureID)
        XCTAssertEqual(item.createdAt, fixedDate)
        XCTAssertEqual(item.originalFilename, "Draft: one/part.txt")
        XCTAssertEqual(item.attachmentRelativePath, "attachments/\(captureID.uuidString.lowercased())/Draft_ one_part.txt")
        XCTAssertEqual(try Data(contentsOf: originalURL), bytes)
        XCTAssertFalse(try repository.exportArchive().isEmpty)
    }

    func testRejectsAttachmentTraversalWithoutReadingOutsideLibrary() throws {
        let repository = try store()
        let itemID = UUID()
        let badPaths = [
            "../outside.txt",
            "/tmp/outside.txt",
            "attachments/\(itemID.uuidString.lowercased())/../../outside.txt",
            "attachments/\(itemID.uuidString.lowercased())/..",
            "attachments/another-id/file.txt",
            "attachments/\(itemID.uuidString.lowercased())/escape\\file.txt"
        ]
        for path in badPaths {
            let item = Pearl(id: itemID, kind: .file, title: "Invalid", createdAt: fixedDate,
                             attachment: PearlAttachment(relativePath: path, originalFilename: "file.txt", byteCount: 1))
            XCTAssertThrowsError(try repository.attachmentURL(for: item)) { error in
                guard case PearlStoreError.unsafeAttachmentPath = error else {
                    return XCTFail("Expected unsafe path rejection for \(path), got \(error)")
                }
            }
        }
        XCTAssertTrue(try repository.refresh().isEmpty)
    }

    func testRejectsSymlinkedAttachmentDirectory() throws {
        let repository = try store()
        let itemID = UUID()
        let outsideDirectory = temporaryDirectory.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        let original = outsideDirectory.appendingPathComponent("original.txt")
        let bytes = Data("Outside library".utf8)
        try bytes.write(to: original)
        let itemDirectory = repository.rootDirectory.appendingPathComponent("attachments/\(itemID.uuidString.lowercased())", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: itemDirectory, withDestinationURL: outsideDirectory)
        let item = Pearl(id: itemID, kind: .file, title: "Unsafe", createdAt: fixedDate,
                         attachment: PearlAttachment(relativePath: "attachments/\(itemID.uuidString.lowercased())/original.txt", originalFilename: "original.txt", byteCount: Int64(bytes.count)))

        XCTAssertThrowsError(try repository.attachmentURL(for: item)) { error in
            guard case PearlStoreError.unsafeAttachmentPath = error else {
                return XCTFail("Expected symbolic link rejection, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    func testArchiveRestoresIdentityOriginalBytesMetadataAndTrash() throws {
        let originalStore = try store("SourceLibrary")
        let bytes = Data([0, 255, 17, 128, 89, 10])
        let original = try source("Reference.png", bytes: bytes)
        let image = try originalStore.addAttachment(from: original, kind: .image, title: "A reference", sourceURL: URL(string: "https://example.com/reference")!, tags: ["Spaces"], ocrText: "Window", contentType: "public.png", createdAt: fixedDate)
        _ = try originalStore.setFavorite(true, for: image.id)
        try originalStore.softDelete(id: image.id)
        let note = try originalStore.addNote(title: "Thought", text: "Keep this.", createdAt: fixedDate)
        let archive = try originalStore.exportArchive()
        let destination = try store("DestinationLibrary")
        let result = try destination.importArchive(archive)

        XCTAssertEqual(result, PearlImportResult(importedCount: 2, skippedCount: 0))
        XCTAssertEqual(try destination.refresh(), try originalStore.refresh())
        XCTAssertEqual(try destination.search("").map(\.id), [note.id])
        let importedImage = try XCTUnwrap(destination.item(id: image.id))
        XCTAssertTrue(importedImage.isDeleted)
        XCTAssertTrue(importedImage.isFavorite)
        XCTAssertEqual(importedImage.attachment, image.attachment)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(destination.attachmentURL(for: importedImage))), bytes)
        XCTAssertEqual(try destination.importArchive(archive), PearlImportResult(importedCount: 0, skippedCount: 2))
        try destination.restore(id: image.id)
        XCTAssertEqual(try destination.search("Window").map(\.id), [image.id])
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(destination.attachmentURL(for: importedImage))), bytes)
    }

    func testArchiveRepairsMissingOriginalWithoutChangingMetadataOrBackup() throws {
        let repository = try store()
        let bytes = Data("An original worth keeping".utf8)
        let item = try repository.addAttachment(from: source(bytes: bytes), kind: .file, createdAt: fixedDate)
        _ = try repository.addNote(text: "Unchanged note", createdAt: fixedDate)
        let archive = try repository.exportArchive()
        let original = try XCTUnwrap(repository.attachmentURL(for: item))
        let manifest = repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)
        let backup = repository.rootDirectory.appendingPathComponent(PearlStore.backupFilename)
        let manifestBefore = try Data(contentsOf: manifest)
        let backupBefore = try Data(contentsOf: backup)
        let recordsBefore = try repository.refresh()
        try FileManager.default.removeItem(at: original)

        XCTAssertEqual(try repository.importArchive(archive),
                       PearlImportResult(importedCount: 0, skippedCount: 1, repairedCount: 1))
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(try repository.refresh(), recordsBefore)
        XCTAssertEqual(try Data(contentsOf: manifest), manifestBefore)
        XCTAssertEqual(try Data(contentsOf: backup), backupBefore)
        XCTAssertEqual(try repository.importArchive(archive),
                       PearlImportResult(importedCount: 0, skippedCount: 2, repairedCount: 0))
    }

    func testArchiveNeverRepairsOrOverwritesOriginalsWhenAnotherOriginalConflicts() throws {
        let repository = try store()
        let first = try repository.addAttachment(from: source("first.txt", bytes: Data("First original".utf8)), kind: .file, createdAt: fixedDate)
        let second = try repository.addAttachment(from: source("second.txt", bytes: Data("Second original".utf8)), kind: .file, createdAt: fixedDate)
        let archive = try repository.exportArchive()
        let missingOriginal = try XCTUnwrap(repository.attachmentURL(for: first))
        let changedOriginal = try XCTUnwrap(repository.attachmentURL(for: second))
        let changedBytes = Data("Second changed!".utf8) // Same byte count as the saved original.
        let manifest = repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)
        let metadataBefore = try Data(contentsOf: manifest)
        try FileManager.default.removeItem(at: missingOriginal)
        try changedBytes.write(to: changedOriginal, options: .atomic)

        XCTAssertThrowsError(try repository.importArchive(archive)) { error in
            guard case let PearlStoreError.archiveConflict(id) = error, id == second.id else {
                return XCTFail("Expected changed-original conflict, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingOriginal.path))
        XCTAssertEqual(try Data(contentsOf: changedOriginal), changedBytes)
        XCTAssertEqual(try Data(contentsOf: manifest), metadataBefore)
    }

    func testArchiveConflictsDoNotPartiallyImportOtherRecords() throws {
        let origin = try store("Origin")
        let shared = try origin.addNote(title: "Shared", text: "First", createdAt: fixedDate)
        let destination = try store("Destination")
        _ = try destination.importArchive(origin.exportArchive())
        var edited = try XCTUnwrap(destination.item(id: shared.id))
        edited.text = "Local changes"
        _ = try destination.save(edited)
        let other = try origin.addAttachment(from: source(), kind: .file, createdAt: fixedDate)
        let before = try destination.refresh()

        XCTAssertThrowsError(try destination.importArchive(origin.exportArchive())) { error in
            guard case PearlStoreError.archiveConflict = error else {
                return XCTFail("Expected same-identity conflict, got \(error)")
            }
        }
        XCTAssertEqual(try destination.refresh(), before)
        XCTAssertFalse(try destination.contains(id: other.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.rootDirectory.appendingPathComponent(try XCTUnwrap(other.attachmentRelativePath)).path))
    }

    func testUnsafeArchiveIsRejectedBeforeAnyImport() throws {
        let repository = try store()
        let itemID = UUID()
        let path = "attachments/\(itemID.uuidString.lowercased())/../../escaped.txt"
        let item = Pearl(id: itemID, kind: .file, title: "Unsafe", createdAt: fixedDate,
                         attachment: PearlAttachment(relativePath: path, originalFilename: "escaped.txt", byteCount: 1))
        let archive = PearlArchiveDocument(items: [item], attachments: [PearlArchiveAttachment(itemID: itemID, relativePath: path, data: Data([1]))])
        XCTAssertThrowsError(try repository.importArchive(PearlDocumentCoding.encoder().encode(archive)))
        XCTAssertTrue(try repository.refresh().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.rootDirectory.appendingPathComponent("escaped.txt").path))
    }

    func testMalformedMetadataRecoversBackupAndPreservesDamagedCopyAndOriginals() throws {
        let repository = try store()
        let bytes = Data("Kept original".utf8)
        let original = try repository.addAttachment(from: source(bytes: bytes), kind: .file, createdAt: fixedDate)
        _ = try repository.addNote(text: "Most recent change")
        let malformed = Data("{broken metadata".utf8)
        try malformed.write(to: repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename), options: .atomic)
        let reopened = try PearlStore(rootDirectory: repository.rootDirectory)

        XCTAssertEqual(try reopened.refresh().map(\.id), [original.id])
        let recovery = try XCTUnwrap(reopened.recoveryNotice)
        XCTAssertEqual(recovery.recoveredItemCount, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(recovery.damagedMetadataURL)), malformed)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(reopened.attachmentURL(for: original))), bytes)
        XCTAssertNil(try PearlStore(rootDirectory: repository.rootDirectory).recoveryNotice)
    }

    func testTwoInvalidMetadataCopiesAreNeverReplacedWithEmptyLibrary() throws {
        let repository = try store()
        _ = try repository.addNote(text: "Original record")
        let manifest = repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)
        let backup = repository.rootDirectory.appendingPathComponent(PearlStore.backupFilename)
        let first = Data("broken current".utf8)
        let second = Data("broken previous".utf8)
        try first.write(to: manifest, options: .atomic)
        try second.write(to: backup, options: .atomic)

        XCTAssertThrowsError(try PearlStore(rootDirectory: repository.rootDirectory)) { error in
            guard case PearlStoreError.metadataUnrecoverable = error else {
                return XCTFail("Expected explicit recovery failure, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: manifest), first)
        XCTAssertEqual(try Data(contentsOf: backup), second)
    }

    func testNewerSchemaDoesNotRollBackToOldBackup() throws {
        let repository = try store()
        _ = try repository.addNote(text: "Current data")
        let manifest = repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        json["schemaVersion"] = 99
        let newerData = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        try newerData.write(to: manifest, options: .atomic)

        XCTAssertThrowsError(try PearlStore(rootDirectory: repository.rootDirectory)) { error in
            guard case PearlStoreError.unsupportedSchema(99) = error else {
                return XCTFail("Expected version compatibility error, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: manifest), newerData)
    }

    func testNewerIncompatibleSchemaDoesNotLookLikeRecoverableCorruption() throws {
        let repository = try store()
        _ = try repository.addNote(text: "Current data")
        let manifest = repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)
        let backup = repository.rootDirectory.appendingPathComponent(PearlStore.backupFilename)
        let backupBefore = try Data(contentsOf: backup)
        let future: [String: Any] = [
            "format": "com.pearls.library", "schemaVersion": 2,
            "items": [["kind": "future-audio", "futureField": true]]
        ]
        let newerData = try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
        try newerData.write(to: manifest, options: .atomic)

        XCTAssertThrowsError(try PearlStore(rootDirectory: repository.rootDirectory)) { error in
            guard case PearlStoreError.unsupportedSchema(2) = error else {
                return XCTFail("Expected unsupported schema before item decoding, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: manifest), newerData)
        XCTAssertEqual(try Data(contentsOf: backup), backupBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.rootDirectory.appendingPathComponent("Recovery").path))
    }

    func testNewerIncompatibleBackupIsPreservedAlongsideMalformedPrimary() throws {
        let repository = try store()
        _ = try repository.addNote(text: "Current data")
        let manifest = repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)
        let backup = repository.rootDirectory.appendingPathComponent(PearlStore.backupFilename)
        let malformed = Data("{damaged current metadata".utf8)
        let future: [String: Any] = [
            "format": "com.pearls.library", "schemaVersion": 2,
            "items": [["kind": "future-audio", "futureField": true]]
        ]
        let newerBackup = try JSONSerialization.data(withJSONObject: future, options: [.sortedKeys])
        try malformed.write(to: manifest, options: .atomic)
        try newerBackup.write(to: backup, options: .atomic)

        XCTAssertThrowsError(try PearlStore(rootDirectory: repository.rootDirectory)) { error in
            guard case PearlStoreError.unsupportedSchema(2) = error else {
                return XCTFail("Expected explicit newer-backup version error, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: manifest), malformed)
        XCTAssertEqual(try Data(contentsOf: backup), newerBackup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.rootDirectory.appendingPathComponent("Recovery").path))
    }

    func testMissingMetadataWithOriginalsDoesNotCreateEmptyLibrary() throws {
        let repository = try store()
        let item = try repository.addAttachment(from: source(), kind: .file)
        let original = try XCTUnwrap(repository.attachmentURL(for: item))
        let manifest = repository.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)
        try FileManager.default.removeItem(at: manifest)
        try FileManager.default.removeItem(at: repository.rootDirectory.appendingPathComponent(PearlStore.backupFilename))

        XCTAssertThrowsError(try PearlStore(rootDirectory: repository.rootDirectory)) { error in
            guard case PearlStoreError.missingMetadataWithOriginals = error else {
                return XCTFail("Expected orphan protection, got \(error)")
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: manifest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
    }

    func testMissingOriginalPreservesMetadataButBlocksIncompleteExport() throws {
        let repository = try store()
        let item = try repository.addAttachment(from: source(), kind: .file)
        let original = try XCTUnwrap(repository.attachmentURL(for: item))
        try FileManager.default.removeItem(at: original)

        XCTAssertEqual(try repository.refresh().map(\.id), [item.id])
        XCTAssertThrowsError(try repository.exportArchive()) { error in
            guard case PearlStoreError.attachmentMissing = error else {
                return XCTFail("Expected missing original error, got \(error)")
            }
        }
    }

    func testSeparateStoresReloadBeforeEachMutation() throws {
        let first = try store()
        let second = try PearlStore(rootDirectory: first.rootDirectory)
        let a = try first.addNote(text: "A")
        let b = try second.addNote(text: "B")
        XCTAssertEqual(Set(try first.refresh().map(\.id)), Set([a.id, b.id]))
        XCTAssertEqual(Set(try second.refresh().map(\.id)), Set([a.id, b.id]))
    }

    func testOversizedAttachmentFailsBeforeMetadataOrOriginalIsAdded() throws {
        let repository = try store()
        let large = try source("large.bin", bytes: Data())
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(PearlStore.maximumAttachmentBytes + 1))
        try handle.close()

        XCTAssertThrowsError(try repository.addAttachment(from: large, kind: .file)) { error in
            guard case PearlStoreError.attachmentTooLarge = error else {
                return XCTFail("Expected attachment limit, got \(error)")
            }
        }
        XCTAssertTrue(try repository.refresh().isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: repository.rootDirectory.appendingPathComponent("attachments").path).isEmpty)
    }
}
