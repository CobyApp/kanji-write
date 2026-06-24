import XCTest

@testable import StudyPlan

final class PlanSchedulerTests: XCTestCase {
    func testEvenSplitWithRemainderGoesToEarlierBuckets() {
        XCTAssertEqual(
            PlanScheduler.distribute(kanjiIDs: [1, 2, 3, 4, 5, 6, 7, 8], days: 3),
            [[1, 2, 3], [4, 5, 6], [7, 8]])
    }

    func testDaysGreaterThanCountIsClampedToCount() {
        XCTAssertEqual(
            PlanScheduler.distribute(kanjiIDs: [1, 2], days: 5),
            [[1], [2]])
    }

    func testSingleDayHoldsEverything() {
        XCTAssertEqual(
            PlanScheduler.distribute(kanjiIDs: [1, 2, 3], days: 1),
            [[1, 2, 3]])
    }

    func testEmptyInputYieldsNoBuckets() {
        XCTAssertEqual(PlanScheduler.distribute(kanjiIDs: [], days: 3), [])
    }

    func testZeroDaysClampsToSingleBucket() {
        XCTAssertEqual(
            PlanScheduler.distribute(kanjiIDs: [1, 2, 3], days: 0),
            [[1, 2, 3]])
    }
}
