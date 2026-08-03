import Foundation

/// An old form (旧字) of a kanji the app already ships.
///
/// The 漢検 list prints these entries only as a picture: they are the pre-reform
/// shape of a character, and the shape it names has no codepoint of its own, so
/// there is no text to show. What we have instead is a verified outline — one
/// filled path on a square box — matched against the dictionary's own bitmap.
public struct KanjiVariant: Equatable, Identifiable, Sendable {
    public let id: Int
    /// 旧字 / 旧字でない異体字 — what kind of variant this is, in the list's own words.
    public let variantKind: String
    /// The glyph outline, as an SVG path `d` string.
    public let pathD: String
    /// The square the outline is drawn on (GlyphWiki uses 200).
    public let viewBox: Double
    /// Where the glyph came from, for the attribution the licence asks for.
    public let sourceURL: String
    public let licenseURL: String

    public init(id: Int, variantKind: String, pathD: String, viewBox: Double,
                sourceURL: String, licenseURL: String) {
        self.id = id
        self.variantKind = variantKind
        self.pathD = pathD
        self.viewBox = viewBox
        self.sourceURL = sourceURL
        self.licenseURL = licenseURL
    }
}
