import ComposableArchitecture
import SharedModels
import XCTest

@testable import TestMode

private func k(_ id: Int, literal: String = "x") -> Kanji {
    Kanji(id: id, literal: literal, strokeCount: 1, grade: 1, jlptLevel: "N5",
          onReadings: ["オン"], kunReadings: ["くん"])
}

final class TestModeQueueTests: XCTestCase {
    func testQueueHoldsOnlyDueCardsOrderedByDueThenDifficulty() {
        let records = [
            ReviewRecord(kanjiID: 1, stability: 5, difficulty: 8, due: 100, lastReviewedDay: 90),
            ReviewRecord(kanjiID: 2, stability: 5, difficulty: 2, due: 100, lastReviewedDay: 90),
            ReviewRecord(kanjiID: 3, stability: 5, difficulty: 5, due: 99, lastReviewedDay: 90),
            ReviewRecord(kanjiID: 4, stability: 5, difficulty: 5, due: 200, lastReviewedDay: 90),
        ]
        let kanji = [k(1), k(2), k(3), k(4)]
        let queue = buildTestQueue(records: records, kanji: kanji, today: 100)
        // due 99 first; then due 100 by ascending difficulty (2, 8); id 4 not due.
        XCTAssertEqual(queue.map(\.id), [3, 2, 1])
    }

    func testQueueDropsIDsWithNoMatchingKanji() {
        let records = [
            ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: 10, lastReviewedDay: 5),
            ReviewRecord(kanjiID: 99, stability: 5, difficulty: 5, due: 10, lastReviewedDay: 5),
        ]
        // kanji 99 is absent, so it must not appear in the queue.
        let queue = buildTestQueue(records: records, kanji: [k(1)], today: 10)
        XCTAssertEqual(queue.map(\.id), [1])
    }

    func testEmptyWhenNothingDue() {
        let records = [
            ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: 100, lastReviewedDay: 90),
        ]
        XCTAssertTrue(buildTestQueue(records: records, kanji: [k(1)], today: 50).isEmpty)
    }
}

@MainActor
final class TestFeatureReducerTests: XCTestCase {
    func testPassSchedulesGoodAndAdvances() async throws {
        let record = ReviewRecord(
            kanjiID: 1, stability: 5, difficulty: 5, due: 100, lastReviewedDay: 95)
        // A second due card so advancing loads the next card's content.
        let record2 = ReviewRecord(
            kanjiID: 2, stability: 5, difficulty: 9, due: 100, lastReviewedDay: 95)
        var saved: [ReviewRecord] = []

        let store = TestStore(initialState: TestFeature.State()) {
            TestFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 100 * 86_400))
            $0.reviewStore.loadRecords = { [record, record2] }
            $0.reviewStore.saveRecords = { records in saved = records }
            $0.dictionaryClient.allKanji = { [k(1), k(2)] }
            $0.dictionaryClient.glosses = { _ in ["en": "one"] }
            $0.dictionaryClient.strokeOrder = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.loaded)
        await store.receive(\.cardContentLoaded)

        await store.send(.showAnswerTapped) { $0.revealed = true }

        await store.send(.graded(pass: true)) {
            $0.index = 1
            $0.revealed = false
        }
        await store.receive(\.cardContentLoaded)

        // The graded card was persisted; pass grade must push its due beyond today.
        let updated = try XCTUnwrap(saved.first { $0.kanjiID == 1 })
        XCTAssertEqual(updated.reps, record.reps + 1)
        XCTAssertGreaterThan(updated.due, 100)
        XCTAssertEqual(updated.lapses, 0)
    }

    func testFailCountsAsLapse() async {
        let record = ReviewRecord(
            kanjiID: 1, stability: 20, difficulty: 5, due: 100, lastReviewedDay: 80)
        var saved: [ReviewRecord] = []

        let store = TestStore(initialState: TestFeature.State()) {
            TestFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 100 * 86_400))
            $0.reviewStore.loadRecords = { [record] }
            $0.reviewStore.saveRecords = { records in saved = records }
            $0.dictionaryClient.allKanji = { [k(1)] }
            $0.dictionaryClient.glosses = { _ in ["en": "one"] }
            $0.dictionaryClient.strokeOrder = { _ in [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.loaded)
        await store.receive(\.cardContentLoaded)
        await store.send(.graded(pass: false))

        let updated = saved.first { $0.kanjiID == 1 }
        XCTAssertEqual(updated?.lapses, record.lapses + 1)
        XCTAssertEqual(updated?.reps, record.reps + 1)
    }

    func testFinishesWhenQueueEmpty() async {
        let store = TestStore(initialState: TestFeature.State()) {
            TestFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 0))
            $0.reviewStore.loadRecords = { [] }
            $0.dictionaryClient.allKanji = { [] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.loaded) {
            $0.queue = []
        }
        XCTAssertTrue(store.state.isFinished)
    }
}
