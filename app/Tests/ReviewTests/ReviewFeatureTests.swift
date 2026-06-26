import ComposableArchitecture
import Foundation
import SharedModels
import XCTest

@testable import Review

private extension Kanji {
    static func make(_ id: Int, _ literal: String) -> Kanji {
        Kanji(id: id, literal: literal, strokeCount: 1, grade: 1, jlptLevel: "N5",
              onReadings: [], kunReadings: [])
    }
}

@MainActor
final class ReviewFeatureTests: XCTestCase {
    func testOnAppearLoadsAndComputesToday() async {
        let day: TimeInterval = 100 * 86_400
        let store = TestStore(initialState: ReviewFeature.State()) {
            ReviewFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: day))
            $0.reviewStore.loadRecords = { [] }
            $0.dictionaryClient.allKanji = { [.make(1, "山"), .make(2, "学")] }
        }
        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(.loaded([], [.make(1, "山"), .make(2, "学")], 100)) {
            $0.isLoading = false
            $0.kanji = [.make(1, "山"), .make(2, "学")]
            $0.today = 100
        }
        // both are new (no record) → due
        XCTAssertEqual(store.state.dueKanji.map(\.id), [1, 2])
    }

    func testGradeAdvancesBoxAndSaves() async {
        let saved = LockIsolated<[ReviewRecord]?>(nil)
        var initial = ReviewFeature.State()
        initial.kanji = [.make(1, "山")]
        initial.today = 100
        let store = TestStore(initialState: initial) {
            ReviewFeature()
        } withDependencies: {
            $0.reviewStore.saveRecords = { saved.setValue($0) }
        }
        await store.send(.grade(kanjiID: 1, correct: true)) {
            $0.records[id: 1] = ReviewRecord(kanjiID: 1, box: 1, lastReviewedDay: 100)
        }
        XCTAssertEqual(saved.value, [ReviewRecord(kanjiID: 1, box: 1, lastReviewedDay: 100)])
    }
}
