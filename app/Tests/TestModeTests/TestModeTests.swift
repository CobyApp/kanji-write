import ComposableArchitecture
import SharedModels
import XCTest

@testable import TestMode

final class KanaDistanceTests: XCTestCase {
    func testDistanceCapturesNearHomophones() {
        XCTAssertEqual(kanaDistance("やま", "やま"), 0)
        XCTAssertEqual(kanaDistance("か", "が"), 1)          // voicing
        XCTAssertEqual(kanaDistance("こう", "こ"), 1)         // long vowel
        XCTAssertEqual(kanaDistance("きって", "きて"), 1)      // small tsu
        XCTAssertEqual(kanaDistance("", "あい"), 2)
    }

    func testNearIsCloserThanFar() {
        // A near-homophone scores lower (more confusing) than an unrelated word.
        XCTAssertLessThan(kanaDistance("しゃかい", "しかい"), kanaDistance("しゃかい", "たべもの"))
    }
}

final class PhoneticTrapsTests: XCTestCase {
    func testTrapsAreMinimalPairsNeverTheAnswer() {
        let traps = Set(phoneticTraps("こうこう"))  // 高校
        XCTAssertFalse(traps.contains("こうこう"))   // never the correct reading
        XCTAssertTrue(traps.contains("ごうこう"))     // voicing (こ→ご)
        XCTAssertTrue(traps.contains("こうこ"))       // dropped long vowel
        XCTAssertGreaterThanOrEqual(traps.count, 3)  // enough to fill 3 options
    }

    func testVoicingAndSmallTsuTraps() {
        XCTAssertTrue(phoneticTraps("かがく").contains("かかく"))   // 化学: が→か
        XCTAssertTrue(phoneticTraps("がっこう").contains("がこう")) // drop small tsu
    }

    func testTrapsAreAlwaysPronounceable() {
        for word in ["いってつ", "こうこう", "がっこう", "しゃかい", "おおきい", "きって"] {
            for trap in phoneticTraps(word) {
                XCTAssertTrue(isPlausibleKana(trap), "\(trap) (from \(word)) must be pronounceable")
            }
        }
    }

    func testImpossibleShapesRejected() {
        XCTAssertFalse(isPlausibleKana("ってつ"))  // leading small tsu (the bug)
        XCTAssertFalse(isPlausibleKana("いてっ"))  // trailing small tsu
        XCTAssertFalse(isPlausibleKana("ーあい"))  // leading chōonpu
        XCTAssertTrue(isPlausibleKana("いってつ"))
        XCTAssertTrue(isPlausibleKana("しゃかい"))
    }
}

final class QuizSRSTests: XCTestCase {
    func testCorrectAdvancesBoxAndLengthensInterval() {
        let new = QuizSRS.schedule(box: nil, correct: true, today: 100)
        XCTAssertEqual(new.box, 0)
        XCTAssertEqual(new.due, 101)              // box 0 → +1 day
        let next = QuizSRS.schedule(box: 0, correct: true, today: 100)
        XCTAssertEqual(next.box, 1)
        XCTAssertEqual(next.due, 103)             // box 1 → +3 days
    }

    func testWrongResetsToBoxZero() {
        let r = QuizSRS.schedule(box: 4, correct: false, today: 100)
        XCTAssertEqual(r.box, 0)
        XCTAssertEqual(r.due, 101)                // seen again tomorrow
    }

    func testBoxCaps() {
        let r = QuizSRS.schedule(box: 5, correct: true, today: 100)
        XCTAssertEqual(r.box, 5)                  // capped
        XCTAssertEqual(r.due, 100 + QuizSRS.intervals[5])
    }
}

@MainActor
final class QuizFeatureTests: XCTestCase {
    private func kanji(_ id: Int, _ literal: String) -> Kanji {
        Kanji(id: id, literal: literal, strokeCount: 1, grade: 1, jlptLevel: "N5",
              onReadings: ["オン"], kunReadings: ["くん"])
    }
    private func word(_ id: Int, _ surface: String, _ reading: String) -> WordEntry {
        WordEntry(id: id, surface: surface, reading: reading, meaningEn: "m\(id)", meaningKo: "뜻\(id)")
    }

    func testTodaysStudiedKanjiProduceQuestions() async {
        let day = 100
        let store = TestStore(initialState: QuizFeature.State(level: "N5")) {
            QuizFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: Double(day) * 86_400))
            $0.withRandomNumberGenerator = WithRandomNumberGenerator(SystemRandomNumberGenerator())
            // A kanji studied today (lastReviewedDay == today) — this was the bug:
            // stale in-memory state hid it; the quiz now reads the store fresh.
            $0.reviewStore.loadRecords = {
                [ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: day + 3, lastReviewedDay: day)]
            }
            $0.quizStore.load = { [] }
            $0.quizStore.save = { _ in }
            $0.dictionaryClient.allKanji = { [self.kanji(1, "山")] }
            $0.dictionaryClient.allGlosses = { [1: ["ko": "메 산", "en": "mountain"]] }
            $0.dictionaryClient.words = { _, _ in [self.word(10, "山", "やま")] }
            $0.dictionaryClient.word = { _ in nil }
            $0.dictionaryClient.antonyms = { _, _ in [] }
            $0.dictionaryClient.sentencesForWord = { _, _ in [] }
            $0.dictionaryClient.quizWords = { _, _ in [self.word(11, "川", "かわ"), self.word(12, "水", "みず")] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(language: .ko))
        await store.receive(\.loaded)
        XCTAssertFalse(store.state.queue.isEmpty)          // today's kanji → questions
        XCTAssertTrue(store.state.started)
    }

    func testOneQuestionPerKanji() async {
        let day = 100
        let store = TestStore(initialState: QuizFeature.State(level: "N5")) {
            QuizFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: Double(day) * 86_400))
            $0.withRandomNumberGenerator = WithRandomNumberGenerator(SystemRandomNumberGenerator())
            // Five kanji studied today.
            $0.reviewStore.loadRecords = {
                (1...5).map {
                    ReviewRecord(kanjiID: $0, stability: 5, difficulty: 5, due: day + 3, lastReviewedDay: day)
                }
            }
            $0.quizStore.load = { [] }
            $0.quizStore.save = { _ in }
            $0.dictionaryClient.allKanji = { (1...5).map { self.kanji($0, "K\($0)") } }
            $0.dictionaryClient.allGlosses = {
                Dictionary(uniqueKeysWithValues: (1...5).map { ($0, ["ko": "뜻\($0)", "en": "m\($0)"]) })
            }
            $0.dictionaryClient.words = { id, _ in [self.word(id * 10, "語\(id)", "ご\(id)")] }
            $0.dictionaryClient.word = { _ in nil }
            $0.dictionaryClient.antonyms = { _, _ in [] }
            $0.dictionaryClient.sentencesForWord = { _, _ in [] }
            $0.dictionaryClient.quizWords = { _, _ in (6...20).map { self.word($0, "W\($0)", "わ\($0)") } }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(language: .ko))
        await store.receive(\.loaded)

        // Exactly one question per studied kanji — no more cramming.
        XCTAssertEqual(store.state.queue.count, 5)
        XCTAssertEqual(store.state.totalItems, 5)
    }

    func testWrongAnswerSchedulesReviewImmediately() async {
        let day = 100
        let saved = LockIsolated<[QuizRecord]>([])
        let store = TestStore(initialState: QuizFeature.State(level: "N5")) {
            QuizFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: Double(day) * 86_400))
            $0.withRandomNumberGenerator = WithRandomNumberGenerator(SystemRandomNumberGenerator())
            $0.reviewStore.loadRecords = {
                [ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: day + 3, lastReviewedDay: day)]
            }
            $0.quizStore.load = { [] }
            $0.quizStore.save = { saved.setValue($0) }
            $0.dictionaryClient.allKanji = { [self.kanji(1, "山")] }
            $0.dictionaryClient.allGlosses = { [1: ["ko": "메 산", "en": "mountain"]] }
            $0.dictionaryClient.words = { _, _ in [self.word(10, "山", "やま")] }
            $0.dictionaryClient.word = { _ in nil }
            $0.dictionaryClient.antonyms = { _, _ in [] }
            $0.dictionaryClient.sentencesForWord = { _, _ in [] }
            $0.dictionaryClient.quizWords = { _, _ in [self.word(11, "川", "かわ"), self.word(12, "水", "みず")] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(language: .ko))
        await store.receive(\.loaded)
        let item = store.state.current!
        let wrong = item.options.first { $0 != item.answer }!

        await store.send(.chose(wrong))
        await store.send(.next)

        // The item is scheduled (box 0, due tomorrow) and saved right away — so a
        // missed item comes back for review even if the session is abandoned.
        let record = saved.value.first { $0.id == item.id }
        XCTAssertEqual(record?.box, 0)
        XCTAssertEqual(record?.due, day + 1)
    }
}
