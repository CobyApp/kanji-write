import SharedModels
import XCTest

@testable import KanjiListFeature

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
    static let gaku = Kanji(id: 2, literal: "学", strokeCount: 8, grade: 1,
                            jlptLevel: "N5", onReadings: ["ガク"], kunReadings: ["まな.ぶ"])
    static let ai = Kanji(id: 3, literal: "愛", strokeCount: 13, grade: 4,
                          jlptLevel: "N3", onReadings: ["アイ"], kunReadings: [])
    static let oyobu = Kanji(id: 4, literal: "及", strokeCount: 3, grade: 8,
                             jlptLevel: "N1", onReadings: ["キュウ"], kunReadings: ["およ.ぶ"])
}

final class KanjiFilterTests: XCTestCase {
    let all: [Kanji] = [.yama, .gaku, .ai, .oyobu]

    func testAllReturnsEverything() {
        XCTAssertEqual(kanjiMatching(all, filter: .all, search: ""), all)
    }

    func testFilterByJLPT() {
        XCTAssertEqual(kanjiMatching(all, filter: .jlpt("N5"), search: ""), [.yama, .gaku])
        XCTAssertEqual(kanjiMatching(all, filter: .jlpt("N3"), search: ""), [.ai])
    }

    func testFilterByGrade() {
        XCTAssertEqual(kanjiMatching(all, filter: .grade(1), search: ""), [.yama, .gaku])
        // grade 8 is the 中学 bucket
        XCTAssertEqual(kanjiMatching(all, filter: .grade(8), search: ""), [.oyobu])
    }

    func testSearchByLiteral() {
        XCTAssertEqual(kanjiMatching(all, filter: .all, search: "山"), [.yama])
    }

    func testSearchByReading() {
        // kun reading (dots in kun readings are ignored for matching)
        XCTAssertEqual(kanjiMatching(all, filter: .all, search: "やま"), [.yama])
        XCTAssertEqual(kanjiMatching(all, filter: .all, search: "およぶ"), [.oyobu])
        // on reading
        XCTAssertEqual(kanjiMatching(all, filter: .all, search: "アイ"), [.ai])
    }

    func testSearchTrimsWhitespace() {
        XCTAssertEqual(kanjiMatching(all, filter: .all, search: "  山 "), [.yama])
    }

    func testFilterAndSearchCombine() {
        XCTAssertEqual(kanjiMatching(all, filter: .jlpt("N5"), search: "学"), [.gaku])
        // filter excludes it even if search would match
        XCTAssertEqual(kanjiMatching(all, filter: .grade(1), search: "愛"), [])
    }

    func testEmptyWhenNoMatch() {
        XCTAssertEqual(kanjiMatching(all, filter: .all, search: "zzz"), [])
    }
}
