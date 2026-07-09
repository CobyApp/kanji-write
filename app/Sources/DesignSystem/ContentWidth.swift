import SwiftUI

extension View {
    /// Forces Japanese glyph variants for CJK Han characters. Kanji are
    /// Han-unified, so the same code point can render as a Korean/Chinese form
    /// unless the run's language is Japanese — this makes displayed kanji match
    /// the Japanese (KanjiVG) stroke-order forms. Apply to any view showing
    /// Japanese kanji / words.
    public func japaneseGlyphs() -> some View {
        typesettingLanguage(Locale.Language(identifier: "ja"))
    }
}

extension View {
    /// Caps content to a comfortable reading width (compact 560 / regular 900),
    /// centered — so screens don't stretch edge-to-edge on iPad / Mac. Apply to
    /// the scrolling content, never to the full-bleed background.
    public func readableWidth(_ sizeClass: UserInterfaceSizeClass?) -> some View {
        frame(maxWidth: sizeClass == .compact ? 560 : 900)
            .frame(maxWidth: .infinity)
    }
}
