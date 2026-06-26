import XCTest

@testable import WritingCanvas

final class StrokeAnimationTests: XCTestCase {
    func testStrokeFractionClampsPerStroke() {
        // overall progress 1.5: stroke 0 done, stroke 1 half, stroke 2 not started
        XCTAssertEqual(strokeFraction(progress: 1.5, index: 0), 1.0, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 1.5, index: 1), 0.5, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 1.5, index: 2), 0.0, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 0, index: 0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(strokeFraction(progress: 3, index: 0), 1.0, accuracy: 1e-9)
    }
}
