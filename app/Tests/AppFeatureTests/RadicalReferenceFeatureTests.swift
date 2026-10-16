import ComposableArchitecture
import SharedModels
import XCTest

@testable import AppFeature

private extension RadicalEntry {
    static let kusa = RadicalEntry(
        number: 140, glyph: "艸", strokes: 6, nameJa: "くさかんむり",
        meaningJa: "草", meaningKo: "초두머리(풀)", meaningZh: "草字头", meaningEn: "grass",
        kanjiCount: 253)
    static let kokoro = RadicalEntry(
        number: 61, glyph: "心", strokes: 4, nameJa: "こころ",
        meaningJa: "心", meaningKo: "마음", meaningZh: "心", meaningEn: "heart",
        kanjiCount: 180)
}

@MainActor
final class RadicalReferenceFeatureTests: XCTestCase {
    func testOnAppearLoadsRadicals() async {
        let store = TestStore(initialState: RadicalReferenceFeature.State()) {
            RadicalReferenceFeature()
        } withDependencies: {
            $0.dictionaryClient.radicals = { [.kokoro, .kusa] }
        }
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.loaded) {
            $0.isLoading = false
            $0.radicals = [.kokoro, .kusa]
        }
    }

    func testSearchFiltersByNameMeaningOrNumber() {
        var state = RadicalReferenceFeature.State()
        state.radicals = [.kokoro, .kusa]

        state.searchText = "마음"
        XCTAssertEqual(state.visible.map(\.number), [61])

        state.searchText = "くさ"
        XCTAssertEqual(state.visible.map(\.number), [140])

        state.searchText = "140"
        XCTAssertEqual(state.visible.map(\.number), [140])

        state.searchText = ""
        XCTAssertEqual(state.visible.map(\.number), [61, 140])
    }
}
