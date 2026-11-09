import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct PearlsSettingsView: View {
    let itemCount: Int
    @ObservedObject var syncFolder: PearlsSyncFolder
    let onSynchronize: () -> Void
    let onExport: () -> Void
    let onImport: () -> Void
    let onShowRecentlyDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(PearlsAppearance.storageKey) private var appearance: PearlsAppearance = .system
    @State private var showingSyncFolderPicker = false
    @State private var connectionError: String?

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 12) {
                        PearlsBrandMark(size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("pearls")
                                .font(PearlsTheme.brand(28))
                            Text("Version \(version) (\(buildNumber))")
                                .font(PearlsTheme.body(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                            .font(PearlsTheme.medium(18))
                        Picker("Appearance", selection: $appearance) {
                            ForEach(PearlsAppearance.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text("System follows your device’s light or dark appearance.")
                            .font(PearlsTheme.body(13))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PearlsTheme.softSurface, in: RoundedRectangle(cornerRadius: 16))

                    syncSection

                    VStack(alignment: .leading, spacing: 12) {
                        Label("On this device", systemImage: "internaldrive")
                            .font(PearlsTheme.medium(18))
                        Text("\(itemCount.formatted()) \(itemCount == 1 ? "pearl" : "pearls") in your collection")
                            .font(PearlsTheme.body(15))
                            .foregroundStyle(.secondary)
                        Text(syncFolder.isConnected
                            ? "A local copy keeps your collection available offline. Export a separate backup whenever you need one."
                            : "Your collection is stored on this device. Connect a private iCloud folder above to exchange changes, or export a backup.")
                            .font(PearlsTheme.body(16))
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PearlsTheme.softSurface, in: RoundedRectangle(cornerRadius: 16))

                    VStack(spacing: 4) {
                        actionRow("Export backup", subtitle: "Save your collection and original files.", symbol: "square.and.arrow.up", action: onExport)
                        Divider().padding(.leading, 48)
                        actionRow("Import backup", subtitle: "Bring in pearls from a saved backup.", symbol: "square.and.arrow.down", action: onImport)
                        Divider().padding(.leading, 48)
                        actionRow("Recently deleted", subtitle: "Restore pearls you’ve removed.", symbol: "trash", action: onShowRecentlyDeleted)
                    }
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(PearlsTheme.canvas)
            .navigationTitle("Settings")
            .pearlsInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(PearlsTheme.blue)
        #if os(iOS)
        .fileImporter(isPresented: $showingSyncFolderPicker, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false, onCompletion: connectSyncFolder)
        #endif
        .alert("Couldn’t connect this folder", isPresented: Binding(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK", role: .cancel) { connectionError = nil }
        } message: {
            Text(connectionError ?? "Choose your private Pearls folder in iCloud Drive.")
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 490)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Private iCloud folder", systemImage: "icloud")
                .font(PearlsTheme.medium(18))
            Text("Use the same folder on iPhone and Mac. Windows can access files through iCloud for Windows.")
                .font(PearlsTheme.body(14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if syncFolder.isConnected {
                HStack(spacing: 8) {
                    if syncFolder.isSyncing { ProgressView().controlSize(.small) }
                    Text(syncFolder.status).font(PearlsTheme.medium(14))
                }
                Text(syncFolder.cloudStatus)
                    .font(PearlsTheme.body(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = syncFolder.lastSyncAt {
                    Text("Last checked: \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(PearlsTheme.body(12))
                        .foregroundStyle(.secondary)
                }
                if let issue = syncFolder.errorMessage {
                    Label(issue, systemImage: "exclamationmark.circle")
                        .font(PearlsTheme.body(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { syncActions }
                    VStack(alignment: .leading, spacing: 8) { syncActions }
                }
                .disabled(syncFolder.isSyncing)
                Text("Sync checks while Pearls is open and active. Disconnecting keeps the local collection and iCloud files.")
                    .font(PearlsTheme.body(12))
                    .foregroundStyle(.secondary)
            } else {
                Text("In the picker, create or choose an empty folder named Pearls under iCloud Drive, or choose your existing Pearls sync folder. Choosing it connects this collection and starts sync.")
                    .font(PearlsTheme.body(13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose iCloud folder…", action: chooseSyncFolder)
                    .font(PearlsTheme.medium(14))
                    .frame(minHeight: 44)
                Text("Your saved contents are private app data. They are never included in the GitHub project or its Proton source mirror.")
                    .font(PearlsTheme.body(12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PearlsTheme.softSurface, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var syncActions: some View {
        Button("Sync now", action: onSynchronize)
            .frame(minHeight: 44)
        Button("Reconnect…", action: chooseSyncFolder)
            .frame(minHeight: 44)
        Button("Disconnect") { syncFolder.disconnect() }
            .frame(minHeight: 44)
    }

    private func chooseSyncFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.title = "Connect Pearls to iCloud Drive"
        panel.message = "Choose or create a private folder named Pearls in iCloud Drive."
        panel.prompt = "Connect"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = false
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            connectSyncFolder(.success(panel.urls))
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
        #else
        showingSyncFolderPicker = true
        #endif
    }

    private func connectSyncFolder(_ result: Result<[URL], Error>) {
        do {
            guard let folder = try result.get().first else { return }
            try syncFolder.connect(to: folder)
            onSynchronize()
        } catch {
            connectionError = error.localizedDescription
        }
    }

    private func actionRow(_ title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(PearlsTheme.medium(16))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(PearlsTheme.body(13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
