import XCTest

@testable import WritingCanvas

final class StrokeCountTests: XCTestCase {
    func testStatusShowsCheckWhenCountsMatch() {
        XCTAssertEqual(strokeCountStatus(expected: 3, drawn: 3), "✓ 3/3")
    }

    func testStatusOmitsCheckWhenCountsDiffer() {
        XCTAssertEqual(strokeCountStatus(expected: 3, drawn: 1), "1/3")
    }
}
