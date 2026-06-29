import CoreText
import SharedModels
import SwiftUI

// Cute, embeddable OFL fonts bundled with the app and applied per language:
//   • Zen Maru Gothic (rounded gothic) — kanji glyphs, Japanese, and Latin
//   • Jua — Korean
//   • ZCOOL KuaiLe — Simplified Chinese
// The TTFs ship in this module's resource bundle and are registered once with
// Core Text at first use (framework-bundled fonts can't use Info.plist UIAppFonts).

public enum Fonts {
    private static let registerOnce: Void = {
        let files = ["ZenMaruGothic-Regular", "ZenMaruGothic-Bold", "Jua-Regular", "ZCOOLKuaiLe-Regular"]
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registers the bundled fonts exactly once. Safe to call repeatedly.
    public static func register() { _ = registerOnce }
}

extension Font {
    /// The app's friendly rounded type for kanji / Japanese / Latin text.
    public static func kawaii(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Fonts.register()
        let bold = weight == .bold || weight == .heavy || weight == .black || weight == .semibold
        return .custom(bold ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Regular", size: size)
    }

    /// Language-aware cute font: Korean → Jua, Chinese → ZCOOL KuaiLe, otherwise
    /// Zen Maru Gothic. Use for text whose script depends on the app language
    /// (meanings, glosses); Korean/Chinese faces ship Regular only.
    public static func kawaii(_ size: CGFloat, weight: Font.Weight = .regular,
                              language: AppLanguage) -> Font {
        Fonts.register()
        switch language {
        case .ko: return .custom("Jua-Regular", size: size)
        case .zh: return .custom("ZCOOLKuaiLe-Regular", size: size)
        case .ja, .en: return kawaii(size, weight: weight)
        }
    }
}
