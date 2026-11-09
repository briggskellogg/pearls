import Foundation
import XCTest
@testable import PearlsCore

final class PearlSyncTests: XCTestCase {
    private var root: URL!
    private let date = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PearlsSyncTests-\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func store(_ name: String) throws -> PearlStore { try PearlStore(rootDirectory: root.appendingPathComponent(name)) }
    private func folder(_ name: String = "Cloud") -> URL { root.appendingPathComponent(name, isDirectory: true) }
    private func edit(_ store: PearlStore, id: UUID, text: String) throws {
        var item = try XCTUnwrap(store.item(id: id))
        item.text = text
        _ = try store.save(item)
    }
    private func sync(_ stores: [PearlStore], cloud: URL? = nil) throws {
        for store in stores { _ = try store.synchronize(with: cloud ?? folder()) }
    }
    private func versions(_ cloud: URL? = nil) throws -> [URL] {
        let directory = (cloud ?? folder()).appendingPathComponent("versions")
        return try PearlSyncFiles.children(directory).flatMap { try PearlSyncFiles.children($0) }.filter { $0.pathExtension == "json" }
    }
    private func publish(_ version: PearlSyncVersion, to cloud: URL? = nil) throws -> URL {
        let data = try PearlDocumentCoding.encoder().encode(version)
        let target = PearlSyncFiles.versionURL(root: cloud ?? folder(), itemID: version.item.id, revision: PearlSyncFiles.hash(data))
        try PearlSyncFiles.writeImmutable(data, to: target)
        return target
    }

    func testTwoDeviceEditCycleIsIdempotentAndWindowsReadable() throws {
        let a = try store("A"), b = try store("B")
        let note = try a.addNote(title: "Reading", text: "First", createdAt: date)
        try sync([a, b])
        try edit(b, id: note.id, text: "Second")
        try sync([b, a])
        XCTAssertEqual(try a.item(id: note.id)?.text, "Second")
        XCTAssertEqual(try a.refresh(), try b.refresh())
        for _ in 0..<4 { try sync([a, b]) }
        XCTAssertEqual(try versions().count, 2)
        XCTAssertEqual(try a.synchronize(with: folder()).uploadedVersionCount, 0)
        let record = try XCTUnwrap(versions().first)
        XCTAssertTrue(String(data: try Data(contentsOf: record), encoding: .utf8)!.contains("\"text\""))
    }

    func testConcurrentEditsConvergeToStableEditableConflictCopy() throws {
        let a = try store("A"), b = try store("B"), c = try store("C")
        let note = try a.addNote(title: "Thought", text: "Base", createdAt: date)
        try sync([a, b])
        try edit(a, id: note.id, text: "Mac edit")
        try edit(b, id: note.id, text: "Phone edit")
        try sync([a, b, a, c])
        XCTAssertEqual(Set(try a.refresh().map(\.text)), Set(["Mac edit", "Phone edit"]))
        let ids = Set(try a.refresh().map(\.id))
        for _ in 0..<5 { try sync([a, b, c]) }
        XCTAssertEqual(Set(try c.refresh().map(\.id)), ids)
        XCTAssertEqual(try a.refresh().count, 2)
        XCTAssertEqual(try versions().count, 4)
        let copy = try XCTUnwrap(a.refresh().first { $0.id != note.id })
        XCTAssertEqual(copy.createdAt, date)
        try edit(a, id: copy.id, text: "Edited preserved copy")
        try sync([a, b, c, a])
        XCTAssertEqual(try b.item(id: copy.id)?.text, "Edited preserved copy")
        XCTAssertEqual(try a.refresh().count, 2)
    }

    func testStaleDeviceCannotResurrectDeletionAndObservedRestorePropagates() throws {
        let a = try store("A"), b = try store("B")
        let note = try a.addNote(text: "Keep", createdAt: date)
        try sync([a, b])
        try a.softDelete(id: note.id)
        try sync([a, b, a])
        XCTAssertTrue(try XCTUnwrap(b.item(id: note.id)).isDeleted)
        XCTAssertEqual(try b.refresh().count, 1)
        try b.restore(id: note.id)
        try sync([b, a])
        XCTAssertFalse(try XCTUnwrap(a.item(id: note.id)).isDeleted)
        XCTAssertEqual(try versions().count, 3)
    }

    func testConcurrentDeleteAndEditKeepsTombstoneAndPreservesLiveDraft() throws {
        let a = try store("A"), b = try store("B")
        let note = try a.addNote(text: "Base", createdAt: date)
        try sync([a, b])
        try a.softDelete(id: note.id)
        try edit(b, id: note.id, text: "Offline draft")
        try sync([a, b, a])
        XCTAssertTrue(try XCTUnwrap(a.item(id: note.id)).isDeleted)
        let active = try a.search("")
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.text, "Offline draft")
        XCTAssertNotEqual(active.first?.id, note.id)
    }

    func testConcurrentDifferentOriginalsKeepEveryByteWithoutPathPingPong() throws {
        let a = try store("A"), b = try store("B"), c = try store("C")
        let id = UUID()
        let first = root.appendingPathComponent("first.txt"), second = root.appendingPathComponent("second.txt")
        try Data("first".utf8).write(to: first)
        try Data("other".utf8).write(to: second)
        _ = try a.addAttachment(from: first, kind: .file, originalFilename: "same.txt", id: id, createdAt: date)
        _ = try b.addAttachment(from: second, kind: .file, originalFilename: "same.txt", id: id, createdAt: date)
        try sync([a, b, a, c])
        let copies = try c.refresh()
        XCTAssertEqual(copies.count, 2)
        let bytes = try copies.map { try Data(contentsOf: XCTUnwrap(c.attachmentURL(for: $0))) }
        XCTAssertEqual(Set(bytes), Set([Data("first".utf8), Data("other".utf8)]))
        for _ in 0..<4 { try sync([a, b, c]) }
        XCTAssertEqual(try versions().count, 3)
        XCTAssertEqual(try c.refresh().count, 2)
        let originals = try PearlSyncFiles.children(folder().appendingPathComponent("originals"))
        XCTAssertEqual(originals.count, 2)
        XCTAssertTrue(try originals.allSatisfy { try PearlSyncFiles.children($0).first?.lastPathComponent == "same.txt" })
        var selected = try XCTUnwrap(a.item(id: id))
        let selectedBytes = try Data(contentsOf: XCTUnwrap(a.attachmentURL(for: selected)))
        selected.title = "Edited after resolving the fork"
        selected.isFavorite = true
        _ = try a.save(selected)
        for _ in 0..<4 { try sync([a, b, c]) }
        XCTAssertEqual(try versions().count, 4)
        for peer in [a, b, c] {
            let edited = try XCTUnwrap(peer.item(id: id))
            XCTAssertEqual(edited.title, selected.title)
            XCTAssertTrue(edited.isFavorite)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(peer.attachmentURL(for: edited))), selectedBytes)
            XCTAssertEqual(try peer.refresh().count, 2)
        }
    }

    func testMissingOriginalDefersUntilDownloadedAndTamperNeverImports() throws {
        let a = try store("A"), b = try store("B"), c = try store("C")
        let source = root.appendingPathComponent("file.bin")
        try Data([0, 1, 2, 3]).write(to: source)
        let item = try a.addAttachment(from: source, kind: .file, createdAt: date)
        try sync([a])
        let data = try Data(contentsOf: XCTUnwrap(versions().first))
        let version = try PearlDocumentCoding.decoder().decode(PearlSyncVersion.self, from: data)
        let original = try XCTUnwrap(version.original)
        let path = PearlSyncFiles.originalURL(root: folder(), original: original)
        let preserved = try Data(contentsOf: path)
        try FileManager.default.removeItem(at: path)
        let before = try Data(contentsOf: b.rootDirectory.appendingPathComponent(PearlStore.manifestFilename))
        XCTAssertGreaterThan(try b.synchronize(with: folder()).deferredFileCount, 0)
        XCTAssertEqual(try b.refresh().count, 0)
        XCTAssertEqual(try Data(contentsOf: b.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)), before)
        try preserved.write(to: path)
        try sync([b])
        XCTAssertEqual(try b.refresh().first?.id, item.id)
        try Data([9, 9, 9, 9]).write(to: path)
        let knownPeerResult = try b.synchronize(with: folder())
        XCTAssertGreaterThan(knownPeerResult.deferredFileCount, 0)
        XCTAssertFalse(knownPeerResult.issues.isEmpty)
        let knownItem = try XCTUnwrap(b.item(id: item.id))
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(b.attachmentURL(for: knownItem))), preserved)
        XCTAssertGreaterThan(try c.synchronize(with: folder()).deferredFileCount, 0)
        XCTAssertEqual(try c.refresh().count, 0)
        XCTAssertEqual(try Data(contentsOf: path), Data([9, 9, 9, 9]))
    }

    func testExistingLocalOriginalIsCheckedByHashNotSize() throws {
        let a = try store("A")
        let source = root.appendingPathComponent("file.bin")
        try Data([1, 2, 3]).write(to: source)
        _ = try a.addAttachment(from: source, kind: .file, createdAt: date)
        try sync([a])
        let item = try XCTUnwrap(a.refresh().first)
        let original = try XCTUnwrap(a.attachmentURL(for: item))
        try Data([7, 8, 9]).write(to: original)
        XCTAssertGreaterThan(try a.synchronize(with: folder()).deferredFileCount, 0)
        XCTAssertEqual(try Data(contentsOf: original), Data([7, 8, 9]))
        XCTAssertEqual(try a.refresh().first, item)
    }

    func testSmallTransferBudgetEventuallyPublishesImportsAndVerifiesEveryOriginal() throws {
        let a = try store("A"), b = try store("B")
        var expected: [UUID: Data] = [:]
        for index in 0..<10 {
            let data = Data(repeating: UInt8(index), count: 8)
            let source = root.appendingPathComponent("small-\(index).bin")
            try data.write(to: source)
            let item = try a.addAttachment(from: source, kind: .file, createdAt: date)
            expected[item.id] = data
        }
        var sawDeferred = false
        for _ in 0..<20 {
            for peer in [a, b] {
                do {
                    let result = try peer.synchronize(with: folder(), maximumOriginalBytesPerPhase: 64)
                    sawDeferred = sawDeferred || result.deferredFileCount > 0
                } catch PearlSyncError.limitExceeded { sawDeferred = true }
            }
        }
        XCTAssertTrue(sawDeferred)
        XCTAssertEqual(try versions().count, 10)
        for peer in [a, b] {
            XCTAssertEqual(try peer.refresh().count, expected.count)
            for item in try peer.refresh() {
                XCTAssertEqual(try Data(contentsOf: XCTUnwrap(peer.attachmentURL(for: item))), expected[item.id])
            }
        }
        // Corrupt a later entry: rotating checks must reach it despite a budget
        // too small to recheck all earlier entries in a single pass.
        let last = try XCTUnwrap(a.refresh().sorted { $0.id.uuidString < $1.id.uuidString }.last)
        let revisionPath = try XCTUnwrap(versions().first { $0.deletingLastPathComponent().lastPathComponent == last.id.uuidString.lowercased() })
        let version = try PearlDocumentCoding.decoder().decode(PearlSyncVersion.self, from: Data(contentsOf: revisionPath))
        let remoteOriginal = PearlSyncFiles.originalURL(root: folder(), original: try XCTUnwrap(version.original))
        let corrupt = Data(repeating: UInt8.max, count: 8)
        try corrupt.write(to: remoteOriginal)
        var detectedCorruption = false
        for _ in 0..<10 {
            let result = try b.synchronize(with: folder(), maximumOriginalBytesPerPhase: 64)
            detectedCorruption = detectedCorruption || result.issues.contains(PearlSyncError.changedFile.localizedDescription)
        }
        XCTAssertTrue(detectedCorruption)
        XCTAssertEqual(try Data(contentsOf: remoteOriginal), corrupt)
        XCTAssertEqual(try versions().count, 10)
    }

    func testCachedAndRemoteRevisionMetadataCountOnceTowardCapacity() throws {
        let a = try store("A"), b = try store("B")
        let note = try a.addNote(text: String(repeating: "a", count: 1_000), createdAt: date)
        try sync([a])
        try edit(a, id: note.id, text: String(repeating: "b", count: 1_000))
        try sync([a, b])
        let metadataBytes = try versions().reduce(0) { $0 + (try Data(contentsOf: $1)).count }
        for peer in [a, b, a, b] {
            let result = try peer.synchronize(with: folder(), maximumOriginalBytesPerPhase: 64, maximumMetadataBytes: metadataBytes)
            XCTAssertTrue(result.issues.isEmpty)
            XCTAssertEqual(result.deferredFileCount, 0)
        }
        XCTAssertEqual(try versions().count, 2)
        XCTAssertThrowsError(try b.synchronize(with: folder(), maximumOriginalBytesPerPhase: 64, maximumMetadataBytes: metadataBytes - 1)) { error in
            guard case PearlSyncError.capacityExceeded = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testDelayedAncestorCannotBeMistakenForIndependentNewestRoot() throws {
        let a = try store("A"), b = try store("B")
        let note = try a.addNote(text: "Base", createdAt: date)
        try sync([a])
        let parent = try XCTUnwrap(versions().first)
        try edit(a, id: note.id, text: "Descendant")
        try sync([a])
        let child = try XCTUnwrap(versions().first { $0 != parent })
        let delayed = folder("Delayed")
        try FileManager.default.createDirectory(at: delayed, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: folder().appendingPathComponent(PearlSyncFiles.markerName), to: delayed.appendingPathComponent(PearlSyncFiles.markerName))
        let childVersion = try PearlDocumentCoding.decoder().decode(PearlSyncVersion.self, from: Data(contentsOf: child))
        _ = try publish(childVersion, to: delayed)
        XCTAssertGreaterThan(try b.synchronize(with: delayed).deferredFileCount, 0)
        XCTAssertTrue(try b.refresh().isEmpty)
        let parentVersion = try PearlDocumentCoding.decoder().decode(PearlSyncVersion.self, from: Data(contentsOf: parent))
        _ = try publish(parentVersion, to: delayed)
        _ = try b.synchronize(with: delayed)
        XCTAssertEqual(try b.item(id: note.id)?.text, "Descendant")
        XCTAssertEqual(try b.refresh().count, 1)
    }

    func testNewCollectionAndReconnectKeepIndependentObservedParents() throws {
        let a = try store("A"), b = try store("B")
        let note = try a.addNote(text: "Base", createdAt: date)
        try sync([a])
        let other = folder("OtherCloud")
        XCTAssertEqual(try a.synchronize(with: other).uploadedVersionCount, 1)
        XCTAssertNotEqual(try PearlSyncFiles.marker(in: folder())?.collectionID, try PearlSyncFiles.marker(in: other)?.collectionID)
        try edit(a, id: note.id, text: "While connected elsewhere")
        _ = try a.synchronize(with: other)
        try sync([a, b])
        XCTAssertEqual(try b.item(id: note.id)?.text, "While connected elsewhere")
        XCTAssertEqual(try b.refresh().count, 1)
        let reopened = try PearlStore(rootDirectory: a.rootDirectory)
        XCTAssertEqual(try reopened.synchronize(with: other).uploadedVersionCount, 0)
    }

    func testMalformedAndUnsafeVersionsDoNotChangeLocalMetadata() throws {
        let b = try store("B")
        _ = try PearlSyncFiles.openCollection(folder())
        let outside = root.appendingPathComponent("private.txt")
        try Data("private sentinel".utf8).write(to: outside)
        let id = UUID()
        let item = Pearl(id: id, kind: .file, title: "Unsafe", createdAt: date,
                         attachment: PearlAttachment(relativePath: "../../private.txt", originalFilename: "../private.txt", byteCount: 16))
        _ = try publish(PearlSyncVersion(item: item, parents: [], original: PearlSyncOriginal(sha256: String(repeating: "a", count: 64), filename: "../private.txt")))
        let before = try Data(contentsOf: b.rootDirectory.appendingPathComponent(PearlStore.manifestFilename))
        XCTAssertGreaterThan(try b.synchronize(with: folder()).deferredFileCount, 0)
        XCTAssertEqual(try Data(contentsOf: b.rootDirectory.appendingPathComponent(PearlStore.manifestFilename)), before)
        XCTAssertEqual(try Data(contentsOf: outside), Data("private sentinel".utf8))
    }

    func testUnknownFoldersAndSymlinksAreRejectedWithoutWrites() throws {
        let a = try store("A")
        try FileManager.default.createDirectory(at: folder(), withIntermediateDirectories: true)
        let unrelated = folder().appendingPathComponent("source.swift")
        try Data("project file".utf8).write(to: unrelated)
        XCTAssertThrowsError(try a.synchronize(with: folder()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder().appendingPathComponent(PearlSyncFiles.markerName).path))
        let linked = folder("Linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: folder())
        XCTAssertThrowsError(try PearlStore.validateSyncDirectory(linked))
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("project file".utf8))
    }

    func testStagingFilesAreIgnoredButNeverRemovedAndImmutableFilesNeverReplace() throws {
        let a = try store("A")
        try FileManager.default.createDirectory(at: folder(), withIntermediateDirectories: true)
        let staging = folder().appendingPathComponent(".\(UUID().uuidString).partial")
        try Data("incomplete marker".utf8).write(to: staging)
        _ = try a.addNote(text: "Saved", createdAt: date)
        try sync([a])
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
        let marker = folder().appendingPathComponent(PearlSyncFiles.markerName)
        let before = try Data(contentsOf: marker)
        XCTAssertThrowsError(try PearlSyncFiles.writeImmutable(Data("different".utf8), to: marker))
        XCTAssertEqual(try Data(contentsOf: marker), before)
    }

    func testDeepHistoryUsesCausalParentsRatherThanClockOrder() throws {
        let b = try store("B")
        _ = try PearlSyncFiles.openCollection(folder())
        let id = UUID()
        var parent: [String] = []
        for index in 0..<150 {
            let item = Pearl(id: id, kind: .note, title: "History", text: "Step \(index)", createdAt: date, updatedAt: date)
            let path = try publish(PearlSyncVersion(item: item, parents: parent, original: nil))
            parent = [path.deletingPathExtension().lastPathComponent]
        }
        try sync([b])
        XCTAssertEqual(try b.item(id: id)?.text, "Step 149")
        XCTAssertEqual(try b.refresh().count, 1)
    }

    func testAtomicNoteDraftUpdatesMatchingBaseAndPreservesConcurrentOrDeletedNote() throws {
        let a = try store("A")
        let note = try a.addNote(title: "Title", text: "Base", createdAt: date)
        let updated = try a.saveNoteDraft(id: note.id, title: "Title", text: "First", originalTitle: "Title", originalText: "Base")
        XCTAssertEqual(updated.id, note.id)
        let stale = try a.saveNoteDraft(id: note.id, title: "Title", text: "Stale draft", originalTitle: "Title", originalText: "Base")
        XCTAssertNotEqual(stale.id, note.id)
        XCTAssertEqual(try a.item(id: note.id)?.text, "First")
        try a.softDelete(id: note.id)
        let deletedDraft = try a.saveNoteDraft(id: note.id, title: "Title", text: "After deletion", originalTitle: "Title", originalText: "First")
        XCTAssertNotEqual(deletedDraft.id, note.id)
        XCTAssertTrue(try XCTUnwrap(a.item(id: note.id)).isDeleted)
        XCTAssertEqual(deletedDraft.text, "After deletion")
    }
}
