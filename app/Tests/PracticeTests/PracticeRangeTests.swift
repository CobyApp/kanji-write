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

@MainActor
final class PracticeFavoriteTests: XCTestCase {
    /// A favourite is kept by id per mode, so switching to 단어 and back does not
    /// lose the starred kanji.
    func testFavoritesAreKeptPerMode() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        } withDependencies: {
            $0.practiceFavoriteStore.save = { _ in }
            // Switching to 단어 loads that level's vocabulary; the favourites
            // themselves are what this is about.
            $0.dictionaryClient.quizWords = { _, _ in [] }
        }
        store.exhaustivity = .off
        let kanji = PracticeItem(id: 7, answer: "山", glosses: [:])

        await store.send(.toggleFavorite(kanji))
        XCTAssertTrue(store.state.isFavorite(kanji))

        await store.send(.modeSelected(.word))
        XCTAssertEqual(store.state.favoriteCount, 0)

        await store.send(.modeSelected(.kanji))
        XCTAssertEqual(store.state.favoriteIDs, [7])
    }

    /// Starring twice removes it — the star is a toggle, not an add button.
    func testStarringTwiceRemovesTheFavorite() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        } withDependencies: {
            $0.practiceFavoriteStore.save = { _ in }
        }
        store.exhaustivity = .off
        let item = PracticeItem(id: 3, answer: "川", glosses: [:])

        await store.send(.toggleFavorite(item))
        await store.send(.toggleFavorite(item))

        XCTAssertFalse(store.state.isFavorite(item))
        XCTAssertEqual(store.state.favoriteCount, 0)
    }

    /// In 즐겨찾기 scope the run is the starred list, not a slice of the level —
    /// a favourite marked at 2級 must still be testable from 準1級.
    func testFavoriteScopeRunsTheStarredItemsWholesale() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        } withDependencies: {
            $0.practiceFavoriteStore.save = { _ in }
        }
        store.exhaustivity = .off
        await store.send(.setUseFavorites(true))
        await store.send(.favoriteItemsLoaded([
            PracticeItem(id: 1, answer: "山", glosses: [:]),
            PracticeItem(id: 2, answer: "川", glosses: [:]),
        ]))

        await store.send(.startTest)

        XCTAssertEqual(store.state.phase, .testing)
        XCTAssertEqual(store.state.questions.map(\.answer), ["山", "川"])
        XCTAssertEqual(store.state.runCount, 2)
    }

    /// Nothing starred yet → the button is inert rather than starting an empty run.
    func testFavoriteScopeWithNothingStarredDoesNotStart() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        } withDependencies: {
            $0.practiceFavoriteStore.save = { _ in }
        }
        store.exhaustivity = .off
        await store.send(.setUseFavorites(true))

        await store.send(.startTest)

        XCTAssertEqual(store.state.phase, .setup)
        XCTAssertEqual(store.state.runCount, 0)
    }
}

@MainActor
final class PracticeScopeRestoreTests: XCTestCase {
    /// The 즐겨찾기 tile pins the scope before the remembered settings arrive, and
    /// the restore used to overwrite it — the tile opened on 급수별 every time.
    func testTheForcedFavoriteScopeSurvivesTheRestore() async {
        var initial = PracticeFeature.State()
        initial.useFavorites = true
        let store = TestStore(initialState: initial) { PracticeFeature() }
        store.exhaustivity = .off

        await store.send(.restored(PracticeSettings(
            mode: "kanji", level: "N5", start: 0, end: 19, useFavorites: false)))

        XCTAssertTrue(store.state.useFavorites)
    }

    /// Opening the writing test normally still restores the remembered scope.
    func testTheRememberedScopeIsRestoredOtherwise() async {
        let store = TestStore(initialState: PracticeFeature.State()) { PracticeFeature() }
        store.exhaustivity = .off

        await store.send(.restored(PracticeSettings(
            mode: "kanji", level: "N5", start: 0, end: 19, useFavorites: true)))

        XCTAssertTrue(store.state.useFavorites)
    }
}
