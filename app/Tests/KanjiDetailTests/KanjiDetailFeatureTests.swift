import ComposableArchitecture
import SharedModels
import XCTest

@testable import KanjiDetail

private extension Kanji {
    static let yama = Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1,
                            jlptLevel: "N5", onReadings: ["サン"], kunReadings: ["やま"])
}

@MainActor
final class KanjiDetailFeatureTests: XCTestCase {
    func testOnAppearLoadsContent() async {
        let store = TestStore(initialState: KanjiDetailFeature.State(kanji: .yama)) {
            KanjiDetailFeature()
        } withDependencies: {
            $0.dictionaryClient.glosses = { _ in ["ko": "메 산", "en": "mountain"] }
            $0.dictionaryClient.words = { _, _ in
                [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")]
            }
            $0.dictionaryClient.sentences = { _, _ in
                [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])]
            }
            $0.dictionaryClient.relations = { _, _ in
                [RelationEntry(surface: "小", type: "antonym")]
            }
            $0.dictionaryClient.strokeOrder = { _ in ["M10 10", "M20 20", "M30 30"] }
        }
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(
            .loaded(["ko": "메 산", "en": "mountain"],
                    [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")],
                    [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])],
                    [RelationEntry(surface: "小", type: "antonym")],
                    ["M10 10", "M20 20", "M30 30"])
        ) {
            $0.isLoading = false
            $0.glosses = ["ko": "메 산", "en": "mountain"]
            $0.words = [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")]
            $0.sentences = [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])]
            $0.relations = [RelationEntry(surface: "小", type: "antonym")]
            $0.strokePaths = ["M10 10", "M20 20", "M30 30"]
        }
    }
}
