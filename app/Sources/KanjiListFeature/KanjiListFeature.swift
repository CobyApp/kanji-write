import SharedModels

// Pure browse helpers shared by the app shell (RootView). The old
// KanjiListFeature reducer + view were retired with the NavigationSplitView
// refactor; only this level/search logic remains. Kanji are organized by JLPT
// level only (N5…N1).

/// A browsable JLPT level (N5…N1).
public struct KanjiLevel: Equatable, Hashable, Identifiable, Sendable {
    public let level: String  // "N5" … "N1"
    public init(level: String) { self.level = level }

    public var id: String { level }
    public var label: String { level }
}

/// The ordered JLPT levels, easiest first.
public func levels() -> [KanjiLevel] {
    ["N5", "N4", "N3", "N2", "N1"].map { KanjiLevel(level: $0) }
}

/// The kanji belonging to a level.
public func kanjiIn(_ all: [Kanji], in level: KanjiLevel) -> [Kanji] {
    all.filter { $0.jlptLevel == level.level }
}

/// Free-text match: the literal, or any on/kun reading (kun dots ignored).
public func searchMatches(_ k: Kanji, _ query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return false }
    if k.literal.contains(q) { return true }
    let readings = (k.onReadings + k.kunReadings).map { $0.replacingOccurrences(of: ".", with: "") }
    return readings.contains { $0.contains(q) }
}
