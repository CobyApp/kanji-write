import SharedModels
import XCTest

@testable import Review

private func k(_ id: Int, strokes: Int, grade: Int?, jlpt: String?) -> Kanji {
    Kanji(id: id, literal: "x", strokeCount: strokes, grade: grade, jlptLevel: jlpt,
          onReadings: [], kunReadings: [])
}

final class CurriculumTests: XCTestCase {
    func testJLPTOrderThenStrokesThenID() {
        let input = [
            k(1, strokes: 10, grade: 1, jlpt: "N1"),
            k(2, strokes: 3, grade: 1, jlpt: "N5"),
            k(3, strokes: 8, grade: 1, jlpt: "N5"),
            k(4, strokes: 1, grade: nil, jlpt: nil),  // unmapped → last
        ]
        let ordered = studyOrder(input).map(\.id)
        XCTAssertEqual(ordered, [2, 3, 1, 4])  // N5(3str), N5(8str), N1, none
    }

    func testStableByIDWhenEqual() {
        let input = [
            k(7, strokes: 4, grade: 2, jlpt: "N4"),
            k(3, strokes: 4, grade: 2, jlpt: "N4"),
        ]
        XCTAssertEqual(studyOrder(input).map(\.id), [3, 7])
    }

    func testSessionDueAndNew() {
        let order = [k(1, strokes: 1, grade: 1, jlpt: "N5"),
                     k(2, strokes: 2, grade: 1, jlpt: "N5"),
                     k(3, strokes: 3, grade: 1, jlpt: "N5")]
        let records = [
            ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: 100, lastReviewedDay: 95),
            ReviewRecord(kanjiID: 2, stability: 5, difficulty: 5, due: 110, lastReviewedDay: 100),
        ]
        let s = todaysSession(records: records, order: order, today: 100, newPerDay: 5)
        XCTAssertEqual(s.dueIDs, [1])        // id 1 due (100<=100); id 2 not due (110>100)
        XCTAssertEqual(s.newIDs, [3])        // id 3 has no record
    }

    func testSessionCapsNewPerDay() {
        let order = (1...10).map { k($0, strokes: $0, grade: 1, jlpt: "N5") }
        let s = todaysSession(records: [], order: order, today: 0, newPerDay: 3)
        XCTAssertEqual(s.newIDs, [1, 2, 3])
        XCTAssertTrue(s.dueIDs.isEmpty)
    }

    func testSessionDueOrderedByDueThenDifficulty() {
        let records = [
            ReviewRecord(kanjiID: 1, stability: 5, difficulty: 8, due: 100, lastReviewedDay: 90),
            ReviewRecord(kanjiID: 2, stability: 5, difficulty: 2, due: 100, lastReviewedDay: 90),
            ReviewRecord(kanjiID: 3, stability: 5, difficulty: 5, due: 99, lastReviewedDay: 90),
        ]
        let s = todaysSession(records: records, order: [], today: 100, newPerDay: 0)
        XCTAssertEqual(s.dueIDs, [3, 2, 1])  // due 99 first; then due 100 by difficulty 2,8
    }
}
