/// A kanji's spaced-repetition state.
public struct ReviewRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { kanjiID }
    public let kanjiID: Int
    public let box: Int
    public let lastReviewedDay: Int

    public init(kanjiID: Int, box: Int, lastReviewedDay: Int) {
        self.kanjiID = kanjiID
        self.box = box
        self.lastReviewedDay = lastReviewedDay
    }
}
