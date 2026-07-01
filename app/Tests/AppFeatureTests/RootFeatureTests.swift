import ComposableArchitecture
import KanjiDetail
import Review
import SharedModels
import WritingCanvas
import XCTest

@testable import AppFeature

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
}

@MainActor
final class RootFeatureTests: XCTestCase {
    func testSidebarAndSearchSelection() async {
        let store = TestStore(initialState: RootFeature.State()) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.sidebarSelected(.settings))
        XCTAssertEqual(store.state.sidebar, .settings)
        await store.send(.sidebarSelected(.level("N5")))
        XCTAssertEqual(store.state.sidebar, .level("N5"))
        await store.send(.searchChanged("山"))
        XCTAssertEqual(store.state.searchText, "山")
    }

    func testKanjiSelectedOpensDetail() async {
        let store = TestStore(initialState: RootFeature.State()) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.kanjiSelected(.yama))
        XCTAssertEqual(store.state.detail?.kanji, .yama)
        XCTAssertNil(store.state.writing)
    }

    func testReviewTapOpensDetail() async {
        let store = TestStore(initialState: RootFeature.State()) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.review(.kanjiTapped(.yama)))
        XCTAssertEqual(store.state.detail?.kanji, .yama)
    }

    func testWriteTappedPushesWritingCanvas() async {
        var initial = RootFeature.State()
        initial.detail = KanjiDetailFeature.State(kanji: .yama)
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.detail(.presented(.writeTapped)))
        XCTAssertEqual(store.state.writing?.kanji, .yama)
    }

    func testTabSwitchClearsPushedDetailAndWriting() async {
        var initial = RootFeature.State()
        initial.detail = KanjiDetailFeature.State(kanji: .yama)
        initial.writing = KanjiWritingFeature.State(kanji: .yama)
        let store = TestStore(initialState: initial) { RootFeature() }
        store.exhaustivity = .off

        await store.send(.tabSelected(.browse))
        XCTAssertEqual(store.state.tab, .browse)
        XCTAssertNil(store.state.detail)
        XCTAssertNil(store.state.writing)
    }
}
