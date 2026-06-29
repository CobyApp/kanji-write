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
        let ordered = studyOrder(input, classification: .jlpt).map(\.id)
        XCTAssertEqual(ordered, [2, 3, 1, 4])  // N5(3str), N5(8str), N1, none
    }

    func testGradeOrderThenStrokes() {
        let input = [
            k(1, strokes: 5, grade: 8, jlpt: nil),   // 中学
            k(2, strokes: 9, grade: 1, jlpt: nil),
            k(3, strokes: 2, grade: 1, jlpt: nil),
        ]
        let ordered = studyOrder(input, classification: .grade).map(\.id)
        XCTAssertEqual(ordered, [3, 2, 1])  // grade1(2str), grade1(9str), grade8
    }

    func testStableByIDWhenEqual() {
        let input = [
            k(7, strokes: 4, grade: 2, jlpt: "N4"),
            k(3, strokes: 4, grade: 2, jlpt: "N4"),
        ]
        XCTAssertEqual(studyOrder(input, classification: .jlpt).map(\.id), [3, 7])
    }
}
