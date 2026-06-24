import ComposableArchitecture
import SharedModels
import XCTest

@testable import WritingCanvas

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
}

@MainActor
final class KanjiWritingFeatureTests: XCTestCase {
    func testOnAppearLoadsStrokePaths() async {
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        } withDependencies: {
            $0.dictionaryClient.strokeOrder = { _ in ["d1", "d2", "d3"] }
        }
        await store.send(.onAppear)
        await store.receive(.strokesLoaded(["d1", "d2", "d3"])) {
            $0.strokePaths = ["d1", "d2", "d3"]
        }
    }

    func testToggleGuideFlips() async {
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        }
        await store.send(.toggleGuide) { $0.showGuide = false }
        await store.send(.toggleGuide) { $0.showGuide = true }
    }
}
