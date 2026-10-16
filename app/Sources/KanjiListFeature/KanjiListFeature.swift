import SharedModels

// Pure browse helpers shared by the app shell (RootView). The old
// KanjiListFeature reducer + view were retired with the NavigationSplitView
// refactor; only this level/search logic remains.

/// A browsable JLPT level (N5…N1).
public struct KanjiLevel: Equatable, Hashable, Identifiable, Sendable {
    public let level: String  // "N5" … "N1"
    public init(level: String) { self.level = level }

    public var id: String { level }
    public var label: String { level }
}

/// The ordered levels of the exam, easiest first.
public func levels(for exam: ExamType = .current) -> [KanjiLevel] {
    exam.levels.map { KanjiLevel(level: $0.rawValue) }
}

/// The kanji belonging to a level of the given exam. The level label carries its
/// own exam (`ExamLevel.exam`), so `exam` is only a fallback for an unknown label.
public func kanjiIn(_ all: [Kanji], in level: KanjiLevel, exam: ExamType = .current) -> [Kanji] {
    guard let lvl = ExamLevel(rawValue: level.level) else { return [] }
    return all.filter { $0.belongs(to: lvl) }
}

/// Free-text match: the literal, any on/kun reading (kun dots ignored), or the
/// kanji's meaning in any language when `meaning` is supplied (so a Korean/English
/// learner can search by 뜻, e.g. "산" → 山, "mountain" → 山). Meaning matching is
/// case-insensitive.
public func searchMatches(_ k: Kanji, _ query: String, meaning: String? = nil) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return false }
    if k.literal.contains(q) { return true }
    let readings = (k.onReadings + k.kunReadings).map { $0.replacingOccurrences(of: ".", with: "") }
    if readings.contains(where: { $0.contains(q) }) { return true }
    if let meaning, meaning.lowercased().contains(q.lowercased()) { return true }
    return false
}
