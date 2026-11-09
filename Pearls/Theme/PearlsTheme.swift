import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PearlsAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    static let storageKey = "pearls.appearance"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum PearlsTheme {
    static let blue = Color(red: 0.20, green: 0.46, blue: 0.95)
    static let gold = Color(red: 0.78, green: 0.57, blue: 0.12)
    static let sky = Color(red: 0.19, green: 0.65, blue: 0.97)
    static let corner: CGFloat = 18

    static var canvas: Color {
        #if os(macOS)
        Color(nsColor: .textBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    static var sidebar: Color {
        #if os(macOS)
        Color(nsColor: .underPageBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }

    static var softSurface: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }

    static func accentText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.48, green: 0.68, blue: 1)
            : Color(red: 0.15, green: 0.37, blue: 0.81)
    }

    static func body(_ size: CGFloat = 16) -> Font {
        custom("PPNeueMontreal-Regular", size: size, weight: .regular, relativeTo: .body)
    }

    static func medium(_ size: CGFloat = 16) -> Font {
        custom("PPNeueMontreal-Bold", size: size, weight: .semibold, relativeTo: .body)
    }

    static func brand(_ size: CGFloat) -> Font {
        custom("PPNeueMontreal-Bold", size: size, weight: .bold, relativeTo: .title2)
    }

    static func reading(_ size: CGFloat = 19) -> Font {
        custom("PPNeueYork-NormalLight", size: size, weight: .regular, relativeTo: .body)
    }

    static func heading(_ size: CGFloat = 32) -> Font {
        custom("PPNeueYork-NormalExtrabold", size: size, weight: .bold, relativeTo: .largeTitle)
    }

    private static func custom(_ name: String, size: CGFloat, weight: Font.Weight, relativeTo: Font.TextStyle) -> Font {
        #if os(macOS)
        let available = NSFont(name: name, size: size) != nil
        #else
        let available = UIFont(name: name, size: size) != nil
        #endif
        return available ? .custom(name, size: size, relativeTo: relativeTo) : .system(size: size, weight: weight)
    }
}

/// A small code-native version of the supplied orbit mark for navigation chrome.
struct PearlsBrandMark: View {
    var size: CGFloat = 29

    var body: some View {
        ZStack {
            Ellipse()
                .stroke(PearlsTheme.sky, style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round))
                .frame(width: size * 0.88, height: size * 0.64)
                .rotationEffect(.degrees(-24))
            Path { path in
                path.move(to: CGPoint(x: size * 0.60, y: size * 0.64))
                path.addQuadCurve(
                    to: CGPoint(x: size * 0.74, y: size * 0.48),
                    control: CGPoint(x: size * 0.74, y: size * 0.60)
                )
            }
            .stroke(PearlsTheme.sky, style: StrokeStyle(lineWidth: size * 0.10, lineCap: .round))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct PearlsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PearlsTheme.medium(16))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(PearlsTheme.blue.opacity(configuration.isPressed ? 0.84 : 1), in: RoundedRectangle(cornerRadius: 12))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    @ViewBuilder
    func pearlsInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
