import XCTest

@testable import Practice

final class PracticeGridTests: XCTestCase {
    func testColumnCountClampsToTwoToFour() {
        XCTAssertEqual(PracticeGrid.columnCount(forWidth: 0), 2)          // no width → min
        XCTAssertEqual(PracticeGrid.columnCount(forWidth: 100), 2)       // too narrow → min
        XCTAssertEqual(PracticeGrid.columnCount(forWidth: 320), 2)       // 320/150 = 2
        XCTAssertEqual(PracticeGrid.columnCount(forWidth: 480), 3)       // 480/150 = 3
        XCTAssertEqual(PracticeGrid.columnCount(forWidth: 1200), 4)      // capped at 4
    }

    func testColumnCountRespectsTarget() {
        XCTAssertEqual(PracticeGrid.columnCount(forWidth: 600, target: 200), 3)
        XCTAssertEqual(PracticeGrid.columnCount(forWidth: 600, target: 100), 4) // 6 → capped
    }

    func testRowCountRoundsUp() {
        XCTAssertEqual(PracticeGrid.rowCount(count: 9, columns: 3), 3)
        XCTAssertEqual(PracticeGrid.rowCount(count: 9, columns: 4), 3)   // ceil(9/4)
        XCTAssertEqual(PracticeGrid.rowCount(count: 9, columns: 2), 5)   // ceil(9/2)
    }

    func testRowCountHandlesZeroColumnsSafely() {
        // Guards against divide-by-zero: treated as a single column.
        XCTAssertEqual(PracticeGrid.rowCount(count: 9, columns: 0), 9)
    }

    func testCellCountIsPositive() {
        XCTAssertGreaterThan(PracticeGrid.cellCount, 0)
    }
}
