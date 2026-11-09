import SwiftUI

extension Notification.Name {
    static let pearlsImportRequested = Notification.Name("Pearls.importRequested")
}

@main
@MainActor
struct PearlsApp: App {
    @StateObject private var library = LibraryController()
    @StateObject private var syncFolder = PearlsSyncFolder()
    @AppStorage(PearlsAppearance.storageKey) private var appearance: PearlsAppearance = .system

    init() { FontRegistration.registerBundledFonts() }

    var body: some Scene {
        WindowGroup("Pearls") {
            PearlsRootView(library: library, syncFolder: syncFolder)
                .preferredColorScheme(appearance.colorScheme)
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Save a Pearl…") {
                    NotificationCenter.default.post(name: .pearlsCaptureRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!library.isReady)
                Button("Import Files…") {
                    NotificationCenter.default.post(name: .pearlsImportRequested, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(!library.isReady)
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Pearls") {
                    NotificationCenter.default.post(name: .pearlsSearchRequested, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!library.isReady)
            }
        }
        #endif
    }
}
