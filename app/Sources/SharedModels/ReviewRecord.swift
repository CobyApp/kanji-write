/// A kanji's spaced-repetition state (FSRS). Days are integer epoch-day numbers.
/// Stability/difficulty are the FSRS memory variables; `due` is the next review
/// day. (Stored as primitives so SharedModels stays dependency-free; the Review
/// module bridges these to its FSRS `MemoryState`.)
public struct ReviewRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { kanjiID }
    public let kanjiID: Int
    public var stability: Double
    public var difficulty: Double
    public var due: Int
    public var lastReviewedDay: Int
    public var lapses: Int
    public var reps: Int

    public init(
        kanjiID: Int, stability: Double, difficulty: Double, due: Int,
        lastReviewedDay: Int, lapses: Int = 0, reps: Int = 1
    ) {
        self.kanjiID = kanjiID
        self.stability = stability
        self.difficulty = difficulty
        self.due = due
        self.lastReviewedDay = lastReviewedDay
        self.lapses = lapses
        self.reps = reps
    }
}
