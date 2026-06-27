/// A learner's active study plan and completion state. Pure value type.
public struct StudyPlan: Codable, Equatable {
    public var axisLabel: String
    public var durationDays: Int
    public var dayAssignments: [[Int]]
    public var completedKanjiIDs: Set<Int>
    /// Epoch-day the plan was created. nil for plans created before
    /// calendar-based pacing existed.
    public var startDay: Int?

    public init(
        axisLabel: String,
        durationDays: Int,
        dayAssignments: [[Int]],
        completedKanjiIDs: Set<Int> = [],
        startDay: Int? = nil
    ) {
        self.axisLabel = axisLabel
        self.durationDays = durationDays
        self.dayAssignments = dayAssignments
        self.completedKanjiIDs = completedKanjiIDs
        self.startDay = startDay
    }

    public var totalCount: Int { dayAssignments.reduce(0) { $0 + $1.count } }
    public var completedCount: Int {
        let planned = Set(dayAssignments.joined())
        return completedKanjiIDs.intersection(planned).count
    }
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

    /// Calendar day index for `today` (0-based, clamped), or nil if no startDay.
    public func scheduledDayIndex(today: Int) -> Int? {
        guard let startDay, !dayAssignments.isEmpty else { return nil }
        return min(max(today - startDay, 0), dayAssignments.count - 1)
    }
}
