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

extension Font {
    /// The app's base rounded type — Latin, numbers, UI chrome. Fixed (Zen Maru
    /// Gothic); not affected by the Japanese-font setting.
    public static func kawaii(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Fonts.register()
        return .custom(isBold(weight) ? "ZenMaruGothic-Bold" : "ZenMaruGothic-Regular", size: size)
    }

    /// Language-aware font: Korean → Jua, Chinese → ZCOOL KuaiLe, otherwise the
    /// base face. Use for text whose script depends on the app language.
    public static func kawaii(_ size: CGFloat, weight: Font.Weight = .regular,
                              language: AppLanguage) -> Font {
        Fonts.register()
        switch language {
        case .ko: return .custom("Jua-Regular", size: size)
        case .zh: return .custom("ZCOOLKuaiLe-Regular", size: size)
        case .ja, .en: return kawaii(size, weight: weight)
        }
    }

    /// The user-selected Japanese face — for kanji / Japanese words / sentences.
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
