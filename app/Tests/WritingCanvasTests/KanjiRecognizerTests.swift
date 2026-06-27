import XCTest

@testable import WritingCanvas

final class KanjiRecognizerTests: XCTestCase {
    func testMatchesWhenCandidateEqualsTarget() {
        XCTAssertTrue(kanjiMatches(target: "山", candidates: ["山", "川"]))
    }

    func testNoMatchWhenAbsent() {
        XCTAssertFalse(kanjiMatches(target: "山", candidates: ["川"]))
    }

    func testMatchesAsSubstring() {
        XCTAssertTrue(kanjiMatches(target: "山", candidates: ["登山道"]))
    }

    func testNoMatchWhenEmpty() {
        XCTAssertFalse(kanjiMatches(target: "山", candidates: []))
    }
}
