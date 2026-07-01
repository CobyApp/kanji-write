import ComposableArchitecture
import Foundation
import SharedModels
import XCTest

@testable import Review

@MainActor
final class WordReviewFeatureTests: XCTestCase {
    func testOnAppearLoadsSavedWordsAndComputesDue() async {
        let day: TimeInterval = 100 * 86_400
        let record = ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5,
                                  due: 100, lastReviewedDay: 95)
        let store = TestStore(initialState: WordReviewFeature.State()) {
            WordReviewFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: day))
            $0.wordReviewStore.loadRecords = { [record] }
            $0.dictionaryClient.word = { id in
                WordEntry(id: id, surface: "山", reading: "やま", meaningEn: "mountain")
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.loaded)
        XCTAssertEqual(store.state.today, 100)
        XCTAssertEqual(store.state.dueIDs, [1])        // due 100 <= today 100
        XCTAssertEqual(store.state.savedIDs, [1])
        XCTAssertEqual(store.state.words[id: 1]?.surface, "山")
    }

    func testGradingNewWordCreatesRecordAndSaves() async {
        let saved = LockIsolated<[ReviewRecord]?>(nil)
        var initial = WordReviewFeature.State()
        initial.today = 100
        let store = TestStore(initialState: initial) {
            WordReviewFeature()
        } withDependencies: {
            $0.wordReviewStore.saveRecords = { saved.setValue($0) }
        }
        store.exhaustivity = .off

        await store.send(.grade(wordID: 42, grade: .good))

        let rec = store.state.records[id: 42]
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.reps, 1)
        XCTAssertEqual(rec?.lapses, 0)
        XCTAssertEqual(rec?.due, 100 + FSRS.interval(stability: FSRS.w[2], retention: 0.9))
        XCTAssertEqual(saved.value?.count, 1)
        XCTAssertEqual(saved.value?.first?.kanjiID, 42)
    }
}
