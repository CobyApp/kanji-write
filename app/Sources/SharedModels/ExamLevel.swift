import Foundation

/// One exam level as a typed value instead of a raw string. JLPT N5→N1 and 漢検
/// 10級→1級 (準2級 / 準1級 included) are distinct sets that share this type.
///
/// The `rawValue` is byte-identical to the label stored everywhere — the bundled
/// read-only `kanji.sqlite` (`jlpt_level`, `kanken_level`, `kanken_membership`),
/// `@AppStorage("targetLevel")`, `SectionStat` keys and the widget payload — so a
/// level round-trips through `.rawValue` / `ExamLevel(rawValue:)` with no change
/// to any persisted data.
public enum ExamLevel: String, CaseIterable, Sendable, Codable, Hashable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"
    case k10 = "10級", k9 = "9級", k8 = "8級", k7 = "7級", k6 = "6級",
         k5 = "5級", k4 = "4級", k3 = "3級", kPre2 = "準2級", k2 = "2級",
         kPre1 = "準1級", k1 = "1級"

    /// The label as printed and stored (same as `rawValue`).
    public var label: String { rawValue }

    public static let jlptLevels: [ExamLevel] = [.n5, .n4, .n3, .n2, .n1]
    public static let kankenLevels: [ExamLevel] = [
        .k10, .k9, .k8, .k7, .k6, .k5, .k4, .k3, .kPre2, .k2, .kPre1, .k1,
    ]

    /// The exam this level belongs to — replaces the old `"N"`-prefix sniff.
    public var exam: ExamType {
        switch self {
        case .n5, .n4, .n3, .n2, .n1: .jlpt
        default: .kanken
        }
    }

    /// Levels of one exam, easiest to hardest.
    public static func levels(for exam: ExamType) -> [ExamLevel] {
        exam == .jlpt ? jlptLevels : kankenLevels
    }

    /// 漢検 級 in ascending difficulty (10級 = 1 … 1級 = 12); nil for a JLPT level.
    /// Cumulative tables (四字熟語, 対義語・類義語) draw everything at or below it.
    public var kankenRank: Int? {
        Self.kankenLevels.firstIndex(of: self).map { $0 + 1 }
    }
}
