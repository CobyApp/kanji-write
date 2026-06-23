import Foundation

/// A single kanji as shown in study screens. Pure value type — no persistence
/// or framework coupling.
public struct Kanji: Equatable, Identifiable, Sendable {
    public let id: Int
    public let literal: String
    public let strokeCount: Int
    public let grade: Int?
    public let jlptLevel: String?
    public let onReadings: [String]
    public let kunReadings: [String]

    public init(
        id: Int,
        literal: String,
        strokeCount: Int,
        grade: Int?,
        jlptLevel: String?,
        onReadings: [String],
        kunReadings: [String]
    ) {
        self.id = id
        self.literal = literal
        self.strokeCount = strokeCount
        self.grade = grade
        self.jlptLevel = jlptLevel
        self.onReadings = onReadings
        self.kunReadings = kunReadings
    }
}
