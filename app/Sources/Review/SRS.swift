/// Leitner-style spaced repetition. Days are integer epoch-day numbers.
private let ladder = [1, 2, 4, 7, 15, 30]

public func srsIntervalDays(box: Int) -> Int {
    ladder[min(max(box, 0), ladder.count - 1)]
}

public func srsAdvance(box: Int, correct: Bool) -> Int {
    correct ? min(box + 1, ladder.count - 1) : 0
}

public func srsIsDue(box: Int, lastReviewedDay: Int, today: Int) -> Bool {
    today - lastReviewedDay >= srsIntervalDays(box: box)
}
