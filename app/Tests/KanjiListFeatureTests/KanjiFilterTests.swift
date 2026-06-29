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

    func testJLPTLevelsOrderAndLabels() {
        let ls = levels(for: .jlpt)
        XCTAssertEqual(ls.map(\.label), ["N5", "N4", "N3", "N2", "N1"])
        XCTAssertEqual(ls.map(\.id), ["jlpt:N5", "jlpt:N4", "jlpt:N3", "jlpt:N2", "jlpt:N1"])
    }

    func testGradeLevelsOrderAndLabels() {
        let ls = levels(for: .grade)
        // 小1…小6 then 中学 (grade 8)
        XCTAssertEqual(ls.map(\.label), ["小1", "小2", "小3", "小4", "小5", "小6", "中学"])
        XCTAssertEqual(ls.last?.id, "grade:8")
    }

    func testKanjiInJLPTLevel() {
        let n5 = KanjiLevel(kind: .jlpt("N5"))
        XCTAssertEqual(kanjiIn(all, in: n5), [.yama, .gaku])
        XCTAssertEqual(kanjiIn(all, in: KanjiLevel(kind: .jlpt("N3"))), [.ai])
    }

    func testKanjiInGradeLevel() {
        XCTAssertEqual(kanjiIn(all, in: KanjiLevel(kind: .grade(1))), [.yama, .gaku])
        // grade 8 is the 中学 bucket
        XCTAssertEqual(kanjiIn(all, in: KanjiLevel(kind: .grade(8))), [.oyobu])
    }

    func testSearchByLiteral() {
        XCTAssertTrue(searchMatches(.yama, "山"))
        XCTAssertFalse(searchMatches(.gaku, "山"))
    }

    func testSearchByReadingIgnoresDots() {
        XCTAssertTrue(searchMatches(.yama, "やま"))    // kun
        XCTAssertTrue(searchMatches(.oyobu, "およぶ"))  // kun with dot removed
        XCTAssertTrue(searchMatches(.ai, "アイ"))       // on
    }

    func testSearchTrimsAndRejectsEmpty() {
        XCTAssertTrue(searchMatches(.yama, "  山 "))
        XCTAssertFalse(searchMatches(.yama, "   "))
        XCTAssertFalse(searchMatches(.yama, "zzz"))
    }
}
