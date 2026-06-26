import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import SharedModels
import WritingCanvas
import XCTest

@testable import AppFeature

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
}

@MainActor
final class AppFeatureNavTests: XCTestCase {
    func testTapPushesDetailThenWritePushesWriting() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(.kanjiList(.kanjiTapped(.yama)))
        XCTAssertEqual(store.state.path.count, 1)
        XCTAssertEqual(store.state.path.ids.count, 1)
        let id = store.state.path.ids[0]
        guard case .detail = store.state.path[id: id] else {
            return XCTFail("expected a detail destination")
        }

        await store.send(.path(.element(id: id, action: .detail(.writeTapped))))
        XCTAssertEqual(store.state.path.count, 2)
        guard case .writing = store.state.path[id: store.state.path.ids[1]] else {
            return XCTFail("expected a writing destination")
        }
    }
}
