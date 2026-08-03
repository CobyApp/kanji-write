import ComposableArchitecture
import Foundation
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
            $0.dictionaryClient.variants = { _ in [] }
            $0.kanjiBookmarkStore.load = { [] }
        }
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(
            .loaded(["ko": "메 산", "en": "mountain"],
                    [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")],
                    [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])],
                    [RelationEntry(surface: "小", type: "antonym")],
                    ["M10 10", "M20 20", "M30 30"],
                    [])
        ) {
            $0.isLoading = false
            $0.glosses = ["ko": "메 산", "en": "mountain"]
            $0.words = [WordEntry(id: 10, surface: "火山", reading: "かざん", meaningEn: "volcano")]
            $0.sentences = [ExampleSentence(id: 20, textJa: "山が高い。", translations: ["ko": "산이 높다."])]
            $0.relations = [RelationEntry(surface: "小", type: "antonym")]
            $0.strokePaths = ["M10 10", "M20 20", "M30 30"]
        }
        await store.receive(.bookmarkLoaded(false))
    }

    func testAddToReviewAddsNewRecord() async {
        let saved = LockIsolated<[ReviewRecord]?>(nil)
        let store = TestStore(initialState: KanjiDetailFeature.State(kanji: .yama)) {
            KanjiDetailFeature()
        } withDependencies: {
            $0.reviewStore.loadRecords = { [] }
            $0.reviewStore.saveRecords = { saved.setValue($0) }
            $0.date = .constant(Date(timeIntervalSince1970: 100 * 86_400))
        }
        await store.send(.addToReview)
        await store.receive(.markedAddedToReview) { $0.addedToReview = true }
        // A fresh FSRS record, due today, not yet reviewed.
        let rec = saved.value?.first
        XCTAssertEqual(rec?.kanjiID, 1)
        XCTAssertEqual(rec?.due, 100)
        XCTAssertEqual(rec?.lastReviewedDay, 100)
        XCTAssertEqual(rec?.reps, 0)
    }

    func testAddToReviewDoesNotDuplicateExistingRecord() async {
        let existing = ReviewRecord(
            kanjiID: 1, stability: 5, difficulty: 5, due: 60, lastReviewedDay: 50)
        let saved = LockIsolated<[ReviewRecord]?>(nil)
        let store = TestStore(initialState: KanjiDetailFeature.State(kanji: .yama)) {
            KanjiDetailFeature()
        } withDependencies: {
            $0.reviewStore.loadRecords = { [existing] }
            $0.reviewStore.saveRecords = { saved.setValue($0) }
            $0.date = .constant(Date(timeIntervalSince1970: 100 * 86_400))
        }
        await store.send(.addToReview)
        await store.receive(.markedAddedToReview) { $0.addedToReview = true }
        // The existing record must not be duplicated; at most one record for this id.
        let recordsForYama = (saved.value ?? [existing]).filter { $0.kanjiID == 1 }
        XCTAssertEqual(recordsForYama, [existing])
    }
}

@MainActor
final class KanjiVariantTests: XCTestCase {
    /// 旧字 forms come down with the rest of the detail payload and land in
    /// state, so the section appears without a second round trip.
    func testAnOldFormReachesTheDetailState() async {
        let store = TestStore(
            initialState: KanjiDetailFeature.State(kanji: Self.yama, siblings: [Self.yama])
        ) {
            KanjiDetailFeature()
        } withDependencies: {
            $0.dictionaryClient.glosses = { _ in [:] }
            $0.dictionaryClient.words = { _, _ in [] }
            $0.dictionaryClient.sentences = { _, _ in [] }
            $0.dictionaryClient.relations = { _, _ in [] }
            $0.dictionaryClient.strokeOrder = { _ in [] }
            $0.dictionaryClient.variants = { _ in [Self.oldForm] }
            $0.kanjiBookmarkStore.load = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.loaded)

        XCTAssertEqual(store.state.variants, [Self.oldForm])
    }

    /// Stepping to the next kanji must clear the previous one's variant, or the
    /// old form of 山 would sit under 川.
    func testSteppingToASiblingClearsTheOldForm() async {
        var initial = KanjiDetailFeature.State(kanji: Self.yama,
                                               siblings: [Self.yama, Self.kawa])
        initial.variants = [Self.oldForm]
        let store = TestStore(initialState: initial) { KanjiDetailFeature() }
            withDependencies: {
                $0.dictionaryClient.glosses = { _ in [:] }
                $0.dictionaryClient.words = { _, _ in [] }
                $0.dictionaryClient.sentences = { _, _ in [] }
                $0.dictionaryClient.relations = { _, _ in [] }
                $0.dictionaryClient.strokeOrder = { _ in [] }
                $0.dictionaryClient.variants = { _ in [] }
                $0.kanjiBookmarkStore.load = { [] }
            }
        store.exhaustivity = .off

        await store.send(.showSibling(delta: 1))

        XCTAssertTrue(store.state.variants.isEmpty)
    }

    private static let oldForm = KanjiVariant(
        id: 1, variantKind: "旧字", pathD: "M 10 10 L 20 20 Z", viewBox: 200,
        sourceURL: "https://glyphwiki.org/wiki/u5c71", licenseURL: "https://glyphwiki.org/wiki/GlyphWiki:License")

    private static var yama: Kanji {
        Kanji(id: 1, literal: "山", strokeCount: 3, grade: 1, jlptLevel: "N5",
              kankenLevel: "10級", kankenMemberships: ["10級"],
              hasVerifiedStrokeOrder: true, onReadings: ["サン"], kunReadings: ["やま"],
              radical: 46)
    }
    private static var kawa: Kanji {
        Kanji(id: 2, literal: "川", strokeCount: 3, grade: 1, jlptLevel: "N5",
              kankenLevel: "10級", kankenMemberships: ["10級"],
              hasVerifiedStrokeOrder: true, onReadings: ["セン"], kunReadings: ["かわ"],
              radical: 47)
    }
}
