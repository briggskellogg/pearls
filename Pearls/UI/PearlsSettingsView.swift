import SwiftUI

struct PearlsSettingsView: View {
    let itemCount: Int
    let onExport: () -> Void
    let onImport: () -> Void
    let onShowRecentlyDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 12) {
                        PearlsBrandMark(size: 42)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("pearls")
                                .font(PearlsTheme.heading(28))
                            Text("Version \(version)")
                                .font(PearlsTheme.body(13))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 12) {
                        Label("On this device", systemImage: "internaldrive")
                            .font(PearlsTheme.medium(18))
                        Text("\(itemCount.formatted()) \(itemCount == 1 ? "pearl" : "pearls") in your collection")
                            .font(PearlsTheme.body(15))
                            .foregroundStyle(.secondary)
                        Text("Your collection is stored locally. Export a backup to keep a copy or move your pearls to another device.")
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
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 490)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
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
