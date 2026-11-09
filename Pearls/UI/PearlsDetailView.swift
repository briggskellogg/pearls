import SwiftUI

struct PearlsDetailView: View {
    let item: PearlsDisplayItem
    let onEdit: (PearlsDisplayItem) -> Void
    let onSetFavorite: (UUID, Bool) async throws -> Void
    let onDelete: (UUID) async throws -> Void
    let onDeleted: () -> Void

    @State private var confirmingDelete = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 8) {
                    Image(systemName: item.kind.symbol)
                        .accessibilityHidden(true)
                    Text(item.kind.label)
                    Text("·")
                    Text(item.createdAt.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                }
                .font(PearlsTheme.body(13))
                .foregroundStyle(.secondary)

                Text(item.displayTitle)
                    .font(PearlsTheme.heading(36))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                content

                Text("On this device")
                    .font(PearlsTheme.body(12))
                    .foregroundStyle(.secondary)
                    .padding(.top, 20)
            }
            .padding(24)
            .padding(.top, 18)
            .frame(maxWidth: 800, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(PearlsTheme.canvas)
        .navigationTitle("Pearl")
        .pearlsInlineNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    toggleFavorite()
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(item.isFavorite ? PearlsTheme.gold : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")
                .disabled(isWorking)

                shareButton

                Menu {
                    if item.kind == .note {
                        Button {
                            onEdit(item)
                        } label: {
                            Label("Edit note", systemImage: "pencil")
                        }
                    }
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete pearl", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("More actions")
                .disabled(isWorking)
            }
        }
        .confirmationDialog("Delete this pearl?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete pearl", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(item.displayTitle)
        }
        .alert("Couldn’t update your pearl", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .note:
            VStack(alignment: .leading, spacing: 24) {
                Text(item.text)
                    .font(PearlsTheme.reading(19))
                    .lineSpacing(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Button {
                    onEdit(item)
                } label: {
                    Label("Edit note", systemImage: "pencil")
                        .font(PearlsTheme.body(14))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }
        case .link:
            VStack(alignment: .leading, spacing: 22) {
                if let url = item.sourceURL {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(item.sourceLabel ?? "Saved link", systemImage: "link")
                            .font(PearlsTheme.medium(18))
                        Text(url.absoluteString)
                            .font(PearlsTheme.body(15))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(PearlsTheme.softSurface, in: RoundedRectangle(cornerRadius: 16))
                    Link(destination: url) {
                        Label("Open original", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(PearlsPrimaryButtonStyle())
                }
                if !item.text.isEmpty, item.text != item.sourceURL?.absoluteString {
                    Text(item.text)
                        .font(PearlsTheme.reading(18))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                }
            }
        case .image:
            if let url = item.attachmentURL {
                PearlsFullImageView(url: url)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(item.displayTitle)
            } else {
                unavailableAttachment
            }
        case .file:
            if let url = item.attachmentURL {
                VStack(alignment: .leading, spacing: 18) {
                    if url.pathExtension.lowercased() == "pdf" {
                        PearlsPDFPreview(url: url)
                            .frame(minHeight: 520)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("PDF preview")
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "doc")
                                .font(.system(size: 52, weight: .light))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text(item.originalFilename ?? item.displayTitle)
                                .font(PearlsTheme.medium(18))
                                .multilineTextAlignment(.center)
                            Text("Use Share to open this file in another app or save a copy.")
                                .font(PearlsTheme.body(15))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(28)
                        .frame(maxWidth: .infinity, minHeight: 250)
                        .background(PearlsTheme.softSurface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    ShareLink(item: url) {
                        Label("Share file", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            } else {
                unavailableAttachment
            }
        }
    }

    private var unavailableAttachment: some View {
        ContentUnavailableView("File unavailable", systemImage: "doc", description: Text("The saved attachment could not be found on this device."))
    }

    @ViewBuilder
    private var shareButton: some View {
        if let url = item.attachmentURL {
            ShareLink(item: url) { shareLabel }
                .buttonStyle(.plain)
                .accessibilityLabel("Share pearl")
        } else if let url = item.sourceURL {
            ShareLink(item: url) { shareLabel }
                .buttonStyle(.plain)
                .accessibilityLabel("Share link")
        } else {
            ShareLink(item: item.displayTitle + "\n\n" + item.text) { shareLabel }
                .buttonStyle(.plain)
                .accessibilityLabel("Share note")
        }
    }

    private var shareLabel: some View {
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
    }

    private func toggleFavorite() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await onSetFavorite(item.id, !item.isFavorite)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            do {
                try await onDelete(item.id)
                onDeleted()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PearlsNoteEditorView: View {
    let item: PearlsDisplayItem
    let onSave: (String, String, String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var text: String
    @State private var originalTitle: String
    @State private var originalText: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var confirmingDiscard = false

    init(item: PearlsDisplayItem, onSave: @escaping (String, String, String, String) async throws -> Void) {
        self.item = item
        self.onSave = onSave
        _title = State(initialValue: item.title)
        _text = State(initialValue: item.text)
        _originalTitle = State(initialValue: item.title)
        _originalText = State(initialValue: item.text)
    }

    private var hasChanges: Bool { title != originalTitle || text != originalText }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Title", text: $title)
                    .font(PearlsTheme.heading(29))
                    .textFieldStyle(.plain)
                    .padding(.top, 12)
                    .accessibilityLabel("Note title")
                TextEditor(text: $text)
                    .font(PearlsTheme.reading(18))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 260)
                    .accessibilityLabel("Note text")
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(PearlsTheme.body(14))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
            .background(PearlsTheme.canvas)
            .navigationTitle("Edit note")
            .pearlsInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !hasChanges)
                }
            }
            .disabled(isSaving)
        }
        .tint(PearlsTheme.blue)
        .interactiveDismissDisabled(isSaving || hasChanges)
        .confirmationDialog("Discard your edits?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard edits", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) { }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 500, idealHeight: 600)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let editedTitle = title
        let editedText = text
        let baseTitle = originalTitle
        let baseText = originalText
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onSave(editedTitle, editedText, baseTitle, baseText)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
