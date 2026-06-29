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
    }

    func testGradingNewKanjiCreatesFSRSRecordAndSaves() async {
        let saved = LockIsolated<[ReviewRecord]?>(nil)
        var initial = ReviewFeature.State()
        initial.kanji = [.make(1, "山")]
        initial.today = 100
        let store = TestStore(initialState: initial) {
            ReviewFeature()
        } withDependencies: {
            $0.reviewStore.saveRecords = { saved.setValue($0) }
        }
        store.exhaustivity = .off

        await store.send(.grade(kanjiID: 1, grade: .good))

        let rec = store.state.records[id: 1]
        XCTAssertNotNil(rec)
        XCTAssertEqual(rec?.stability ?? 0, FSRS.w[2], accuracy: 1e-9)  // S0(Good)
        XCTAssertEqual(rec?.reps, 1)
        XCTAssertEqual(rec?.lapses, 0)
        // due = today + interval(S0(Good)=3.173 @0.9 ≈ 3)
        XCTAssertEqual(rec?.due, 100 + FSRS.interval(stability: FSRS.w[2], retention: 0.9))
        XCTAssertEqual(saved.value?.count, 1)
    }

    func testGradingAgainCountsLapse() async {
        var initial = ReviewFeature.State()
        initial.kanji = [.make(1, "山")]
        initial.today = 100
        initial.records = [ReviewRecord(
            kanjiID: 1, stability: 20, difficulty: 5, due: 100, lastReviewedDay: 80)]
        let store = TestStore(initialState: initial) { ReviewFeature() }
            withDependencies: { $0.reviewStore.saveRecords = { _ in } }
        store.exhaustivity = .off

        await store.send(.grade(kanjiID: 1, grade: .again))
        XCTAssertEqual(store.state.records[id: 1]?.lapses, 1)
        XCTAssertEqual(store.state.records[id: 1]?.reps, 2)
        XCTAssertLessThan(store.state.records[id: 1]!.stability, 20)  // lapsed down
    }
}
