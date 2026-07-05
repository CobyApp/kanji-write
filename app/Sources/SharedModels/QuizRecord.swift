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
    public static func schedule(box currentBox: Int?, correct: Bool, today: Int) -> (box: Int, due: Int) {
        let box = correct ? min((currentBox ?? -1) + 1, intervals.count - 1) : 0
        return (box, today + intervals[box])
    }
}
