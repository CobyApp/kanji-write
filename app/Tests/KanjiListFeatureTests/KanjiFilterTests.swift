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
    static let a = Kanji(id: 5, literal: "亞", strokeCount: 8, grade: nil,
                         jlptLevel: nil, kankenLevel: "準1級",
                         kankenMemberships: ["準1級", "1級"],
                         onReadings: ["ア"], kunReadings: [])
}

final class KanjiFilterTests: XCTestCase {
    let all: [Kanji] = [.yama, .gaku, .ai, .oyobu]

    func testJLPTLevelsOrderAndLabels() {
        let ls = levels()
        XCTAssertEqual(ls.map(\.label), ["N5", "N4", "N3", "N2", "N1"])
        XCTAssertEqual(ls.map(\.id), ["N5", "N4", "N3", "N2", "N1"])
    }

    func testKanjiInJLPTLevel() {
        let n5 = KanjiLevel(level: "N5")
        XCTAssertEqual(kanjiIn(all, in: n5), [.yama, .gaku])
        XCTAssertEqual(kanjiIn(all, in: KanjiLevel(level: "N3")), [.ai])
    }

    func testSharedKankenItemBelongsToBothAdvancedLevels() {
        XCTAssertTrue(Kanji.a.belongs(to: "準1級", exam: .kanken))
        XCTAssertTrue(Kanji.a.belongs(to: "1級", exam: .kanken))
        XCTAssertFalse(Kanji.a.belongs(to: "2級", exam: .kanken))
    }

    func testKankenLevelsIncludeAdvancedLevels() {
        XCTAssertEqual(Array(ExamType.kanken.levels.suffix(2)), ["準1級", "1級"])
    }

    func testKanjiInKankenLevelUsesMemberships() {
        let advanced = all + [.a]
        XCTAssertEqual(
            kanjiIn(advanced, in: KanjiLevel(level: "1級"), exam: .kanken),
            [.a]
        )
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
