import SharedModels

// Pure browse helpers shared by the app shell (RootView). The old
// KanjiListFeature reducer + view were retired with the NavigationSplitView
// refactor; only this level/search logic remains.

/// A browsable level within a classification (one JLPT level or one school grade).
public struct KanjiLevel: Equatable, Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case jlpt(String)  // "N5" … "N1"
        case grade(Int)    // 1…6 (小学), 8 (中学)
    }

    public let kind: Kind
    public init(kind: Kind) { self.kind = kind }

    public var id: String {
        switch kind {
        case let .jlpt(level): "jlpt:\(level)"
        case let .grade(grade): "grade:\(grade)"
        }
    }

    public var label: String {
        switch kind {
        case let .jlpt(level): level
        case .grade(8): "中学"
        case let .grade(grade): "小\(grade)"
        }
    }
}

/// The ordered levels for a classification.
public func levels(for classification: Classification) -> [KanjiLevel] {
    switch classification {
    case .jlpt:
        ["N5", "N4", "N3", "N2", "N1"].map { KanjiLevel(kind: .jlpt($0)) }
    case .grade:
        [1, 2, 3, 4, 5, 6, 8].map { KanjiLevel(kind: .grade($0)) }
    }
}

/// The kanji belonging to a level.
public func kanjiIn(_ all: [Kanji], in level: KanjiLevel) -> [Kanji] {
    all.filter { k in
        switch level.kind {
        case let .jlpt(l): k.jlptLevel == l
        case let .grade(g): k.grade == g
        }
    }
}

/// Free-text match: the literal, or any on/kun reading (kun dots ignored).
public func searchMatches(_ k: Kanji, _ query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return false }
    if k.literal.contains(q) { return true }
    let readings = (k.onReadings + k.kunReadings).map { $0.replacingOccurrences(of: ".", with: "") }
    return readings.contains { $0.contains(q) }
}
