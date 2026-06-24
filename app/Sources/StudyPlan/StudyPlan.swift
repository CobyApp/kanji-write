/// A learner's active study plan and completion state. Pure value type.
public struct StudyPlan: Codable, Equatable {
    public var axisLabel: String
    public var durationDays: Int
    public var dayAssignments: [[Int]]
    public var completedKanjiIDs: Set<Int>

    public init(
        axisLabel: String,
        durationDays: Int,
        dayAssignments: [[Int]],
        completedKanjiIDs: Set<Int> = []
    ) {
        self.axisLabel = axisLabel
        self.durationDays = durationDays
        self.dayAssignments = dayAssignments
        self.completedKanjiIDs = completedKanjiIDs
    }

    public var totalCount: Int { dayAssignments.reduce(0) { $0 + $1.count } }
    public var completedCount: Int { completedKanjiIDs.count }
    public var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    /// The first day whose kanji are not all completed; the last day if every
    /// kanji is done. Pace-based — no calendar dependency.
    public var currentDayIndex: Int {
        for (index, day) in dayAssignments.enumerated()
        where day.contains(where: { !completedKanjiIDs.contains($0) }) {
            return index
        }
        return max(0, dayAssignments.count - 1)
    }

    public var todaysKanjiIDs: [Int] {
        guard !dayAssignments.isEmpty else { return [] }
        return dayAssignments[currentDayIndex]
    }
}
