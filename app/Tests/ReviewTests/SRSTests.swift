import SharedModels
import XCTest

@testable import Review

final class SRSTests: XCTestCase {
    func testIntervalLadderAndClamp() {
        XCTAssertEqual(srsIntervalDays(box: 0), 1)
        XCTAssertEqual(srsIntervalDays(box: 3), 7)
        XCTAssertEqual(srsIntervalDays(box: 5), 30)
        XCTAssertEqual(srsIntervalDays(box: 99), 30)   // clamped
        XCTAssertEqual(srsIntervalDays(box: -1), 1)     // clamped
    }

    func testAdvance() {
        XCTAssertEqual(srsAdvance(box: 0, correct: true), 1)
        XCTAssertEqual(srsAdvance(box: 5, correct: true), 5)   // capped
        XCTAssertEqual(srsAdvance(box: 3, correct: false), 0)  // reset
    }

    func testIsDue() {
        // box 1 → interval 2: due when today-last >= 2
        XCTAssertFalse(srsIsDue(box: 1, lastReviewedDay: 100, today: 101))
        XCTAssertTrue(srsIsDue(box: 1, lastReviewedDay: 100, today: 102))
        XCTAssertTrue(srsIsDue(box: 1, lastReviewedDay: 100, today: 200))
    }

    func testReviewRecordIsIdentifiableByKanjiID() {
        let r = ReviewRecord(kanjiID: 7, box: 2, lastReviewedDay: 10)
        XCTAssertEqual(r.id, 7)
    }
}
