import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The extension only stages captures. The main app is the sole library writer.
@MainActor
final class ShareViewController: UIViewController {
    private var shareModel: ShareModel?

    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        view.backgroundColor = .systemBackground

        let model = ShareModel(inputItems: extensionContext?.inputItems ?? [], onComplete: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }, onCancel: { [weak self] in
            let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError,
                                userInfo: [NSLocalizedDescriptionKey: "Sharing was cancelled. Any pearls already saved will remain in Pearls."])
            self?.extensionContext?.cancelRequest(withError: error)
        })
        shareModel = model
        let host = UIHostingController(rootView: ShareScreen(model: model))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        model.prepare()
    }
}

private struct ShareEntry: Identifiable {
    let id = UUID()
    let createdAt = Date()
    let provider: NSItemProvider
    let titleHint: String?
    var prepared: PreparedShare?
    var errorMessage: String?
}

private struct PreparedShare: Sendable {
    let capture: PendingCapture
    let originalURL: URL?
    let byteCount: Int

    var symbol: String {
        switch capture.kind {
        case "link": return "link"
        case "image": return "photo"
        case "file": return "doc"
        default: return "doc.text"
        }
    }

    var preview: String {
        if originalURL != nil {
            return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
        }
        return String(capture.text.prefix(240))
    }
}

@MainActor
private final class ShareModel: ObservableObject {
    @Published private(set) var entries: [ShareEntry] = []
    @Published private(set) var publishedIDs = Set<UUID>()
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var issue: String?

    private let stagingDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PearlsShare-" + UUID().uuidString, isDirectory: true)
    private let onComplete: () -> Void
    private let onCancel: () -> Void
    private var work: Task<Void, Never>?
    private var closed = false

    init(inputItems: [Any], onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        var seenProviders = Set<ObjectIdentifier>()
        for item in inputItems.compactMap({ $0 as? NSExtensionItem }) {
            let title = item.attributedTitle?.string
            let attachments = item.attachments ?? []
            if attachments.isEmpty, let text = item.attributedContentText?.string, !text.isEmpty {
                entries.append(ShareEntry(provider: NSItemProvider(object: text as NSString), titleHint: title))
            } else {
                for provider in attachments where seenProviders.insert(ObjectIdentifier(provider)).inserted {
                    entries.append(ShareEntry(provider: provider, titleHint: title))
                }
            }
        }
        if entries.count > 10 {
            entries = []
            issue = "You can save up to 10 items at once. Cancel and choose fewer items to share."
        } else if entries.isEmpty {
            issue = CaptureError.unsupportedContent.localizedDescription
        }
    }

    var canSave: Bool {
        !closed && !isLoading && !isSaving && !entries.isEmpty
            && entries.allSatisfy { $0.prepared != nil }
    }

    var canRetryLoading: Bool {
        !closed && !isLoading && !isSaving && entries.contains { $0.prepared == nil }
    }

    func prepare() {
        guard canRetryLoading else { return }
        isLoading = true
        issue = nil
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isLoading = false; work = nil }
            do {
                guard AppPaths.sharedContainer != nil else { throw CaptureError.sharedContainerUnavailable }
                try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            } catch {
                issue = Self.message(for: error, fallback: "Pearls couldn’t prepare this share. Please try again.")
                return
            }
            for index in entries.indices where entries[index].prepared == nil {
                let entry = entries[index]
                entries[index].errorMessage = nil
                do {
                    let prepared = try await ShareReader.prepare(entry, in: stagingDirectory)
                    guard !Task.isCancelled, !closed else { cleanUp(); return }
                    entries[index].prepared = prepared
                } catch {
                    guard !Task.isCancelled, !closed else { cleanUp(); return }
                    entries[index].errorMessage = Self.message(for: error,
                        fallback: "This item couldn’t be read. Try again, or share its original from Files.")
                }
            }
        }
    }

    func save() {
        guard canSave else { return }
        isSaving = true
        issue = nil
        let preparedItems = entries.compactMap(\.prepared)
        work = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { isSaving = false; work = nil }
            for item in preparedItems where !publishedIDs.contains(item.capture.id) {
                do {
                    // Read and publish one bounded original at a time, off the UI actor.
                    try await Task.detached(priority: .utility) {
                        let data = try item.originalURL.map { try ShareReader.readOriginal(at: $0) }
                        try item.capture.publish(originalData: data)
                    }.value
                    publishedIDs.insert(item.capture.id)
                } catch {
                    issue = Self.message(for: error,
                        fallback: "Pearls couldn’t save this item. Your shared content is still here; try saving again.")
                    return
                }
            }
            closed = true
            cleanUp()
            onComplete()
        }
    }

    func cancel() {
        guard !isSaving, !closed else { return }
        closed = true
        work?.cancel()
        cleanUp()
        onCancel()
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }

    private static func message(for error: Error, fallback: String) -> String {
        if error is CaptureError || error is ShareReadError { return error.localizedDescription }
        let cocoaError = error as NSError
        if cocoaError.domain == NSCocoaErrorDomain && cocoaError.code == NSFileWriteOutOfSpaceError {
            return "Your device is out of storage. Free some space, then try saving again."
        }
        return fallback
    }
}

@MainActor
private struct ShareScreen: View {
    @ObservedObject var model: ShareModel
    @State private var confirmingClose = false
    private let blue = Color(red: 0.20, green: 0.46, blue: 0.95)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(blue)
                            .accessibilityHidden(true)
                        Text("Worth keeping.")
                            .font(.system(size: 28, weight: .bold))
                    }
                    Text("Your pearls will be available in Pearls on this iPhone.")
                        .foregroundStyle(.secondary)

                    ForEach(model.entries) { entry in
                        itemRow(entry)
                    }

                    if let issue = model.issue {
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(issue)
                    }
                    if !model.publishedIDs.isEmpty {
                        Text("\(model.publishedIDs.count) of \(model.entries.count) saved. Retry to save the remaining items. Closing keeps the saved pearls.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if model.isLoading {
                        ProgressView("Preparing your pearls…")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else if model.canRetryLoading {
                        Button("Try loading again") { model.prepare() }
                            .frame(minHeight: 44)
                    }
                    Text("Up to 10 items · 25 MiB per original")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Save to Pearls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.publishedIDs.isEmpty ? "Cancel" : "Close") {
                        if model.publishedIDs.isEmpty { model.cancel() } else { confirmingClose = true }
                    }
                    .disabled(model.isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: model.save) {
                    HStack(spacing: 10) {
                        if model.isSaving { ProgressView().tint(.white) }
                        Text(saveLabel).fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
                .padding(20)
                .background(.regularMaterial)
            }
            .confirmationDialog("Leave the remaining items unsaved?", isPresented: $confirmingClose,
                                titleVisibility: .visible) {
                Button("Close share", role: .destructive) { model.cancel() }
                Button("Keep trying", role: .cancel) { }
            } message: {
                Text("The pearls already saved will stay in Pearls.")
            }
        }
        .tint(blue)
        .interactiveDismissDisabled(true)
    }

    private var saveLabel: String {
        if model.isSaving { return "Saving…" }
        if !model.publishedIDs.isEmpty { return "Retry saving" }
        return model.entries.count == 1 ? "Save pearl" : "Save pearls"
    }

    private func itemRow(_ entry: ShareEntry) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: entry.prepared?.symbol ?? "doc")
                .font(.system(size: 21))
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.prepared?.capture.title ?? entry.titleHint ?? entry.provider.suggestedName ?? "Shared item")
                    .font(.headline)
                    .lineLimit(3)
                if let prepared = entry.prepared {
                    Text(prepared.preview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if let error = entry.errorMessage {
                    Text(error).font(.callout).foregroundStyle(.secondary)
                }
                if model.publishedIDs.contains(entry.id) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

private enum ShareReadError: LocalizedError {
    case unavailable, unsupportedURL, notRegularFile, textTooLarge

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "This app couldn’t provide the original. Try again, or share it from Files."
        case .unsupportedURL:
            return "Pearls can save web links beginning with http or https."
        case .notRegularFile:
            return "Choose individual files to share. Folders and file aliases aren’t supported yet."
        case .textTooLarge:
            return "This text is too large to save as a note. Share it as a file instead."
        }
    }
}

private enum ShareReader {
    // Worst-case JSON escaping still keeps metadata below the 2 MiB inbox limit.
    private static let maximumTextBytes = 256 * 1024

    static func prepare(_ entry: ShareEntry, in directory: URL) async throws -> PreparedShare {
        let provider = entry.provider
        let fileType = provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .data) && !type.conforms(to: .url)
                && !type.conforms(to: .plainText) && type != .data && type != .text
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            do {
                return try await loadURL(entry, requiresFile: true, in: directory)
            } catch ShareReadError.unavailable {
                if let fileType { return try await loadOriginal(entry, typeIdentifier: fileType, in: directory) }
                throw ShareReadError.unavailable
            }
        }
        // A web URL takes precedence over a thumbnail offered by a webpage host.
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            return try await loadURL(entry, requiresFile: false, in: directory)
        }
        if let fileType {
            return try await loadOriginal(entry, typeIdentifier: fileType, in: directory)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            let text: String = try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadObject(ofClass: NSString.self) { object, error in
                    guard error == nil, let value = object as? String else {
                        continuation.resume(throwing: ShareReadError.unavailable)
                        return
                    }
                    continuation.resume(returning: value)
                }
            }
            return try prepareText(text, id: entry.id, date: entry.createdAt, titleHint: entry.titleHint)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            return try await loadOriginal(entry, typeIdentifier: UTType.data.identifier, in: directory)
        }
        throw CaptureError.unsupportedContent
    }

    private static func loadURL(_ entry: ShareEntry, requiresFile: Bool, in directory: URL) async throws -> PreparedShare {
        let suggestedName = entry.provider.suggestedName
        let id = entry.id, date = entry.createdAt, titleHint = entry.titleHint
        return try await withCheckedThrowingContinuation { continuation in
            _ = entry.provider.loadObject(ofClass: NSURL.self) { object, error in
                guard error == nil, let url = object as? URL else {
                    continuation.resume(throwing: ShareReadError.unavailable)
                    return
                }
                do {
                    if url.isFileURL {
                        // Consume the source while the provider callback still owns its lifetime.
                        let prepared = try stageFile(url, id: id, date: date, suggestedName: suggestedName,
                                                     typeIdentifier: nil, in: directory)
                        continuation.resume(returning: prepared)
                    } else {
                        guard !requiresFile, isWebURL(url) else { throw ShareReadError.unsupportedURL }
                        let prepared = try prepareText(url.absoluteString, id: id, date: date, titleHint: titleHint)
                        continuation.resume(returning: prepared)
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private static func loadOriginal(_ entry: ShareEntry, typeIdentifier: String, in directory: URL) async throws -> PreparedShare {
        let suggestedName = entry.provider.suggestedName
        let id = entry.id, date = entry.createdAt
        do {
            return try await withCheckedThrowingContinuation { continuation in
                _ = entry.provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                    guard error == nil, let url else {
                        continuation.resume(throwing: ShareReadError.unavailable)
                        return
                    }
                    do {
                        // Do not return the temporary URL: iOS removes it when this callback returns.
                        continuation.resume(returning: try stageFile(url, id: id, date: date,
                            suggestedName: suggestedName, typeIdentifier: typeIdentifier, in: directory))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } catch ShareReadError.unavailable {
            // Some hosts vend only bytes. Keep that same registered representation; never re-encode UIImage.
            return try await withCheckedThrowingContinuation { continuation in
                _ = entry.provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                    guard error == nil, let data else {
                        continuation.resume(throwing: ShareReadError.unavailable)
                        return
                    }
                    do {
                        continuation.resume(returning: try stageData(data, id: id, date: date,
                            filename: suggestedName, type: UTType(typeIdentifier) ?? .data, in: directory))
                    } catch { continuation.resume(throwing: error) }
                }
            }
        }
    }

    private static func prepareText(_ text: String, id: UUID, date: Date, titleHint: String?) throws -> PreparedShare {
        guard text.utf8.count <= maximumTextBytes else { throw ShareReadError.textTooLarge }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CaptureError.invalidCapture }
        let url = !trimmed.contains(where: \.isWhitespace) ? URL(string: trimmed) : nil
        let sourceURL = url.flatMap { isWebURL($0) ? $0 : nil }
        let fallback = sourceURL?.host ?? String(trimmed.prefix(100))
        let capture = PendingCapture(id: id, kind: sourceURL == nil ? "note" : "link",
            title: shortTitle(titleHint, fallback: fallback), text: text, sourceURL: sourceURL,
            originalFilename: nil, contentType: sourceURL == nil ? UTType.plainText.identifier : UTType.url.identifier,
            createdAt: date)
        return PreparedShare(capture: capture, originalURL: nil, byteCount: 0)
    }

    private static func stageFile(_ url: URL, id: UUID, date: Date, suggestedName: String?,
                                  typeIdentifier: String?, in directory: URL) throws -> PreparedShare {
        guard url.isFileURL else { throw CaptureError.invalidCapture }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ShareReadError.notRegularFile }
        let declaredType = typeIdentifier.flatMap { UTType($0) }
        let specificType = declaredType.flatMap { $0 == .data || $0 == .image ? nil : $0 }
        let type = specificType ?? values.contentType ?? UTType(filenameExtension: url.pathExtension) ?? declaredType ?? .data
        let filename = suggestedName?.isEmpty == false ? suggestedName : url.lastPathComponent
        return try stageData(readOriginal(at: url), id: id, date: date, filename: filename, type: type, in: directory)
    }

    private static func stageData(_ data: Data, id: UUID, date: Date, filename: String?,
                                  type: UTType, in directory: URL) throws -> PreparedShare {
        guard data.count <= PendingCapture.maximumOriginalBytes else { throw CaptureError.originalTooLarge }
        let filenameType = filename.flatMap { UTType(filenameExtension: ($0 as NSString).pathExtension) }
        let contentType = type == .data ? filenameType ?? type : type
        let name = safeFilename(filename, type: contentType)
        let stagedURL = directory.appendingPathComponent(id.uuidString)
        try data.write(to: stagedURL, options: .atomic)
        let capture = PendingCapture(id: id, kind: contentType.conforms(to: .image) ? "image" : "file",
            title: shortTitle(name, fallback: "Shared file"), text: "", sourceURL: nil,
            originalFilename: name, contentType: contentType.identifier, createdAt: date)
        return PreparedShare(capture: capture, originalURL: stagedURL, byteCount: data.count)
    }

    static func readOriginal(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw ShareReadError.notRegularFile }
        let limit = PendingCapture.maximumOriginalBytes
        if let size = values.fileSize, size > limit { throw CaptureError.originalTooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var result = Data()
        while let chunk = try file.read(upToCount: min(64 * 1024, limit - result.count + 1)), !chunk.isEmpty {
            guard chunk.count <= limit - result.count else { throw CaptureError.originalTooLarge }
            result.append(chunk)
        }
        return result
    }

    private static func safeFilename(_ suggested: String?, type: UTType) -> String {
        var name = (suggested ?? "Shared file").components(separatedBy: CharacterSet(charactersIn: "/\\")).last ?? "Shared file"
        name = String(String.UnicodeScalarView(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.utf8.count > 180 { name.removeLast() }
        if name.isEmpty || name == "." || name == ".." { name = "Shared file" }
        if name.lowercased() == "capture.json" { name = "original-capture.json" }
        if (name as NSString).pathExtension.isEmpty, let ext = type.preferredFilenameExtension {
            name += "." + ext
        }
        return PendingCapture.isSafeFilename(name) ? name : "Shared file"
    }

    private static func shortTitle(_ candidate: String?, fallback: String) -> String {
        let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var result = ""
        for scalar in (value.isEmpty ? fallback : value).unicodeScalars {
            guard result.utf8.count + String(scalar).utf8.count <= 512 else { break }
            result.unicodeScalars.append(scalar)
        }
        return String(result.prefix(120))
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
