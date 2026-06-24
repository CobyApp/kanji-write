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
}
