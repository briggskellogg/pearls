import Foundation
import CoreText

enum FontRegistration {
    static func registerBundledFonts() {
        for name in ["PPNeueYork-NormalLight", "PPNeueYork-NormalMedium", "PPNeueYork-NormalExtrabold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "otf") else { continue }
            // An already registered iOS font is harmless; macOS needs explicit registration.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
