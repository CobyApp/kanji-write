import XCTest

@testable import Review

final class FSRSTests: XCTestCase {
    func testInitialStabilityEqualsWeights() {
        XCTAssertEqual(FSRS.initialState(.again).stability, FSRS.w[0], accuracy: 1e-9)
        XCTAssertEqual(FSRS.initialState(.hard).stability, FSRS.w[1], accuracy: 1e-9)
        XCTAssertEqual(FSRS.initialState(.good).stability, FSRS.w[2], accuracy: 1e-9)
        XCTAssertEqual(FSRS.initialState(.easy).stability, FSRS.w[3], accuracy: 1e-9)
    }

    func testInitialStabilityOrdersByGrade() {
        XCTAssertLessThan(FSRS.initialState(.again).stability, FSRS.initialState(.good).stability)
        XCTAssertLessThan(FSRS.initialState(.good).stability, FSRS.initialState(.easy).stability)
    }

    func testDifficultyStaysInRange() {
        for g in Grade.allCases {
            let d = FSRS.initialState(g).difficulty
            XCTAssertGreaterThanOrEqual(d, 1)
            XCTAssertLessThanOrEqual(d, 10)
        }
        // Again is harder (higher D) than Easy.
        XCTAssertGreaterThan(FSRS.initialState(.again).difficulty, FSRS.initialState(.easy).difficulty)
    }

    func testRetrievabilityCurve() {
        XCTAssertEqual(FSRS.retrievability(elapsedDays: 0, stability: 10), 1, accuracy: 1e-9)
        // At t = 9S, R = 0.5.
        XCTAssertEqual(FSRS.retrievability(elapsedDays: 90, stability: 10), 0.5, accuracy: 1e-9)
    }

    func testIntervalEqualsStabilityAt90Percent() {
        // 9·S·(1/0.9 - 1) = S
        XCTAssertEqual(FSRS.interval(stability: 10, retention: 0.9), 10)
        XCTAssertEqual(FSRS.interval(stability: 5, retention: 0.9), 5)
        XCTAssertGreaterThanOrEqual(FSRS.interval(stability: 0.1, retention: 0.9), 1)  // floored
    }

    func testHigherRetentionMeansShorterInterval() {
        XCTAssertLessThan(
            FSRS.interval(stability: 50, retention: 0.95),
            FSRS.interval(stability: 50, retention: 0.9))
    }

    func testGoodReviewGrowsStability() {
        let first = FSRS.schedule(state: nil, grade: .good, elapsedDays: 0)
        // After the interval elapses, a Good review increases stability.
        let second = FSRS.schedule(state: first.state, grade: .good,
                                   elapsedDays: first.intervalDays)
        XCTAssertGreaterThan(second.state.stability, first.state.stability)
        XCTAssertGreaterThan(second.intervalDays, first.intervalDays)
    }

    func testAgainLapsesStabilityDown() {
        let mature = MemoryState(stability: 50, difficulty: 5)
        let lapsed = FSRS.schedule(state: mature, grade: .again, elapsedDays: 50)
        XCTAssertLessThan(lapsed.state.stability, mature.stability)
    }

    func testLowerRetrievabilityGivesLargerStabilityGain() {
        let state = MemoryState(stability: 20, difficulty: 5)
        // Reviewing late (lower R) yields a larger stability than reviewing early.
        let early = FSRS.schedule(state: state, grade: .good, elapsedDays: 5)
        let late = FSRS.schedule(state: state, grade: .good, elapsedDays: 40)
        XCTAssertGreaterThan(late.state.stability, early.state.stability)
    }
}
