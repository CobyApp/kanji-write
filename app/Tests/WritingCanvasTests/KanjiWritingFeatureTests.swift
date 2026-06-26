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
            $0.drawingStore.loadDrawing = { _ in nil }
        }
        await store.send(.onAppear)
        await store.receive(.strokesLoaded(["d1", "d2", "d3"])) {
            $0.strokePaths = ["d1", "d2", "d3"]
        }
        await store.receive(.drawingLoaded(nil))
    }

    func testToggleGuideFlips() async {
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        }
        await store.send(.toggleGuide) { $0.showGuide = false }
        await store.send(.toggleGuide) { $0.showGuide = true }
    }

    func testOnAppearRestoresSavedDrawing() async {
        let data = Data("saved".utf8)
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        } withDependencies: {
            $0.dictionaryClient.strokeOrder = { _ in [] }
            $0.drawingStore.loadDrawing = { _ in data }
        }
        await store.send(.onAppear)
        await store.receive(.strokesLoaded([]))
        await store.receive(.drawingLoaded(data)) { $0.savedDrawingData = data }
    }

    func testSaveDrawingPersists() async {
        let saved = LockIsolated<(Int, Data)?>(nil)
        let store = TestStore(initialState: KanjiWritingFeature.State(kanji: .yama)) {
            KanjiWritingFeature()
        } withDependencies: {
            $0.drawingStore.saveDrawing = { id, data in saved.setValue((id, data)) }
        }
        let data = Data("ink".utf8)
        await store.send(.saveDrawing(data))
        XCTAssertEqual(saved.value?.0, 1)
        XCTAssertEqual(saved.value?.1, data)
    }
}
