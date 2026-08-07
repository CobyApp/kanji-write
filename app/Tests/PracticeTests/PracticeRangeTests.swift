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

@MainActor
final class PracticeRadicalTests: XCTestCase {
    /// The 部首 rides along on the item, so the clue card can show it without a
    /// second lookup mid-test.
    func testAKanjiItemCarriesItsRadical() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        }
        store.exhaustivity = .off
        await store.send(.loaded([Self.yama], [:]))

        XCTAssertEqual(store.state.levelItems.first?.radical, "山")
    }

    /// A word has no single radical, and claiming one would put a wrong clue on
    /// the card.
    func testAWordItemHasNoRadical() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        } withDependencies: {
            $0.dictionaryClient.quizWords = { _, _ in
                [WordEntry(id: 1, surface: "火山", reading: "かざん", meaningEn: "volcano", meaningKo: "화산")]
            }
        }
        store.exhaustivity = .off
        await store.send(.loaded([Self.yama], [:]))
        await store.send(.modeSelected(.word))
        await store.send(.wordsLoaded([
            WordEntry(id: 1, surface: "火山", reading: "かざん", meaningEn: "volcano", meaningKo: "화산"),
        ]))

        XCTAssertNil(store.state.levelItems.first?.radical)
    }

    private static var yama: Kanji {
        // radical 46 is 山 — the glyph the card shows comes from this number.
        Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1, jlptLevel: "N5",
              kankenLevel: "10級", kankenMemberships: ["10級"],
              hasVerifiedStrokeOrder: true, onReadings: ["サン"], kunReadings: ["やま"],
              radical: 46)
    }
}

@MainActor
final class PracticeFavoriteRaceTests: XCTestCase {
    /// Favourites and the kanji list load in parallel, and the favourites usually
    /// arrive first. A kanji favourite can only be turned into an item once the
    /// list is here, so the resolution has to run again when it lands — otherwise
    /// the setup screen showed a count from the stored ids while the run was empty
    /// and 테스트 시작 stayed disabled.
    func testFavoritesResolveOnceTheKanjiListArrives() async {
        let store = TestStore(initialState: PracticeFeature.State()) {
            PracticeFeature()
        } withDependencies: {
            $0.practiceFavoriteStore.save = { _ in }
        }
        store.exhaustivity = .off

        await store.send(.favoritesLoaded(["kanji": [1]]))
        XCTAssertEqual(store.state.favoriteCount, 1)
        XCTAssertTrue(store.state.favoriteItems.isEmpty)  // nothing to resolve against

        await store.send(.loaded([Self.yama], [:]))
        await store.receive(\.favoriteItemsLoaded)

        XCTAssertEqual(store.state.favoriteItems.map(\.answer), ["山"])
    }

    private static var yama: Kanji {
        Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1, jlptLevel: "N5",
              kankenLevel: "10級", kankenMemberships: ["10級"],
              hasVerifiedStrokeOrder: true, onReadings: ["サン"], kunReadings: ["やま"],
              radical: 46)
    }
}
