import Foundation

/// Which exam the app is oriented around. JLPT (levels N5→N1) or 漢検 Kanji
/// Kentei (10級→1級). Chosen in settings; drives level lists, ordering and
/// filtering across study / dictionary / quiz.
public enum ExamType: String, CaseIterable, Sendable {
    case jlpt
    case kanken

    /// Levels from easiest to hardest.
    public var levels: [String] {
        switch self {
        case .jlpt: ["N5", "N4", "N3", "N2", "N1"]
        case .kanken:
            ["10級", "9級", "8級", "7級", "6級", "5級", "4級", "3級",
             "準2級", "2級", "準1級", "1級"]
        }
    }

    public var defaultLevel: String { levels.first ?? "" }

    /// The currently selected exam, read from the shared `examType` default.
    /// Lets non-View code (reducers, helpers) resolve it without a Binding.
    public static var current: ExamType {
        UserDefaults.standard.string(forKey: "examType").flatMap(ExamType.init(rawValue:)) ?? .jlpt
    }
}

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
    /// Every Kanken paper scope that includes this kanji.
    public let kankenMemberships: [String]
    /// Whether verified stroke-order paths are available for writing features.
    public let hasVerifiedStrokeOrder: Bool
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
        kankenMemberships: [String]? = nil,
        hasVerifiedStrokeOrder: Bool = false,
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
        self.kankenMemberships = kankenMemberships ?? kankenLevel.map { [$0] } ?? []
        self.hasVerifiedStrokeOrder = hasVerifiedStrokeOrder
        self.onReadings = onReadings
        self.kunReadings = kunReadings
        self.radical = radical
    }

    /// The KANGXI radical glyph (部首) for this kanji, if known.
    public var radicalGlyph: String? {
        radical.flatMap(kangxiRadical)
    }

    /// This kanji's level for the given exam (jlptLevel or kankenLevel).
    public func level(for exam: ExamType) -> String? {
        switch exam {
        case .jlpt: jlptLevel
        case .kanken: kankenLevel
        }
    }

    /// Whether this kanji is included in the requested exam level.
    public func belongs(to level: String, exam: ExamType) -> Bool {
        switch exam {
        case .jlpt: jlptLevel == level
        case .kanken: kankenMemberships.contains(level)
        }
    }
}
