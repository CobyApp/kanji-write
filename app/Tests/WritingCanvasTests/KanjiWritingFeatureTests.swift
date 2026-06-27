import ComposableArchitecture
import CoreGraphics
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

    func testScoreComputesAgainstReferenceStrokePaths() async {
        var initial = KanjiWritingFeature.State(kanji: .yama)
        // Reference endpoints normalize to corners: s1 (0,0)-(1,1), s2 (1,0)-(0,1).
        initial.strokePaths = ["M10,10 L90,90", "M90,10 L10,90"]
        let store = TestStore(initialState: initial) {
            KanjiWritingFeature()
        }
        // Drawn endpoints (already normalized by the view) matching the reference.
        let drawn = [
            StrokeEndpoints(start: .zero, end: CGPoint(x: 1, y: 1)),
            StrokeEndpoints(start: CGPoint(x: 1, y: 0), end: CGPoint(x: 0, y: 1)),
        ]
        await store.send(.score(drawn)) {
            $0.score = StrokeScore(countMatch: true, matched: 2, total: 2, percent: 100)
        }
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
