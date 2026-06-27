import CoreGraphics
import XCTest

@testable import WritingCanvas

final class StrokeScoringTests: XCTestCase {
    // MARK: endpoints(ofSVGPath:)

    func testEndpointsOfLineUsesFirstMoveAndLastTerminal() {
        let e = endpoints(ofSVGPath: "M10,10 L90,90")
        XCTAssertEqual(e, StrokeEndpoints(start: CGPoint(x: 10, y: 10),
                                          end: CGPoint(x: 90, y: 90)))
    }

    func testEndpointsOfCubicUsesCubicEnd() {
        let e = endpoints(ofSVGPath: "M0,0 C1,1 2,2 3,3")
        XCTAssertEqual(e, StrokeEndpoints(start: .zero, end: CGPoint(x: 3, y: 3)))
    }

    func testEndpointsOfEmptyIsNil() {
        XCTAssertNil(endpoints(ofSVGPath: ""))
    }

    // MARK: normalize

    func testNormalizeMapsBoundingBoxToUnitSquare() {
        let normalized = normalize([
            StrokeEndpoints(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 90, y: 90)),
        ])
        XCTAssertEqual(normalized, [
            StrokeEndpoints(start: .zero, end: CGPoint(x: 1, y: 1)),
        ])
    }

    func testNormalizeSinglePointReturnsZeros() {
        let normalized = normalize([
            StrokeEndpoints(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5)),
        ])
        XCTAssertEqual(normalized, [
            StrokeEndpoints(start: .zero, end: .zero),
        ])
    }

    // MARK: scoreStrokes

    func testScoreIdenticalSetsIsPerfect() {
        let strokes = [
            StrokeEndpoints(start: .zero, end: CGPoint(x: 1, y: 1)),
            StrokeEndpoints(start: CGPoint(x: 0, y: 1), end: CGPoint(x: 1, y: 0)),
        ]
        let score = scoreStrokes(reference: strokes, drawn: strokes)
        XCTAssertEqual(score, StrokeScore(countMatch: true, matched: 2, total: 2, percent: 100))
    }

    func testScoreOffByOneCountMismatchTotalIsMax() {
        let ref = [
            StrokeEndpoints(start: .zero, end: CGPoint(x: 1, y: 1)),
            StrokeEndpoints(start: CGPoint(x: 0, y: 1), end: CGPoint(x: 1, y: 0)),
        ]
        let drawn = [ref[0]]
        let score = scoreStrokes(reference: ref, drawn: drawn)
        XCTAssertFalse(score.countMatch)
        XCTAssertEqual(score.matched, 1)
        XCTAssertEqual(score.total, 2)
        XCTAssertEqual(score.percent, 50)
    }

    func testFarOffStrokeIsNotMatched() {
        let ref = [StrokeEndpoints(start: .zero, end: CGPoint(x: 1, y: 1))]
        let drawn = [StrokeEndpoints(start: CGPoint(x: 1, y: 1), end: .zero)]
        let score = scoreStrokes(reference: ref, drawn: drawn)
        XCTAssertEqual(score.matched, 0)
        XCTAssertEqual(score.percent, 0)
    }

    func testEmptyScoresZero() {
        let score = scoreStrokes(reference: [], drawn: [])
        XCTAssertEqual(score, StrokeScore(countMatch: true, matched: 0, total: 0, percent: 0))
    }
}
