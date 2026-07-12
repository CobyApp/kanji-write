/// Spaced-repetition state for one quiz item (a specific question about a kanji
/// or word). Leitner-style: a `box` that grows on correct answers, with the next
/// `due` day computed from the box. Stored as primitives (SharedModels stays
/// framework-free).
public struct QuizRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: String   // "<kind>:<entityID>", e.g. "wordReading:42"
    public var box: Int
    public var due: Int     // next-review epoch-day number

    public init(id: String, box: Int, due: Int) {
        self.id = id
        self.box = box
        self.due = due
    }
}

/// Leitner scheduling for quiz items. Correct → advance a box (longer wait);
/// wrong → back to box 0 (see it again tomorrow). Mirrors the "days / a week /
/// a month later" cadence of mainstream language apps.
public enum QuizSRS {
    /// Days until the next review, indexed by box (0…5).
    public static let intervals = [1, 3, 7, 14, 30, 60]

    /// The box/due after answering, given the current box (nil = brand new).
    ///
    /// - Correct advances one box. A brand-new item answered right on the first
    ///   try jumps straight to box 1 (3 days) rather than box 0 (tomorrow), so a
    ///   confident first answer isn't treated the same as a miss.
    /// - Wrong resets to box 0 (due tomorrow), keeping shaky items in daily
    ///   rotation until they stick.
    public static func schedule(box currentBox: Int?, correct: Bool, today: Int) -> (box: Int, due: Int) {
        let box: Int
        if correct {
            // New (nil) + correct → box 1; otherwise one box further.
            box = min((currentBox ?? 0) + 1, intervals.count - 1)
        } else {
            box = 0
        }
        return (box, today + intervals[box])
    }
}
