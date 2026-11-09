import SwiftUI

struct PearlsItemCard: View {
    let item: PearlsDisplayItem
    let onOpen: () -> Void
    let onFavorite: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    preview
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayTitle)
                            .font(PearlsTheme.medium(17))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let source = item.sourceLabel {
                            Text(source)
                                .font(PearlsTheme.body(13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 15)
                    .padding(.bottom, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.displayTitle), \(item.kind.label)")
            .accessibilityHint("Open pearl")
            HStack(spacing: 7) {
                Image(systemName: item.kind.symbol)
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                Text(item.kind.label)
                    .font(PearlsTheme.body(12))
                Spacer(minLength: 4)
                Button(action: onFavorite) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.isFavorite ? PearlsTheme.gold : Color.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isFavorite ? "Remove \(item.displayTitle) from favorites" : "Favorite \(item.displayTitle)")
                .accessibilityValue(item.isFavorite ? "Favorited" : "Not favorited")
            }
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
            .padding(.trailing, 6)
            .padding(.bottom, 3)
        }
        .background(PearlsTheme.canvas)
        .clipShape(RoundedRectangle(cornerRadius: PearlsTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: PearlsTheme.corner)
                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.13 : 0.075), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contextMenu {
            Button("Open pearl", systemImage: "arrow.up.right.square", action: onOpen)
            Button(item.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: item.isFavorite ? "star.slash" : "star", action: onFavorite)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch item.kind {
        case .image:
            if let url = item.attachmentURL {
                PearlsThumbnailView(url: url)
                    .frame(height: 164)
            } else {
                symbolPreview("photo")
            }
        case .note:
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                Text(item.text.isEmpty ? "An unfinished thought." : item.text)
                    .font(PearlsTheme.reading(16))
                    .foregroundStyle(.primary.opacity(0.85))
                    .multilineTextAlignment(.leading)
                    .lineLimit(6)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
            .background(PearlsTheme.gold.opacity(colorScheme == .dark ? 0.055 : 0.045))
        case .link:
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "link")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                Text(item.sourceLabel ?? "A saved link")
                    .font(PearlsTheme.medium(19))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(linkPath)
                    .font(PearlsTheme.body(13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 164, alignment: .leading)
            .background(PearlsTheme.blue.opacity(colorScheme == .dark ? 0.075 : 0.045))
        case .file:
            symbolPreview("doc")
        }
    }

    private func symbolPreview(_ symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
            if let filename = item.originalFilename {
                Text(filename)
                    .font(PearlsTheme.body(13))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.secondary)
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 164)
        .background(Color.primary.opacity(0.035))
    }

    private var linkPath: String {
        guard let path = item.sourceURL?.path, !path.isEmpty, path != "/" else { return "Open when you’re ready." }
        return path
    }
}
