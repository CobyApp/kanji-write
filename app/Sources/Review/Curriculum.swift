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
/// `startIndex` skips that many kanji at the front of `order`, so a learner can
/// start the level mid-way (set from the study plan's range).
public func todaysSession(
    records: [ReviewRecord], order: [Kanji], today: Int, newPerDay: Int, startIndex: Int = 0
) -> StudySession {
    let known = Set(records.map(\.kanjiID))
    let due = records.filter { $0.due <= today }
        .sorted { ($0.due, $0.difficulty) < ($1.due, $1.difficulty) }
        .map(\.kanjiID)
    let pool = clampedTail(order, from: startIndex)
    let new = pool.lazy.filter { !known.contains($0.id) }.prefix(max(0, newPerDay)).map(\.id)
    return StudySession(dueIDs: due, newIDs: Array(new))
}

/// `order` from `start` onward, with `start` clamped to a valid range.
func clampedTail(_ order: [Kanji], from start: Int) -> [Kanji] {
    guard start > 0 else { return order }
    guard start < order.count else { return [] }
    return Array(order[start...])
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

/// Study order scoped to a single JLPT level (nil = all levels).
public func studyOrder(_ kanji: [Kanji], level: String?) -> [Kanji] {
    guard let level else { return studyOrder(kanji) }
    return studyOrder(kanji.filter { $0.jlptLevel == level })
}

/// How many kanji in `order` (from `startIndex` onward) have not been started yet.
public func remainingNew(order: [Kanji], records: [ReviewRecord], startIndex: Int = 0) -> Int {
    let known = Set(records.map(\.kanjiID))
    return clampedTail(order, from: startIndex).filter { !known.contains($0.id) }.count
}

/// Days to finish `remaining` new kanji at `perDay` per day (round up).
public func daysToFinish(remaining: Int, perDay: Int) -> Int {
    guard perDay > 0 else { return 0 }
    return (remaining + perDay - 1) / perDay
}

/// The set of epoch-days on which the learner studied at least one kanji,
/// derived from each record's last-reviewed day. (Approximate: only the most
/// recent review per kanji is stored, so it undercounts re-reviews, but it is
/// enough to drive a motivational streak.)
public func studyDays(records: [ReviewRecord]) -> Set<Int> {
    Set(records.map(\.lastReviewedDay))
}

/// Current consecutive-day study streak ending today (or yesterday if today is
/// not yet studied). Zero if neither today nor yesterday has activity.
public func currentStreak(activeDays: Set<Int>, today: Int) -> Int {
    var day = activeDays.contains(today) ? today : today - 1
    guard activeDays.contains(day) else { return 0 }
    var streak = 0
    while activeDays.contains(day) {
        streak += 1
        day -= 1
    }
    return streak
}

/// How many kanji were reviewed/learned today (records last touched today).
public func learnedToday(records: [ReviewRecord], today: Int) -> Int {
    records.filter { $0.lastReviewedDay == today }.count
}
