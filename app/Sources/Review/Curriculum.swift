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
/// due then difficulty), plus today's remaining new-kanji quota from `order`.
///
/// `newPerDay` is a *daily quota*, not a per-session batch: the new count is
/// `newPerDay − (kanji already learned today)`, so studying twice in one day
/// doesn't hand out two full batches, and the count winds down to zero as today's
/// goal is met. Pass `ignoreTodaysProgress: true` to deliberately study ahead
/// (pull tomorrow's batch forward) — then a full `newPerDay` is served regardless.
///
/// `startIndex` skips that many kanji at the front of `order`, so a learner can
/// start the level mid-way (set from the study plan's range).
public func todaysSession(
    records: [ReviewRecord], order: [Kanji], today: Int, newPerDay: Int,
    startIndex: Int = 0, ignoreTodaysProgress: Bool = false
) -> StudySession {
    let known = Set(records.map(\.kanjiID))
    let due = records.filter { $0.due <= today }
        .sorted { ($0.due, $0.difficulty) < ($1.due, $1.difficulty) }
        .map(\.kanjiID)
    let learnedToday = ignoreTodaysProgress ? 0 : records.filter { $0.lastReviewedDay == today }.count
    let quota = max(0, newPerDay - learnedToday)
    let pool = clampedTail(order, from: startIndex)
    let new = pool.lazy.filter { !known.contains($0.id) }.prefix(quota).map(\.id)
    return StudySession(dueIDs: due, newIDs: Array(new))
}

/// `order` from `start` onward, with `start` clamped to a valid range.
func clampedTail(_ order: [Kanji], from start: Int) -> [Kanji] {
    guard start > 0 else { return order }
    guard start < order.count else { return [] }
    return Array(order[start...])
}

/// The order in which new kanji are introduced: by the exam's level (easiest
/// first; un-leveled last), then ascending stroke count, then id for stability.
public func studyOrder(_ kanji: [Kanji], exam: ExamType) -> [Kanji] {
    let rank = Dictionary(uniqueKeysWithValues: exam.levels.enumerated().map { ($1, $0) })
    return kanji.sorted { a, b in
        let la = rank[a.level(for: exam) ?? ""] ?? 99
        let lb = rank[b.level(for: exam) ?? ""] ?? 99
        if la != lb { return la < lb }
        if a.strokeCount != b.strokeCount { return a.strokeCount < b.strokeCount }
        return a.id < b.id
    }
}

/// Study order scoped to a single level of the exam (nil = all levels).
public func studyOrder(_ kanji: [Kanji], exam: ExamType, level: String?) -> [Kanji] {
    guard let level else { return studyOrder(kanji, exam: exam) }
    return studyOrder(kanji.filter { $0.belongs(to: level, exam: exam) }, exam: exam)
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
