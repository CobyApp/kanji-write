import XCTest

@testable import StudyPlan

final class StudyPlanModelTests: XCTestCase {
    private func plan(completed: Set<Int> = []) -> StudyPlan {
        StudyPlan(axisLabel: "学年", durationDays: 3,
                  dayAssignments: [[1, 2], [3, 4], [5]],
                  completedKanjiIDs: completed)
    }

    func testCurrentDayIsFirstIncompleteBucket() {
        XCTAssertEqual(plan().currentDayIndex, 0)
        XCTAssertEqual(plan(completed: [1, 2]).currentDayIndex, 1)
        XCTAssertEqual(plan(completed: [1, 2, 3, 4]).currentDayIndex, 2)
    }

    func testCurrentDayIsLastWhenAllDone() {
        XCTAssertEqual(plan(completed: [1, 2, 3, 4, 5]).currentDayIndex, 2)
    }

    func testTodaysKanjiAreTheCurrentBucket() {
        XCTAssertEqual(plan(completed: [1, 2]).todaysKanjiIDs, [3, 4])
    }

    func testProgressCounts() {
        let p = plan(completed: [1, 2, 3])
        XCTAssertEqual(p.totalCount, 5)
        XCTAssertEqual(p.completedCount, 3)
        XCTAssertEqual(p.progress, 0.6, accuracy: 0.0001)
    }

    func testCompletedCountIgnoresIDsNotInPlan() {
        let p = StudyPlan(axisLabel: "学年", durationDays: 1,
                          dayAssignments: [[1, 2]], completedKanjiIDs: [1, 2, 999])
        XCTAssertEqual(p.completedCount, 2)
        XCTAssertEqual(p.progress, 1.0, accuracy: 0.0001)
    }

    func testScheduledDayIndexNilWhenNoStartDay() {
        XCTAssertNil(plan().scheduledDayIndex(today: 100))
    }

    func testScheduledDayIndexClampsToRange() {
        let p = StudyPlan(axisLabel: "学年", durationDays: 3,
                          dayAssignments: [[1, 2], [3, 4], [5]], startDay: 100)
        // today == startDay -> day 0
        XCTAssertEqual(p.scheduledDayIndex(today: 100), 0)
        // mid-range
        XCTAssertEqual(p.scheduledDayIndex(today: 101), 1)
        // beyond last -> last
        XCTAssertEqual(p.scheduledDayIndex(today: 999), 2)
        // negative (today before startDay) -> 0
        XCTAssertEqual(p.scheduledDayIndex(today: 50), 0)
    }

    func testScheduledDayIndexNilWhenNoAssignments() {
        let p = StudyPlan(axisLabel: "学年", durationDays: 0,
                          dayAssignments: [], startDay: 100)
        XCTAssertNil(p.scheduledDayIndex(today: 100))
    }
}
