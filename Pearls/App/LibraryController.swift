import Foundation
import SwiftUI
import UniformTypeIdentifiers
import PearlsCore

private struct LibrarySnapshot: Sendable {
    let entries: [(Pearl, URL?)]
    let deletedEntries: [(Pearl, URL?)]
    let recoveryMessage: String?
}

private struct InboxImportResult: Sendable {
    let importedCount: Int
    let issues: [String]
}

/// All disk operations are isolated from the main actor and serialized here.
private actor LibraryRepository {
    private let store: PearlStore

    init(directory: URL) throws { store = try PearlStore(rootDirectory: directory) }

    func snapshot() throws -> LibrarySnapshot {
        let all = try store.refresh()
        var unavailableOriginals = 0
        func entry(_ pearl: Pearl) throws -> (Pearl, URL?) {
            do { return (pearl, try store.attachmentURL(for: pearl)) }
            catch PearlStoreError.attachmentMissing {
                unavailableOriginals += 1
                return (pearl, nil)
            } catch PearlStoreError.attachmentSizeMismatch {
                unavailableOriginals += 1
                return (pearl, nil)
            }
        }
        let entries = try all.filter { !$0.isDeleted }.map(entry)
        let deleted = try all.filter(\.isDeleted).map(entry)
        var messages = [store.recoveryNotice?.message].compactMap { $0 }
        if unavailableOriginals > 0 {
            messages.append("\(unavailableOriginals) original files are missing or changed. Their saved records remain here. Restore a complete backup or import the originals again.")
        }
        return LibrarySnapshot(entries: entries, deletedEntries: deleted,
                               recoveryMessage: messages.isEmpty ? nil : messages.joined(separator: "\n\n"))
    }

    func create(_ draft: PearlsDraft) throws {
        if let url = draft.sourceURL {
            _ = try store.addLink(url: url, title: draft.title)
        } else {
            _ = try store.addNote(title: draft.title, text: draft.text)
        }
    }

    func editNote(id: UUID, title: String, text: String) throws {
        guard var item = try store.item(id: id), item.kind == .note else {
            throw PearlStoreError.itemNotFound(id)
        }
        item.title = title
        item.text = text
        _ = try store.save(item)
    }

    func favorite(id: UUID, value: Bool) throws { _ = try store.setFavorite(value, for: id) }
    func remove(id: UUID) throws { try store.softDelete(id: id) }
    func restore(id: UUID) throws { try store.restore(id: id) }

    func importOriginal(_ url: URL) throws -> Pearl {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let type = UTType(filenameExtension: url.pathExtension)
        let kind: PearlKind = type?.conforms(to: .image) == true ? .image : .file
        return try store.addAttachment(from: url, kind: kind,
            title: url.deletingPathExtension().lastPathComponent,
            contentType: type?.identifier)
    }

    func recognizedText(_ text: String, for id: UUID) throws {
        guard !text.isEmpty, var item = try store.item(id: id), !item.isDeleted else { return }
        item.ocrText = text
        _ = try store.save(item)
    }

    func exportArchive() throws -> Data { try store.exportArchive() }

    func importArchive(at url: URL) throws -> PearlImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true,
              let size = values.fileSize, size <= PearlStore.maximumArchiveBytes else {
            throw PearlStoreError.archiveTooLarge
        }
        return try store.importArchive(Data(contentsOf: url, options: .mappedIfSafe))
    }

    func consumeSharedItems() throws -> InboxImportResult {
        guard AppPaths.sharedContainer != nil else { return InboxImportResult(importedCount: 0, issues: []) }
        let inbox = try AppPaths.sharedInbox()
        let directories = try FileManager.default.contentsOfDirectory(at: inbox,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        var imported = 0
        var issues: [String] = []
        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let flags = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard flags.isDirectory == true, flags.isSymbolicLink != true,
                      UUID(uuidString: directory.lastPathComponent) != nil,
                      FileManager.default.fileExists(atPath: directory.appendingPathComponent("capture.json").path) else { continue }
                let capture = try PendingCapture.read(from: directory)
                if try store.item(id: capture.id) == nil {
                    if let original = try capture.originalURL(in: directory) {
                        let kind: PearlKind = capture.kind == "image" ? .image : .file
                        _ = try store.addAttachment(from: original, kind: kind,
                            title: capture.title, text: capture.text, sourceURL: capture.sourceURL,
                            contentType: capture.contentType, originalFilename: capture.originalFilename,
                            id: capture.id, createdAt: capture.createdAt)
                    } else if capture.kind == "link", let url = capture.sourceURL {
                        _ = try store.addLink(url: url, title: capture.title, text: capture.text,
                            id: capture.id, createdAt: capture.createdAt)
                    } else if capture.kind == "note" {
                        _ = try store.addNote(title: capture.title, text: capture.text,
                            id: capture.id, createdAt: capture.createdAt)
                    } else { throw CaptureError.invalidCapture }
                    imported += 1
                }
                // The UUID is durable before cleanup. A retry cannot duplicate a capture.
                try FileManager.default.removeItem(at: directory)
            } catch {
                // A bad capture must not prevent later, independent captures from importing.
                issues.append(error.localizedDescription)
            }
        }
        return InboxImportResult(importedCount: imported, issues: issues)
    }
}

@MainActor
final class LibraryController: ObservableObject {
    @Published private(set) var items: [PearlsDisplayItem] = []
    @Published private(set) var deletedItems: [PearlsDisplayItem] = []
    @Published private(set) var isReady = false
    @Published private(set) var opening = true
    @Published private(set) var loadError: String?
    @Published var notice: String?
    @Published private(set) var lastDeletedID: UUID?
    @Published private(set) var isBusy = false

    private var repository: LibraryRepository?
    private var openingTask: Task<LibraryRepository, Error>?
    private var indexingTask: Task<Void, Never>?
    private var indexedThisSession = Set<UUID>()
    private var shownRecoveryMessage: String?

    func open() async {
        opening = true
        defer { opening = false }
        do {
            if repository == nil {
                let task = openingTask ?? Task.detached(priority: .userInitiated) {
                    try LibraryRepository(directory: AppPaths.libraryDirectory())
                }
                openingTask = task
                defer { openingTask = nil }
                repository = try await task.value
            }
            try await reload()
            isReady = true
            loadError = nil
            await receiveSharedItems()
            startIndexing()
        } catch {
            isReady = false
            loadError = error.localizedDescription
        }
    }

    func create(_ draft: PearlsDraft) async throws {
        guard let repository else { throw CocoaError(.fileReadUnknown) }
        try await repository.create(draft)
        try await reload()
    }

    func updateNote(id: UUID, title: String, text: String) async throws {
        guard let repository else { throw CocoaError(.fileReadUnknown) }
        try await repository.editNote(id: id, title: title, text: text)
        try await reload()
    }

    func setFavorite(id: UUID, value: Bool) async throws {
        guard let repository else { throw CocoaError(.fileReadUnknown) }
        try await repository.favorite(id: id, value: value)
        try await reload()
    }

    func delete(id: UUID) async throws {
        guard let repository else { throw CocoaError(.fileReadUnknown) }
        try await repository.remove(id: id)
        lastDeletedID = id
        try await reload()
    }

    func undoDelete() async {
        guard let id = lastDeletedID, let repository else { return }
        do {
            try await repository.restore(id: id)
            lastDeletedID = nil
            try await reload()
        } catch { notice = error.localizedDescription }
    }

    func restore(id: UUID) async {
        guard let repository else { return }
        do {
            try await repository.restore(id: id)
            if lastDeletedID == id { lastDeletedID = nil }
            try await reload()
            startIndexing()
        } catch { notice = error.localizedDescription }
    }

    func importFiles(_ urls: [URL]) async {
        guard let repository else { return }
        isBusy = true
        defer { isBusy = false }
        var failures: [String] = []
        for url in urls {
            do { _ = try await repository.importOriginal(url) }
            catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        do { try await reload() }
        catch { failures.append(error.localizedDescription) }
        if !failures.isEmpty { notice = failures.joined(separator: "\n\n") }
        startIndexing()
    }

    func importArchive(_ url: URL) async {
        guard let repository else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await repository.importArchive(at: url)
            try await reload()
            notice = "Imported \(result.importedCount) pearls, restored \(result.repairedCount) missing originals, and kept \(result.skippedCount) unchanged items."
            startIndexing()
        } catch { notice = error.localizedDescription }
    }

    func archiveData() async throws -> Data {
        guard let repository else { throw CocoaError(.fileReadUnknown) }
        isBusy = true
        defer { isBusy = false }
        return try await repository.exportArchive()
    }

    func receiveSharedItems() async {
        guard isReady, let repository else { return }
        do {
            let result = try await repository.consumeSharedItems()
            if result.importedCount > 0 { try await reload(); startIndexing() }
            if !result.issues.isEmpty {
                notice = "\(result.issues.count) shared items need attention and remain saved in the sharing inbox. "
                    + result.issues.prefix(3).joined(separator: "\n\n")
            }
        } catch {
            notice = "A shared item is waiting to be imported. \(error.localizedDescription)"
        }
    }

    private func reload() async throws {
        guard let repository else { return }
        let snapshot = try await repository.snapshot()
        func display(_ entry: (Pearl, URL?)) -> PearlsDisplayItem {
            let (item, original) = entry
            return PearlsDisplayItem(id: item.id, title: item.title,
                kind: PearlsItemKind(rawValue: item.kind.rawValue) ?? .file,
                text: item.text, sourceURL: item.sourceURL, attachmentURL: original,
                originalFilename: item.originalFilename, createdAt: item.createdAt,
                isFavorite: item.isFavorite, recognizedText: item.ocrText)
        }
        items = snapshot.entries.map(display)
        deletedItems = snapshot.deletedEntries.map(display)
        if let message = snapshot.recoveryMessage, message != shownRecoveryMessage {
            shownRecoveryMessage = message
            notice = message
        }
    }

    private func startIndexing() {
        guard indexingTask == nil else { return }
        indexingTask = Task { [weak self] in
            guard let self else { return }
            defer { self.indexingTask = nil }
            while !Task.isCancelled {
                guard let item = self.items.first(where: {
                    $0.recognizedText.isEmpty && !self.indexedThisSession.contains($0.id)
                    && ($0.kind == .image || $0.originalFilename?.lowercased().hasSuffix(".pdf") == true)
                    && $0.attachmentURL != nil
                }), let url = item.attachmentURL else { break }
                self.indexedThisSession.insert(item.id)
                let text = await ContentIndexer.text(at: url, isPDF: item.kind != .image)
                do {
                    try await self.repository?.recognizedText(text, for: item.id)
                    try await self.reload()
                } catch { self.notice = "The original is saved. Its searchable text could not be updated: \(error.localizedDescription)" }
            }
        }
    }
}
