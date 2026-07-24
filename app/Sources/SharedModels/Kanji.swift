import Foundation

/// A single kanji as shown in study screens. Pure value type — no persistence
/// or framework coupling.
public struct Kanji: Equatable, Identifiable, Sendable {
    public let id: Int
    public let literal: String
    public let strokeCount: Int
    public let grade: Int?
    public let jlptLevel: String?
    /// 漢検 (Kanji Kentei) level as a display label — "10級"…"2級", "準2級",
    /// "準1級", "1級". nil if not assigned to any level.
    public let kankenLevel: String?
    public let onReadings: [String]
    public let kunReadings: [String]
    /// KANGXI radical index (1…214), if known.
    public let radical: Int?

    public init(
        id: Int,
        literal: String,
        strokeCount: Int,
        grade: Int?,
        jlptLevel: String?,
        kankenLevel: String? = nil,
        onReadings: [String],
        kunReadings: [String],
        radical: Int? = nil
    ) {
        self.id = id
        self.literal = literal
        self.strokeCount = strokeCount
        self.grade = grade
        self.jlptLevel = jlptLevel
        self.kankenLevel = kankenLevel
        self.onReadings = onReadings
        self.kunReadings = kunReadings
        self.radical = radical
    }

    /// The KANGXI radical glyph (部首) for this kanji, if known.
    public var radicalGlyph: String? {
        radical.flatMap(kangxiRadical)
    }
}
