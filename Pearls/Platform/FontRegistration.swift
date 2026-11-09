import Foundation
import CoreText

enum FontRegistration {
    static func registerBundledFonts() {
        let fonts = [
            ("PPNeueMontreal-Regular", "ttf"),
            ("PPNeueMontreal-Bold", "ttf"),
            ("PPNeueYork-NormalLight", "otf"),
            ("PPNeueYork-NormalMedium", "otf"),
            ("PPNeueYork-NormalExtrabold", "otf")
        ]
        for (name, extensionName) in fonts {
            guard let url = Bundle.main.url(forResource: name, withExtension: extensionName) else { continue }
            // An already registered iOS font is harmless; macOS needs explicit registration.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
