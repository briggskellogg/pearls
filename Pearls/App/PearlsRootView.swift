import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct PearlsRootView: View {
    @ObservedObject var library: LibraryController
    @ObservedObject var syncFolder: PearlsSyncFolder
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingImporter = false
    @State private var importingArchive = false
    @State private var showingExporter = false
    @State private var showingRecentlyDeleted = false
    @State private var archiveDocument: PearlsArchiveDocument?

    var body: some View {
        content
            .overlay(alignment: .topTrailing) {
                if library.isBusy {
                    ProgressView().padding(18).accessibilityLabel("Saving your collection")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if library.lastDeletedID != nil {
                    HStack(spacing: 16) {
                        Text("Pearl moved to Recently Deleted")
                            .font(PearlsTheme.body(13))
                        Spacer(minLength: 8)
                        Button("Undo") { Task { await library.undoDelete() } }
                            .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 20)
                    .background(.regularMaterial)
                }
            }
            .task {
                if !library.isReady { await library.open() }
                await synchronize()
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    await synchronize()
                    do { try await Task.sleep(for: .seconds(25)) }
                    catch { return }
                }
            }
            .onChange(of: library.contentRevision) { _, _ in
                Task { await synchronize() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await library.receiveSharedItems() } }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pearlsImportRequested)) { _ in
                presentImporter(archive: false)
            }
            .onOpenURL { url in
                Task {
                    if !library.isReady { await library.open() }
                    guard library.isReady else { return }
                    await receive(url)
                }
            }
            .fileImporter(isPresented: $showingImporter,
                allowedContentTypes: importingArchive ? [.pearlsArchive, .json, .data] : [.item],
                allowsMultipleSelection: !importingArchive) { result in
                switch result {
                case .success(let urls):
                    let archive = importingArchive
                    Task {
                        if archive, let url = urls.first { await library.importArchive(url) }
                        else { await library.importFiles(urls) }
                    }
                case .failure(let error): library.notice = error.localizedDescription
                }
            }
            .fileExporter(isPresented: $showingExporter, document: archiveDocument,
                contentType: .pearlsArchive, defaultFilename: "Pearls-Collection") { result in
                if case .failure(let error) = result { library.notice = error.localizedDescription }
                archiveDocument = nil
            }
            .sheet(isPresented: $showingRecentlyDeleted) {
                PearlsRecentlyDeletedView(library: library)
            }
            .alert("Your collection", isPresented: Binding(
                get: { library.notice != nil },
                set: { if !$0 { library.notice = nil } }
            )) {
                Button("OK", role: .cancel) { library.notice = nil }
            } message: {
                Text(library.notice ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if library.isReady {
            PearlsLibraryView(items: library.items, syncFolder: syncFolder,
                onSynchronize: { Task { await synchronize() } },
                onCreate: { try await library.create($0) },
                onUpdateNote: { try await library.updateNote(id: $0, title: $1, text: $2, originalTitle: $3, originalText: $4) },
                onSetFavorite: { try await library.setFavorite(id: $0, value: $1) },
                onDelete: { try await library.delete(id: $0) },
                onImportFiles: { presentImporter(archive: false) },
                onExportArchive: exportCollection,
                onImportArchive: { presentImporter(archive: true) },
                onShowRecentlyDeleted: { showingRecentlyDeleted = true })
                #if os(macOS)
                .dropDestination(for: URL.self) { urls, _ in
                    guard !urls.isEmpty else { return false }
                    Task { for url in urls { await receive(url) } }
                    return true
                }
                #endif
        } else if library.opening {
            VStack(spacing: 20) {
                PearlsBrandMark(size: 56)
                ProgressView("Opening your collection…")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PearlsTheme.canvas)
        } else {
            ContentUnavailableView {
                Label("Your collection needs attention", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(library.loadError ?? "Pearls couldn’t open the collection on this device.")
            } actions: {
                Button("Try Again") { Task { await library.open() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .background(PearlsTheme.canvas)
        }
    }

    private func presentImporter(archive: Bool) {
        guard library.isReady else { return }
        importingArchive = archive
        showingImporter = true
    }

    private func synchronize() async {
        guard library.isReady, scenePhase == .active, !Task.isCancelled else { return }
        await syncFolder.synchronize { folder in
            try await library.synchronize(with: folder)
        }
    }

    private func exportCollection() {
        Task {
            do {
                archiveDocument = PearlsArchiveDocument(data: try await library.archiveData())
                showingExporter = true
            } catch { library.notice = error.localizedDescription }
        }
    }

    private func receive(_ url: URL) async {
        if url.isFileURL {
            if ["pearlsarchive", "pearls"].contains(url.pathExtension.lowercased()) {
                await library.importArchive(url)
            } else { await library.importFiles([url]) }
        } else if ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
            do { try await library.create(PearlsDraft(title: "", text: url.absoluteString)) }
            catch { library.notice = error.localizedDescription }
        }
    }
}

@MainActor
private struct PearlsRecentlyDeletedView: View {
    @ObservedObject var library: LibraryController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if library.deletedItems.isEmpty {
                    ContentUnavailableView("Nothing here", systemImage: "trash",
                        description: Text("Pearls you remove can be restored here."))
                } else {
                    List(library.deletedItems) { item in
                        HStack(spacing: 14) {
                            Image(systemName: item.kind.symbol).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.displayTitle).font(PearlsTheme.medium(16))
                                Text(item.kind.label).font(PearlsTheme.body(13)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Button("Restore") { Task { await library.restore(id: item.id) } }
                                .frame(minHeight: 44)
                                .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("Recently Deleted")
            .pearlsInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 440)
        #endif
    }
}
