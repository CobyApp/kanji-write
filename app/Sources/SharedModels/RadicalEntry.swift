import Foundation

/// One of the 214 Kangxi radicals (部首) for the radical reference: its glyph,
/// stroke count, Japanese 部首名 and a short meaning in every language, plus how
/// many kanji in the current scope carry it.
public struct RadicalEntry: Equatable, Identifiable, Sendable {
    public var id: Int { number }
    public let number: Int          // Kangxi radical number 1…214
    public let glyph: String
    public let strokes: Int
    public let nameJa: String       // 部首名 in hiragana (くさかんむり)
    public let meaningJa: String
    public let meaningKo: String
    public let meaningZh: String
    public let meaningEn: String
    public let kanjiCount: Int

    public init(number: Int, glyph: String, strokes: Int, nameJa: String,
                meaningJa: String, meaningKo: String, meaningZh: String,
                meaningEn: String, kanjiCount: Int) {
        self.number = number
        self.glyph = glyph
        self.strokes = strokes
        self.nameJa = nameJa
        self.meaningJa = meaningJa
        self.meaningKo = meaningKo
        self.meaningZh = meaningZh
        self.meaningEn = meaningEn
        self.kanjiCount = kanjiCount
    }

    /// The meaning in the app language, falling back to Japanese.
    public func meaning(_ language: AppLanguage) -> String {
        switch language {
        case .ko: meaningKo.isEmpty ? meaningJa : meaningKo
        case .ja: meaningJa
        case .zh: meaningZh.isEmpty ? meaningJa : meaningZh
        case .en: meaningEn.isEmpty ? meaningJa : meaningEn
        }
    }
}
