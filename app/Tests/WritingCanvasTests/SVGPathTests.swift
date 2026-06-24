import CoreGraphics
import XCTest

@testable import WritingCanvas

final class SVGPathTests: XCTestCase {
    func testAbsoluteMoveAndLine() {
        XCTAssertEqual(
            SVGPath.parse("M21,30 L21,70"),
            [.move(CGPoint(x: 21, y: 30)), .line(CGPoint(x: 21, y: 70))])
    }

    func testRelativeCubicResolvesToAbsolute() {
        XCTAssertEqual(
            SVGPath.parse("M0,0 c1,1 2,2 3,3"),
            [.move(.zero),
             .cubic(CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3))])
    }

    func testSmoothCubicReflectsPreviousControl() {
        // After C ... control2=(2,2), end=(3,3); S reflects c1 = 2*end - control2 = (4,4)
        XCTAssertEqual(
            SVGPath.parse("M0,0 C1,1 2,2 3,3 S4,4 5,5"),
            [.move(.zero),
             .cubic(CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)),
             .cubic(CGPoint(x: 4, y: 4), CGPoint(x: 4, y: 4), CGPoint(x: 5, y: 5))])
    }

    func testCloseAndImplicitLineRepeat() {
        XCTAssertEqual(
            SVGPath.parse("M0,0 L1,0 2,0 Z"),
            [.move(.zero), .line(CGPoint(x: 1, y: 0)), .line(CGPoint(x: 2, y: 0)), .close])
    }

    func testUnsupportedCommandIsSkipped() {
        // 'A' (arc) is unsupported; its operands are skipped, the following L still parses.
        XCTAssertEqual(
            SVGPath.parse("M0,0 A1,1 0 0,1 2,2 L3,3"),
            [.move(.zero), .line(CGPoint(x: 3, y: 3))])
    }

    func testSmoothCubicWithoutPriorCubicUsesCurrentPoint() {
        // No preceding C/S, so control1 falls back to the current point (5,5).
        XCTAssertEqual(
            SVGPath.parse("M5,5 S10,10 15,15"),
            [.move(CGPoint(x: 5, y: 5)),
             .cubic(CGPoint(x: 5, y: 5), CGPoint(x: 10, y: 10), CGPoint(x: 15, y: 15))])
    }

    func testPathFromCommandsIsNonEmpty() {
        let path = SVGPath.path(from: SVGPath.parse("M21,30 L21,70"))
        XCTAssertFalse(path.isEmpty)
    }
}
