import ComposableArchitecture
import Review
import SharedModels
import XCTest

@testable import Worksheet

private func k(_ id: Int, literal: String = "x", strokes: Int = 1, level: String? = "N5") -> Kanji {
    Kanji(id: id, literal: literal, strokeCount: strokes, grade: 1, jlptLevel: level,
          onReadings: ["オン"], kunReadings: ["くん"])
}

final class ReadingClassifierTests: XCTestCase {
    // 生: on セイ/ショウ, kun い.きる / なま / き …
    private let sei = Kanji(id: 1, literal: "生", strokeCount: 5, grade: 1, jlptLevel: "N5",
                            onReadings: ["セイ", "ショウ"], kunReadings: ["い.きる", "なま", "き"])
    // 山: on サン, kun やま
    private let yama = Kanji(id: 2, literal: "山", strokeCount: 3, grade: 1, jlptLevel: "N5",
                             onReadings: ["サン"], kunReadings: ["やま"])

    private func w(_ surface: String, _ reading: String) -> WordEntry {
        WordEntry(id: 1, surface: surface, reading: reading, meaningEn: "m")
    }

    func testCompoundClassifiesAsOn() {
        XCTAssertEqual(classifyReading(word: w("学生", "がくせい"), kanji: sei), .on)   // セイ
        XCTAssertEqual(classifyReading(word: w("富士山", "ふじさん"), kanji: yama), .on) // サン
    }

    func testNativeWordClassifiesAsKun() {
        XCTAssertEqual(classifyReading(word: w("生", "なま"), kanji: sei), .kun)   // なま
        XCTAssertEqual(classifyReading(word: w("山", "やま"), kanji: yama), .kun)  // やま
    }

    func testUnmatchedReadingIsNil() {
        XCTAssertNil(classifyReading(word: w("外", "そと"), kanji: yama))  // neither サン nor やま
    }
}

final class WorksheetQueueTests: XCTestCase {
    func testQueueHoldsOnlyNeverSeenKanjiInStudyOrder() {
        // kanji 1 already has a record → seen; the rest are new. studyOrder sorts
        // by JLPT then ascending strokes then id.
        let records = [
            ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: 10, lastReviewedDay: 5),
        ]
        let kanji = [
            k(1, strokes: 1),
            k(2, strokes: 3),
            k(3, strokes: 2),
            k(4, strokes: 5),
        ]
        let queue = buildWorksheetQueue(records: records, kanji: kanji, today: 10, newPerDay: 7)
        // 1 is seen; remaining ordered by strokes: 3 (2), 2 (3), 4 (5).
        XCTAssertEqual(queue.map(\.id), [3, 2, 4])
    }

    func testQueueRespectsNewPerDayCap() {
        let kanji = [k(1, strokes: 1), k(2, strokes: 2), k(3, strokes: 3)]
        let queue = buildWorksheetQueue(records: [], kanji: kanji, today: 0, newPerDay: 2)
        XCTAssertEqual(queue.map(\.id), [1, 2])
    }

    func testQueueEmptyWhenAllSeen() {
        let records = [
            ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: 0, lastReviewedDay: 0),
            ReviewRecord(kanjiID: 2, stability: 5, difficulty: 5, due: 0, lastReviewedDay: 0),
        ]
        let queue = buildWorksheetQueue(records: records, kanji: [k(1), k(2)], today: 0, newPerDay: 7)
        XCTAssertTrue(queue.isEmpty)
    }
}

@MainActor
final class WorksheetFeatureReducerTests: XCTestCase {
    func testNextAdvancesAndReloadsContent() async {
        let store = TestStore(initialState: WorksheetFeature.State()) {
            WorksheetFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 100 * 86_400))
            $0.reviewStore.loadRecords = { [] }
            $0.dictionaryClient.allKanji = { [k(1, strokes: 1), k(2, strokes: 2)] }
            $0.dictionaryClient.words = { _, _ in [] }
            $0.dictionaryClient.sentences = { _, _ in [] }
            $0.dictionaryClient.strokeOrder = { _ in [] }
            $0.dictionaryClient.glosses = { _ in [:] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(newPerDay: 7, level: nil))
        await store.receive(\.loaded)
        await store.receive(\.contentLoaded)

        XCTAssertEqual(store.state.queue.map(\.id), [1, 2])
        XCTAssertFalse(store.state.isLast)

        // Content is prefetched for the whole queue, so advancing is instant.
        await store.send(.nextTapped) { $0.index = 1 }
        XCTAssertTrue(store.state.isLast)
    }

    func testDoneSchedulesInitialRecordsForEveryLearnedKanji() async {
        var saved: [ReviewRecord] = []
        let store = TestStore(initialState: WorksheetFeature.State()) {
            WorksheetFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 100 * 86_400))
            $0.reviewStore.loadRecords = { [] }
            $0.reviewStore.saveRecords = { records in saved = records }
            $0.dictionaryClient.allKanji = { [k(1, strokes: 1), k(2, strokes: 2)] }
            $0.dictionaryClient.words = { _, _ in [] }
            $0.dictionaryClient.sentences = { _, _ in [] }
            $0.dictionaryClient.strokeOrder = { _ in [] }
            $0.dictionaryClient.glosses = { _ in [:] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(newPerDay: 7, level: nil))
        await store.receive(\.loaded)
        await store.receive(\.contentLoaded)

        await store.send(.doneTapped) { $0.isFinished = true }

        // Both learned kanji were scheduled, due strictly after today (100).
        XCTAssertEqual(Set(saved.map(\.kanjiID)), [1, 2])
        for record in saved {
            XCTAssertGreaterThan(record.due, 100)
            XCTAssertEqual(record.lastReviewedDay, 100)
            XCTAssertEqual(record.reps, 1)
            XCTAssertEqual(record.lapses, 0)
        }
    }

    func testDoneDoesNotOverwriteExistingRecord() async {
        let existing = ReviewRecord(
            kanjiID: 2, stability: 42, difficulty: 3, due: 500, lastReviewedDay: 80, lapses: 2, reps: 9)
        var saved: [ReviewRecord] = []
        let store = TestStore(initialState: WorksheetFeature.State()) {
            WorksheetFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: 100 * 86_400))
            // kanji 2 already known; only kanji 1 is a new lesson today.
            $0.reviewStore.loadRecords = { [existing] }
            $0.reviewStore.saveRecords = { records in saved = records }
            $0.dictionaryClient.allKanji = { [k(1, strokes: 1), k(2, strokes: 2)] }
            $0.dictionaryClient.words = { _, _ in [] }
            $0.dictionaryClient.sentences = { _, _ in [] }
            $0.dictionaryClient.strokeOrder = { _ in [] }
            $0.dictionaryClient.glosses = { _ in [:] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(newPerDay: 7, level: nil))
        await store.receive(\.loaded)
        await store.receive(\.contentLoaded)

        // Only kanji 1 is in today's queue (2 is already seen).
        XCTAssertEqual(store.state.queue.map(\.id), [1])

        await store.send(.doneTapped)

        // The pre-existing record for kanji 2 is preserved untouched.
        let untouched = saved.first { $0.kanjiID == 2 }
        XCTAssertEqual(untouched, existing)
        XCTAssertNotNil(saved.first { $0.kanjiID == 1 })
    }
}
