import CoreText
import SharedModels
import SwiftUI

// Cute, embeddable OFL fonts bundled with the app. Latin / UI is Zen Maru
// Gothic, Korean is Jua, Chinese is ZCOOL KuaiLe — all fixed. Japanese text
// (kanji / words / sentences) uses one of five user-selectable faces (see
// `JapaneseFont`). The TTFs ship in this module's resource bundle and are
// registered once with Core Text at first use (framework-bundled fonts can't
// use Info.plist UIAppFonts).

public enum Fonts {
    private static let registerOnce: Void = {
        let files = [
            "ZenMaruGothic-Regular", "ZenMaruGothic-Bold", "Jua-Regular", "ZCOOLKuaiLe-Regular",
            "KleeOne-Regular", "Yomogi-Regular", "HachiMaruPop-Regular", "MochiyPopOne-Regular",
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
    /// which matches the KanjiVG stroke-order guide.
    public static func kawaiiJP(_ size: CGFloat, weight: Font.Weight = .regular,
                                font: JapaneseFont) -> Font {
        Fonts.register()
        return .custom(isBold(weight) ? font.boldPSName : font.regularPSName, size: size)
    }
}

// MARK: - Japanese-font environment

private struct JapaneseFontKey: EnvironmentKey {
    static let defaultValue: JapaneseFont = .default
}

extension EnvironmentValues {
    /// The Japanese face for kanji / words / sentences, set once near the root
    /// from the user setting so every component renders Japanese consistently.
    public var japaneseFont: JapaneseFont {
        get { self[JapaneseFontKey.self] }
        set { self[JapaneseFontKey.self] = newValue }
    }
}

extension View {
    /// Propagates the selected Japanese face to all descendants.
    public func japaneseFont(_ font: JapaneseFont) -> some View {
        environment(\.japaneseFont, font)
    }
}
