import CoreText
import SharedModels
import SwiftUI

// Cute, embeddable OFL fonts bundled with the app, applied per script:
//   • Zen Maru Gothic — Latin / UI base
//   • Jua — Korean
//   • ZCOOL KuaiLe — Simplified Chinese
//   • Klee One — Japanese kanji / words / sentences (교과서체, matches the
//     KanjiVG stroke-order guide)
// The TTFs ship in this module's resource bundle and are registered once with
// Core Text at first use (framework-bundled fonts can't use Info.plist UIAppFonts).

public enum Fonts {
    private static let registerOnce: Void = {
        let files = [
            "ZenMaruGothic-Regular", "ZenMaruGothic-Bold", "Jua-Regular",
            "ZCOOLKuaiLe-Regular", "KleeOne-Regular",
        ]
        for file in files {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    /// Registers the bundled fonts exactly once. Safe to call repeatedly.
    public static func register() { _ = registerOnce }
}

private func isBold(_ weight: Font.Weight) -> Bool {
    weight == .bold || weight == .heavy || weight == .black || weight == .semibold
}

/// The neutral Latin/Japanese base face (Zen Maru Gothic).
private func baseFace(_ size: CGFloat, _ weight: Font.Weight) -> Font {
    .custom(isBold(weight) ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Regular", size: size)
}

/// The current UI language, read from the same store as `@AppStorage("appLanguage")`.
private func uiLanguage() -> AppLanguage {
    AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .ko
}

extension Font {
    /// The app's UI type — automatically the current app language's face (Korean
    /// → Jua, Chinese → ZCOOL, else the base) so all interface text, including
    /// numbers, is one consistent font per language.
    public static func kawaii(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        kawaii(size, weight: weight, language: uiLanguage())
    }

    /// Explicit-language font: Korean → Jua, Chinese → ZCOOL KuaiLe, otherwise
    /// the base face.
    public static func kawaii(_ size: CGFloat, weight: Font.Weight = .regular,
                              language: AppLanguage) -> Font {
        Fonts.register()
        switch language {
        case .ko: return .custom("Jua-Regular", size: size)
        case .zh: return .custom("ZCOOLKuaiLe-Regular", size: size)
        case .ja, .en: return baseFace(size, weight)
        }
    }

    /// The Japanese face for kanji / words / sentences — 교과서체 (Klee One),
    /// which matches the KanjiVG stroke-order guide. Single weight.
    public static func kawaiiJP(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Fonts.register()
        return .custom("KleeOne-Regular", size: size)
    }
}

extension View {
    /// Optically center a single Klee One kanji inside a square box.
    ///
    /// Klee One ships without USE_TYPO_METRICS, so SwiftUI lays a glyph out in the
    /// tall hhea line box (asc 1160 / desc −288). That line box's center sits about
    /// 0.096em *above* the ink center of a typical kanji, so a glyph centered by
    /// its line box reads noticeably low. Nudging it up by ~0.09em lands the ink
    /// in the true center of the tile / trace / guide box.
    public func opticalKanjiCenter(_ fontSize: CGFloat) -> some View {
        offset(y: -fontSize * 0.09)
    }
}
