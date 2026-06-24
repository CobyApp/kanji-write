import ComposableArchitecture
import SharedModels
import XCTest

@testable import KanjiListFeature

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
    static let gaku = Kanji(id: 2, literal: "学", strokeCount: 8, grade: 1,
                            jlptLevel: "N5", onReadings: ["ガク"], kunReadings: ["まな.ぶ"])
}

@MainActor
final class KanjiListFeatureTests: XCTestCase {
    func testOnAppearLoadsKanji() async {
        let store = TestStore(initialState: KanjiListFeature.State()) {
            KanjiListFeature()
        } withDependencies: {
            $0.dictionaryClient.allKanji = { [.yama, .gaku] }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(.kanjiLoaded([.yama, .gaku])) {
            $0.isLoading = false
            $0.kanji = [.yama, .gaku]
        }
    }

    func testOnAppearFailureSetsError() async {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "boom" } }
        let store = TestStore(initialState: KanjiListFeature.State()) {
            KanjiListFeature()
        } withDependencies: {
            $0.dictionaryClient.allKanji = { throw Boom() }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(.loadFailed("boom")) {
            $0.isLoading = false
            $0.loadError = "boom"
        }
    }
}
