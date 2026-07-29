import ComposableArchitecture
import SharedModels
import XCTest

@testable import Practice

final class PracticeRangeTests: XCTestCase {
    /// The range is remembered across sessions but the item count is not: 단어 and
    /// 사자성어 load asynchronously, and a level can hold far fewer of them than
    /// the kanji list did. A remembered 1~20 against a list of 3 used to slice
    /// with a start clamped to the list and a length taken from the old range —
    /// two numbers that disagree — and the test could open with no questions.
    func testStartTestClampsBothEndsToWhatTheLevelHolds() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        }
        store.exhaustivity = .off
        await store.send(.loaded(Self.threeKanji, [:]))
        await store.send(.setEnd(19))     // a range remembered from a bigger level

        await store.send(.startTest)

        XCTAssertEqual(store.state.questions.count, 3)
        XCTAssertEqual(store.state.phase, .testing)
    }

    func testStartTestHonoursARangeInsideTheLevel() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        }
        store.exhaustivity = .off
        await store.send(.loaded(Self.threeKanji, [:]))
        await store.send(.setStart(1))
        await store.send(.setEnd(2))

        await store.send(.startTest)

        XCTAssertEqual(store.state.questions.count, 2)
        XCTAssertEqual(store.state.questions.first?.answer, "川")
    }

    /// Closing a run returns to setup, not out of the feature: the level and
    /// range are right there and the next run almost always reuses them.
    func testClosingARunReturnsToSetup() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        }
        store.exhaustivity = .off
        await store.send(.loaded(Self.threeKanji, [:]))
        await store.send(.startTest)
        XCTAssertEqual(store.state.phase, .testing)

        await store.send(.exitToSetup)

        XCTAssertEqual(store.state.phase, .setup)
        XCTAssertTrue(store.state.questions.isEmpty)
    }

    /// 四字熟語 starts at 5級, so 10級 loads an empty list. The range summary read
    /// "1 ~ 0 · 0" there, because `start` is an index and `rangeEnd`/`count`
    /// clamp to a list of none — the view now shows an empty notice instead of a
    /// slider, and these are the numbers that told it to.
    func testAnEmptyLevelReportsNothingToRangeOver() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        }
        store.exhaustivity = .off
        await store.send(.loaded([], [:]))

        XCTAssertEqual(store.state.levelCount, 0)
        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.rangeEnd, 0)
    }

    private static var threeKanji: [Kanji] {
        ["山", "川", "空"].enumerated().map { index, literal in
            Kanji(id: index + 1, literal: literal, strokeCount: 3, grade: 1,
                  jlptLevel: "N5", kankenLevel: "10級",
                  kankenMemberships: ["10級"], hasVerifiedStrokeOrder: true,
                  onReadings: ["サン"], kunReadings: ["やま"], radical: 46)
        }
    }
}
