import SwiftUI
#if os(macOS)
import AppKit
#endif

extension Notification.Name {
    static let pearlsCaptureRequested = Notification.Name("Pearls.captureRequested")
    static let pearlsSearchRequested = Notification.Name("Pearls.searchRequested")
}

struct PearlsLibraryView: View {
    var items: [PearlsDisplayItem]
    @ObservedObject var syncFolder: PearlsSyncFolder
    let onSynchronize: () -> Void
    let onCreate: (PearlsDraft) async throws -> Void
    let onUpdateNote: (UUID, String, String, String, String) async throws -> Void
    let onSetFavorite: (UUID, Bool) async throws -> Void
    let onDelete: (UUID) async throws -> Void
    let onImportFiles: () -> Void
    let onExportArchive: () -> Void
    let onImportArchive: () -> Void
    let onShowRecentlyDeleted: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var destination: Destination = .all
    @State private var query = ""
    @State private var path: [UUID] = []
    @State private var showingCapture = false
    @State private var showingSettings = false
    @State private var editingNote: PearlsDisplayItem?
    @State private var syncFolderConnectionError: String?
    #if os(macOS)
    @State private var syncFolderPanel: NSOpenPanel?
    #endif
    @State private var pendingAction: PendingAction?
    @State private var errorMessage: String?
    @FocusState private var searchIsFocused: Bool

    private enum Destination: String, CaseIterable {
        case all, favorites
        var title: String { self == .all ? "All pearls" : "Favorites" }
        var symbol: String { self == .all ? "square.stack.3d.up.fill" : "star.fill" }
        var color: Color { self == .all ? PearlsTheme.blue : PearlsTheme.gold }
    }

    private enum PendingAction { case importFiles, importArchive, exportArchive, recentlyDeleted, connectSyncFolder }

    private var displayedItems: [PearlsDisplayItem] {
        items.filter { (destination == .all || $0.isFavorite) && $0.matches(query) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var gridColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 220, maximum: 360), spacing: 18, alignment: .top)]
        #else
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 155, maximum: 420), spacing: 14, alignment: .top)]
        #endif
    }

    var body: some View {
        Group {
            #if os(macOS)
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 200, ideal: 232, max: 280)
            } detail: {
                mainNavigation
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 760, minHeight: 560)
            #else
            mainNavigation
            #endif
        }
        .tint(PearlsTheme.blue)
        .sheet(isPresented: $showingCapture, onDismiss: performPendingAction) {
            PearlsCaptureView(onSave: onCreate, onImportFiles: {
                pendingAction = .importFiles
                showingCapture = false
            })
        }
        .sheet(isPresented: $showingSettings, onDismiss: performPendingAction) {
            PearlsSettingsView(itemCount: items.count, syncFolder: syncFolder,
                onSynchronize: onSynchronize,
                onChooseSyncFolder: {
                    pendingAction = .connectSyncFolder
                    showingSettings = false
                }, onConnectSyncFolder: connectSyncFolder,
                connectionError: $syncFolderConnectionError, onExport: {
                pendingAction = .exportArchive
                showingSettings = false
            }, onImport: {
                pendingAction = .importArchive
                showingSettings = false
            }, onShowRecentlyDeleted: {
                pendingAction = .recentlyDeleted
                showingSettings = false
            })
        }
        .sheet(item: $editingNote) { note in
            // The captured note and this presentation outlive its detail route.
            // A remote edit/deletion must not dismiss or replace an open draft.
            PearlsNoteEditorView(item: note) { title, text, originalTitle, originalText in
                try await onUpdateNote(note.id, title, text, originalTitle, originalText)
            }
        }
        .alert("Couldn’t update your pearl", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .pearlsCaptureRequested)) { _ in
            showingCapture = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .pearlsSearchRequested)) { _ in
            path.removeAll()
            searchIsFocused = true
        }
    }

    private var mainNavigation: some View {
        NavigationStack(path: $path) {
            collection
                .navigationDestination(for: UUID.self) { id in
                    if let item = items.first(where: { $0.id == id }) {
                        PearlsDetailView(
                            item: item,
                            onEdit: { editingNote = $0 },
                            onSetFavorite: onSetFavorite,
                            onDelete: onDelete,
                            onDeleted: { path.removeAll() }
                        )
                    } else {
                        ContentUnavailableView("Pearl unavailable", systemImage: "doc", description: Text("This item is no longer in your collection."))
                    }
                }
        }
    }

    private var collection: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            phoneDestinations
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 14)
            #endif
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    searchField
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(destination.title)
                                .font(PearlsTheme.heading(34))
                                .foregroundStyle(.primary)
                                .accessibilityAddTraits(.isHeader)
                            Text(collectionSubtitle)
                                .font(PearlsTheme.body(15))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Image(systemName: destination.symbol)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(destination.color)
                            .accessibilityHidden(true)
                    }
                    if displayedItems.isEmpty {
                        emptyState
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                    } else {
                        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 18) {
                            ForEach(displayedItems) { item in
                                PearlsItemCard(item: item, onOpen: { path.append(item.id) }, onFavorite: {
                                    Task {
                                        do { try await onSetFavorite(item.id, !item.isFavorite) }
                                        catch { errorMessage = error.localizedDescription }
                                    }
                                })
                            }
                        }
                    }
                }
                .padding(.horizontal, collectionPadding)
                .padding(.top, 22)
                .padding(.bottom, 30)
                .frame(maxWidth: 1240, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .background(PearlsTheme.canvas)
        #if os(macOS)
        .navigationTitle("Pearls")
        #else
        .navigationTitle("")
        #endif
        .pearlsInlineNavigationTitle()
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .primaryAction) {
                Button { showingCapture = true } label: {
                    Label("Save a pearl", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Save a note or link")
            }
            #else
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) {
                    PearlsBrandSignature()
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) {
                    PearlsBrandSignature()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Settings and backups")
            }
            #endif
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            #if os(iOS)
            HStack(spacing: 14) {
                Button { showingCapture = true } label: {
                    Label("Save a pearl", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PearlsPrimaryButtonStyle())
                PearlsMakerMark()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.regularMaterial)
            #endif
        }
    }

    private var collectionPadding: CGFloat {
        #if os(macOS)
        36
        #else
        20
        #endif
    }

    private var collectionSubtitle: String {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(displayedItems.count) \(displayedItems.count == 1 ? "match" : "matches") in your collection"
        }
        if destination == .favorites { return "The things you return to." }
        return items.isEmpty ? "A little room for what matters." : "\(items.count) \(items.count == 1 ? "thing" : "things") worth keeping."
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find something you saved", text: $query)
                .font(PearlsTheme.body(16))
                .textFieldStyle(.plain)
                .focused($searchIsFocused)
                .accessibilityLabel("Search your collection")
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
                #endif
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
            #if os(macOS)
            Text("⌘ F")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            #endif
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: !query.isEmpty ? "magnifyingglass" : destination.symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(!query.isEmpty ? Color.secondary : destination.color)
                .accessibilityHidden(true)
            Text(!query.isEmpty ? "Nothing found" : destination == .favorites ? "Keep your favorites close" : "Start with one small thing")
                .font(PearlsTheme.medium(22))
                .multilineTextAlignment(.center)
            Text(!query.isEmpty ? "Try a word from a title, note, link, or image." : destination == .favorites ? "Tap the star on any pearl to find it here." : "A thought, a link, an image. Save it here, then come back when you need it.")
                .font(PearlsTheme.body(16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            if !query.isEmpty {
                Button("Clear search") { query = "" }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
    }

    #if os(macOS)
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            PearlsBrandSignature()
                .padding(.horizontal, 20)
                .padding(.top, 16)
            VStack(spacing: 6) {
                ForEach(Destination.allCases, id: \.self) { entry in
                    destinationButton(entry)
                }
            }
            .padding(.horizontal, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                Button { showingSettings = true } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                        .font(PearlsTheme.body(15))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(alignment: .bottom, spacing: 12) {
                    Text(syncFolder.isConnected ? "Private iCloud folder" : "On this device")
                        .font(PearlsTheme.body(11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    PearlsMakerMark()
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .background(PearlsTheme.sidebar)
    }
    #endif

    private var phoneDestinations: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            ForEach(Destination.allCases, id: \.self) { entry in
                destinationButton(entry)
            }
        }
    }

    private func destinationButton(_ entry: Destination) -> some View {
        let selected = destination == entry
        let count = entry == .all ? items.count : items.filter(\.isFavorite).count
        return Button {
            destination = entry
            path.removeAll()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(entry.color)
                    .frame(width: 23)
                Text(entry.title)
                    .font(selected ? PearlsTheme.medium(15) : PearlsTheme.body(15))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 3)
                Text(count.formatted())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(selected ? Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.055) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(entry.color).frame(width: 3, height: 18)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.title), \(count) \(count == 1 ? "pearl" : "pearls")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func performPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .importFiles: onImportFiles()
        case .importArchive: onImportArchive()
        case .exportArchive: onExportArchive()
        case .recentlyDeleted: onShowRecentlyDeleted()
        case .connectSyncFolder:
            #if os(macOS)
            // Let SwiftUI finish ending its sheet before presenting AppKit's.
            DispatchQueue.main.async { presentMacSyncFolderPanel() }
            #else
            showingSettings = true
            #endif
        }
    }

    private func connectSyncFolder(_ result: Result<[URL], Error>) {
        do {
            guard let folder = try result.get().first else { return }
            try syncFolder.connect(to: folder)
            onSynchronize()
        } catch {
            syncFolderConnectionError = error.localizedDescription
        }
    }

    #if os(macOS)
    private func presentMacSyncFolderPanel() {
        guard syncFolderPanel == nil else { return }
        let panel = NSOpenPanel()
        panel.title = "Connect Pearls to iCloud Drive"
        panel.message = "Choose or create a private folder named Pearls in iCloud Drive."
        panel.prompt = "Connect"
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        syncFolderPanel = panel
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            let selected = response == .OK ? panel.urls : []
            panel.orderOut(nil)
            syncFolderPanel = nil
            DispatchQueue.main.async {
                if !selected.isEmpty { connectSyncFolder(.success(selected)) }
                showingSettings = true
            }
        }
        // Settings is no longer present. Never anchor the panel to a sheet or
        // queue it behind an existing sheet: that leaves two modal lifetimes.
        if let window = NSApp.mainWindow, window.sheetParent == nil, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
    #endif
}
