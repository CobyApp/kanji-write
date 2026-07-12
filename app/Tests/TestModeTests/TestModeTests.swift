import ComposableArchitecture
import SharedModels
import XCTest

@testable import TestMode

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
    private func question(_ id: Int, kanji: Int, answer: Int = 0) -> JLPTQuestion {
        JLPTQuestion(
            id: id, kanjiID: kanji, level: "N5", kind: "reading",
            prompt: "問題\(id)", options: ["あ\(id)", "い\(id)", "う\(id)", "え\(id)"],
            answer: answer, explanations: ["ko": "해설\(id)"])
    }

    func testTodaysStudiedKanjiProduceQuestions() async {
        let day = 100
        let store = TestStore(initialState: QuizFeature.State(level: "N5")) {
            QuizFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: Double(day) * 86_400))
            $0.withRandomNumberGenerator = WithRandomNumberGenerator(SystemRandomNumberGenerator())
            // A kanji studied today (lastReviewedDay == today) feeds the quiz.
            $0.reviewStore.loadRecords = {
                [ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: day + 3, lastReviewedDay: day)]
            }
            $0.quizStore.load = { [] }
            $0.quizStore.save = { _ in }
            $0.dictionaryClient.jlptQuestions = { _, _ in
                [self.question(10, kanji: 1), self.question(11, kanji: 1)]
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(language: .ko))
        await store.receive(\.loaded)
        XCTAssertFalse(store.state.queue.isEmpty)          // today's kanji → questions
        XCTAssertTrue(store.state.started)
    }

    func testPlannedKanjiAreQuizzableBeforeStudy() async {
        let day = 100
        let store = TestStore(initialState: QuizFeature.State(level: "N5", plannedIDs: [7])) {
            QuizFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: Double(day) * 86_400))
            $0.withRandomNumberGenerator = WithRandomNumberGenerator(SystemRandomNumberGenerator())
            $0.reviewStore.loadRecords = { [] }        // nothing studied, nothing due
            $0.quizStore.load = { [] }
            $0.quizStore.save = { _ in }
            $0.dictionaryClient.jlptQuestions = { ids, _ in
                ids.contains(7) ? [self.question(70, kanji: 7)] : []
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(language: .ko))
        await store.receive(\.loaded)
        // Even with no study today, today's planned kanji feed the quiz.
        XCTAssertFalse(store.state.queue.isEmpty)
    }

    func testNewQuestionsCappedAtTwoPerKanji() async {
        let day = 100
        let store = TestStore(initialState: QuizFeature.State(level: "N5")) {
            QuizFeature()
        } withDependencies: {
            $0.date = .constant(Date(timeIntervalSince1970: Double(day) * 86_400))
            $0.withRandomNumberGenerator = WithRandomNumberGenerator(SystemRandomNumberGenerator())
            $0.reviewStore.loadRecords = {
                [ReviewRecord(kanjiID: 1, stability: 5, difficulty: 5, due: day + 3, lastReviewedDay: day)]
            }
            $0.quizStore.load = { [] }
            $0.quizStore.save = { _ in }
            $0.dictionaryClient.jlptQuestions = { _, _ in
                (10...15).map { self.question($0, kanji: 1) }   // 6 available
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(language: .ko))
        await store.receive(\.loaded)
        XCTAssertEqual(store.state.queue.count, 2)             // capped per kanji
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
            $0.dictionaryClient.jlptQuestions = { _, _ in [self.question(10, kanji: 1)] }
        }
        store.exhaustivity = .off

        await store.send(.onAppear(language: .ko))
        await store.receive(\.loaded)
        let item = store.state.current!
        let wrong = item.options.first { $0 != item.answer }!

        await store.send(.chose(wrong))
        await store.send(.next)

        // Scheduled (box 0, due tomorrow) and saved right away — a missed item
        // comes back for review even if the session is abandoned.
        let record = saved.value.first { $0.id == item.id }
        XCTAssertEqual(record?.box, 0)
        XCTAssertEqual(record?.due, day + 1)
        XCTAssertEqual(record?.id, "q:1:10")
    }
}
