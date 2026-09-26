import SharedModels
import XCTest

@testable import AppFeature

final class StatsFeatureTests: XCTestCase {
    private func record(_ id: Int, day: Int, reps: Int = 1) -> ReviewRecord {
        ReviewRecord(kanjiID: id, stability: 1, difficulty: 5, due: day + 1,
                     lastReviewedDay: day, reps: reps)
    }

    func testRecentDaysCountNewKanjiAndAnswers() {
        var state = StatsFeature.State(exam: .kanken, level: "10級", kanji: [],
                                       records: [record(1, day: 100), record(2, day: 100),
                                                 record(3, day: 99, reps: 3)],
                                       today: 100)
        state.log = [100: DayLog(answered: 12, correct: 9)]
        let days = state.recentDays
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.last?.day, 100)
        XCTAssertEqual(days.last?.learned, 2)        // a re-reviewed card isn't "new"
        XCTAssertEqual(days.last?.answered, 12)
        XCTAssertEqual(days.first?.day, 87)
    }

    func testEstimateNeedsFiveAnswersPerSection() {
        var state = StatsFeature.State(exam: .kanken, level: "5級", kanji: [], records: [], today: 0)
        let sections = ExamType.kanken.sections(for: "5級")
        state.stats = [SectionStat.key(level: "5級", section: sections[0].id): SectionStat(attempts: 3, correct: 3)]
        XCTAssertNil(state.estimatedScore)
        state.stats[SectionStat.key(level: "5級", section: sections[1].id)] = SectionStat(attempts: 10, correct: 6)
        XCTAssertEqual(state.estimatedScore, 0.6)
        // Weakest tried section first, untried last.
        XCTAssertEqual(state.sectionScores.first?.section.id, sections[1].id)
        XCTAssertNil(state.sectionScores.last?.stat)
    }
}
