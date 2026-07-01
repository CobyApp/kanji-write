import SharedModels

/// A day's study queue: due reviews plus a capped set of new kanji.
public struct StudySession: Equatable, Sendable {
    public var dueIDs: [Int]
    public var newIDs: [Int]
    public init(dueIDs: [Int], newIDs: [Int]) {
        self.dueIDs = dueIDs
        self.newIDs = newIDs
    }
}

/// Build today's session: every tracked card whose `due` has arrived (ordered by
/// due then difficulty), plus the next `newPerDay` never-seen kanji from
/// `order`.
public func todaysSession(
    records: [ReviewRecord], order: [Kanji], today: Int, newPerDay: Int
) -> StudySession {
    let known = Set(records.map(\.kanjiID))
    let due = records.filter { $0.due <= today }
        .sorted { ($0.due, $0.difficulty) < ($1.due, $1.difficulty) }
        .map(\.kanjiID)
    let new = order.lazy.filter { !known.contains($0.id) }.prefix(max(0, newPerDay)).map(\.id)
    return StudySession(dueIDs: due, newIDs: Array(new))
}

/// The order in which new kanji are introduced: by JLPT level (N5→N1; un-leveled
/// last), then by ascending stroke count (simpler first), then id for stability.
public func studyOrder(_ kanji: [Kanji]) -> [Kanji] {
    kanji.sorted { a, b in
        let ra = orderRank(a)
        let rb = orderRank(b)
        if ra.level != rb.level { return ra.level < rb.level }
        if ra.strokes != rb.strokes { return ra.strokes < rb.strokes }
        return ra.id < rb.id
    }
}

private func orderRank(_ k: Kanji) -> (level: Int, strokes: Int, id: Int) {
    // N5 first … N1 last; unmapped sorts after.
    let level = ["N5": 0, "N4": 1, "N3": 2, "N2": 3, "N1": 4][k.jlptLevel ?? ""] ?? 99
    return (level, k.strokeCount, k.id)
}
