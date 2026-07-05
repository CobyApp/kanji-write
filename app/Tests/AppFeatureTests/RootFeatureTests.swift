import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import Practice
import Review
import SharedModels
import TestMode
import Worksheet
import WritingCanvas
import XCTest

@testable import AppFeature

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
    static let gaku = Kanji(id: 2, literal: "学", strokeCount: 8, grade: 1,
                            jlptLevel: "N5", onReadings: ["ガク"], kunReadings: ["まな.ぶ"])
}

private extension WordEntry {
    static let yamamichi = WordEntry(id: 10, surface: "山道", reading: "やまみち",
                                     meaningEn: "mountain path")
}

@MainActor
final class RootFeatureTests: XCTestCase {
    func testSettingsSheetToggles() async {
        let store = TestStore(initialState: RootFeature.State()) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.setShowSettings(true))
        XCTAssertTrue(store.state.showSettings)
        await store.send(.setShowSettings(false))
        XCTAssertFalse(store.state.showSettings)
    }

    func testOpenDictionaryPushesBrowse() async {
        var initial = RootFeature.State()
        initial.review.kanji = IdentifiedArray(uniqueElements: [.yama])
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.openDictionary)
        guard case .dictionary = store.state.path.first else {
            return XCTFail("expected the dictionary browse pushed as the stack root")
        }
    }

    func testKanjiSelectedMakesKanjiTheStackRoot() async {
        let store = TestStore(initialState: RootFeature.State()) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.kanjiSelected(.yama))
        XCTAssertEqual(store.state.path.count, 1)
        guard case let .kanji(detail) = store.state.path.first else {
            return XCTFail("expected a kanji at the stack root")
        }
        XCTAssertEqual(detail.kanji, .yama)
    }

    func testLevelSelectedPushesKanjiList() async {
        var initial = RootFeature.State()
        initial.review.kanji = IdentifiedArray(uniqueElements: [.yama, .gaku])
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.levelSelected(KanjiLevel(level: "N5")))
        guard case let .kanjiList(list) = store.state.path.first else {
            return XCTFail("expected a kanji list at the stack root")
        }
        XCTAssertEqual(list.kanji, [.yama, .gaku])
    }

    func testWordTappedInKanjiDetailPushesWordDetail() async {
        var initial = RootFeature.State()
        initial.path = StackState([.kanji(KanjiDetailFeature.State(kanji: .yama))])
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        let id = store.state.path.ids.first!
        await store.send(.path(.element(id: id, action: .kanji(.wordTapped(.yamamichi)))))
        XCTAssertEqual(store.state.path.count, 2)
        guard case let .word(word) = store.state.path.last else {
            return XCTFail("expected a word pushed on top")
        }
        XCTAssertEqual(word.word, .yamamichi)
    }

    func testKanjiTappedInWordDetailPushesKanjiDetail() async {
        var initial = RootFeature.State()
        initial.path = StackState([.word(WordDetailFeature.State(word: .yamamichi))])
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        let id = store.state.path.ids.first!
        await store.send(.path(.element(id: id, action: .word(.kanjiTapped(.gaku)))))
        XCTAssertEqual(store.state.path.count, 2)
        guard case let .kanji(detail) = store.state.path.last else {
            return XCTFail("expected a kanji pushed on top")
        }
        XCTAssertEqual(detail.kanji, .gaku)
    }

    func testWriteTappedPushesWritingCanvas() async {
        var initial = RootFeature.State()
        initial.path = StackState([.kanji(KanjiDetailFeature.State(kanji: .yama))])
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        let id = store.state.path.ids.first!
        await store.send(.path(.element(id: id, action: .kanji(.writeTapped))))
        XCTAssertEqual(store.state.path.count, 2)
        guard case let .writing(writing) = store.state.path.last else {
            return XCTFail("expected the writing canvas pushed on top")
        }
        XCTAssertEqual(writing.kanji, .yama)
    }

    func testStartStudyPresentsWorksheetSession() async {
        let store = TestStore(initialState: RootFeature.State()) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.startStudy)
        guard case .worksheet = store.state.session else {
            return XCTFail("expected a worksheet session")
        }
    }

    func testStartPracticePresentsPracticeSession() async {
        let store = TestStore(initialState: RootFeature.State()) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.startPractice)
        guard case .practice = store.state.session else {
            return XCTFail("expected a practice session")
        }
    }

    func testDismissingSessionClearsIt() async {
        var initial = RootFeature.State()
        initial.session = .worksheet(WorksheetFeature.State())
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.session(.dismiss))
        XCTAssertNil(store.state.session)
    }

    // MARK: In-session navigation (drilling while studying)

    func testWordTappedWhileStudyingDrillsOnSessionPath() async {
        var initial = RootFeature.State()
        initial.session = .worksheet(WorksheetFeature.State())
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.session(.presented(.worksheet(.wordTapped(.yamamichi)))))
        XCTAssertEqual(store.state.sessionPath.count, 1)
        guard case let .word(word) = store.state.sessionPath.first else {
            return XCTFail("expected the word pushed on the in-session stack")
        }
        XCTAssertEqual(word.word, .yamamichi)
    }

    func testKanjiTappedInSessionWordDrillsToKanji() async {
        var initial = RootFeature.State()
        initial.session = .worksheet(WorksheetFeature.State())
        initial.sessionPath = StackState([.word(WordDetailFeature.State(word: .yamamichi))])
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        let id = store.state.sessionPath.ids.first!
        await store.send(.sessionPath(.element(id: id, action: .word(.kanjiTapped(.gaku)))))
        XCTAssertEqual(store.state.sessionPath.count, 2)
        guard case let .kanji(detail) = store.state.sessionPath.last else {
            return XCTFail("expected the kanji pushed on the in-session stack")
        }
        XCTAssertEqual(detail.kanji, .gaku)
    }

    func testDismissingSessionClearsSessionPath() async {
        var initial = RootFeature.State()
        initial.session = .worksheet(WorksheetFeature.State())
        initial.sessionPath = StackState([.word(WordDetailFeature.State(word: .yamamichi))])
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.session(.dismiss))
        XCTAssertTrue(store.state.sessionPath.isEmpty)
    }
}
