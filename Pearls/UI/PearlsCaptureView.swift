import SwiftUI

struct PearlsCaptureView: View {
    let onSave: (PearlsDraft) async throws -> Void
    let onImportFiles: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var title = ""
    @State private var text = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingDiscardConfirmation = false
    @State private var importAfterDiscard = false
    @FocusState private var textIsFocused: Bool

    private var draft: PearlsDraft { PearlsDraft(title: title, text: text) }
    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var hasUnsavedChanges: Bool {
        canSave || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 12) {
                        PearlsBrandMark(size: 32)
                        Text("Something worth keeping.")
                            .font(PearlsTheme.medium(21))
                    }
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 9) {
                        Text("Title")
                            .font(PearlsTheme.medium(13))
                            .foregroundStyle(.secondary)
                        TextField("Optional title", text: $title)
                            .font(PearlsTheme.medium(18))
                            .textFieldStyle(.plain)
                            .padding(14)
                            .frame(minHeight: 48)
                            .background(PearlsTheme.softSurface, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Title, optional")
                    }

                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Text("Thought or link")
                                .font(PearlsTheme.medium(13))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if draft.sourceURL != nil {
                                Label("Link", systemImage: "link")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ZStack(alignment: .topLeading) {
                            if text.isEmpty {
                                Text("Write something, or paste a link…")
                                    .font(PearlsTheme.body(17))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 17)
                                    .padding(.top, 19)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $text)
                                .font(PearlsTheme.body(17))
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .frame(minHeight: 220)
                                .focused($textIsFocused)
                                .accessibilityLabel("Thought or link")
                        }
                        .background(PearlsTheme.softSurface, in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle")
                            .font(PearlsTheme.body(14))
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        requestClose(importFile: true)
                    } label: {
                        Label("Import an image or file", systemImage: "square.and.arrow.down")
                            .font(PearlsTheme.body(15))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.10), lineWidth: 1)
                    }
                }
                .padding(24)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .background(PearlsTheme.canvas)
            .navigationTitle("Save a pearl")
            .pearlsInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { requestClose(importFile: false) }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canSave || isSaving)
                    .accessibilityLabel(isSaving ? "Saving pearl" : "Save pearl")
                }
            }
            .disabled(isSaving)
        }
        .tint(PearlsTheme.blue)
        .interactiveDismissDisabled(isSaving || hasUnsavedChanges)
        .confirmationDialog("Discard your unsaved text?", isPresented: $showingDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard text", role: .destructive) {
                if importAfterDiscard { onImportFiles() } else { dismiss() }
            }
            Button("Keep editing", role: .cancel) { }
        }
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 540, minHeight: 520, idealHeight: 570)
        #else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        .task { textIsFocused = true }
    }

    private func requestClose(importFile: Bool) {
        guard !isSaving else { return }
        if hasUnsavedChanges {
            importAfterDiscard = importFile
            showingDiscardConfirmation = true
        } else if importFile {
            onImportFiles()
        } else {
            dismiss()
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        let value = draft
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onSave(value)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
