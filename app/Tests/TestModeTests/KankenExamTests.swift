import ComposableArchitecture
import Foundation
import Review
import SharedModels
import XCTest

@testable import TestMode

final class ExamScoringTests: XCTestCase {
    func testKankenRankOrdersEveryLevel() {
        XCTAssertEqual(ExamType.kankenRank("10級"), 1)
        XCTAssertEqual(ExamType.kankenRank("2級"), 10)
        XCTAssertEqual(ExamType.kankenRank("1級"), 12)
        XCTAssertNil(ExamType.kankenRank("N3"))
    }

    func testPassLinesFollowTheOfficialCriteria() {
        XCTAssertEqual(ExamType.kanken.passRatio(for: "10級"), 0.8)   // 120/150
        XCTAssertEqual(ExamType.kanken.passRatio(for: "5級"), 0.7)    // 140/200
        XCTAssertEqual(ExamType.kanken.passRatio(for: "準2級"), 0.7)
        XCTAssertEqual(ExamType.kanken.passRatio(for: "2級"), 0.8)    // 160/200
        XCTAssertEqual(ExamType.kanken.officialMinutes(for: "8級"), 40)
        XCTAssertEqual(ExamType.kanken.officialMinutes(for: "7級"), 60)
        XCTAssertFalse(ExamType.jlpt.hasOfficialPassLine)
    }
}

final class ExamGeneratorTests: XCTestCase {
    func testOnKunNeverOffersAnotherReadingOfTheSameKanji() {
        // 行 reads both コウ and ギョウ; ギョウ must not appear as a "wrong" answer.
        let items = [
            OnKunItem(kanjiID: 1, literal: "行", onReadings: ["コウ", "ギョウ"], kunReadings: ["い"]),
            OnKunItem(kanjiID: 2, literal: "業", onReadings: ["ギョウ", "ゴウ"], kunReadings: ["わざ"]),
            OnKunItem(kanjiID: 3, literal: "学", onReadings: ["ガク"], kunReadings: ["まな"]),
            OnKunItem(kanjiID: 4, literal: "国", onReadings: ["コク"], kunReadings: ["くに"]),
            OnKunItem(kanjiID: 5, literal: "森", onReadings: ["シン"], kunReadings: ["もり"]),
            OnKunItem(kanjiID: 6, literal: "天", onReadings: ["テン"], kunReadings: ["あま"]),
        ]
        let questions = KankenQuestion.onKunQuiz(items, count: 6, language: .ko)
        let gyo = try? XCTUnwrap(questions.first { $0.kanjiID == 1 && $0.answer == "コウ" })
        if let gyo {
            XCTAssertFalse(gyo.options.contains("ギョウ"))
        }
        for question in questions {
            let item = items.first { $0.kanjiID == question.kanjiID }!
            let others = Set(item.onReadings + item.kunReadings).subtracting([question.answer])
            XCTAssertTrue(others.isDisjoint(with: question.options), question.prompt)
        }
    }

    func testHitsujunAnswersWithAnOrdinal() {
        let paths = (0..<8).map { "M\($0) 0 L\($0) 10" }
        let questions = KankenQuestion.hitsujunQuiz(
            [StrokeOrderItem(kanjiID: 9, literal: "東", paths: paths)], count: 1, language: .ja)
        let question = try? XCTUnwrap(questions.first)
        XCTAssertNotNil(question)
        XCTAssertTrue(question?.answer.hasSuffix("画目") ?? false)
        XCTAssertEqual(question?.options.count, 4)
    }

    func testYojiBlankNeverRespellsAnotherIdiom() {
        let items = [
            Yojijukugo(id: 1, yoji: "一石二鳥", reading: "いっせきにちょう", meaningJa: "a", meaningKo: "a", level: "5級"),
            Yojijukugo(id: 2, yoji: "一期一会", reading: "いちごいちえ", meaningJa: "b", meaningKo: "b", level: "5級"),
            Yojijukugo(id: 3, yoji: "十人十色", reading: "じゅうにんといろ", meaningJa: "c", meaningKo: "c", level: "5級"),
            Yojijukugo(id: 4, yoji: "四苦八苦", reading: "しくはっく", meaningJa: "d", meaningKo: "d", level: "5級"),
            Yojijukugo(id: 5, yoji: "自画自賛", reading: "じがじさん", meaningJa: "e", meaningKo: "e", level: "5級"),
            Yojijukugo(id: 6, yoji: "起死回生", reading: "きしかいせい", meaningJa: "f", meaningKo: "f", level: "5級"),
        ]
        let known = Set(items.map(\.yoji))
        let questions = KankenQuestion.yojijukugoQuiz(items, count: 6, language: .ko)
            .filter { $0.id.hasPrefix("yoji:b:") }
        XCTAssertFalse(questions.isEmpty)
        for question in questions {
            let blanked = question.prompt.split(separator: "\n").first.map(String.init) ?? ""
            for option in question.options where option != question.answer {
                XCTAssertFalse(known.contains(blanked.replacingOccurrences(of: "□", with: option)))
            }
        }
    }
}

@MainActor
final class KankenExamFeatureTests: XCTestCase {
    private func question(_ id: String, section: String = "reading") -> KankenQuestion {
        KankenQuestion(id: id, type: .reading, kanjiID: 1, prompt: "問\(id)",
                       options: ["あ", "い", "う", "え"], answer: "あ", sectionID: section)
    }

    func testMockPaperIsSatOnceAndScored() async {
        var state = KankenExamFeature.State(level: "5級")
        state.isMockExam = true
        let store = TestStore(initialState: state) { KankenExamFeature() } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 1_000)
            $0.wrongNoteStore.update = { transform in transform([]) }
        }
        store.exhaustivity = .off

        await store.send(.loaded([question("a"), question("b", section: "writing")]))
        await store.send(.chose("い"))          // wrong
        await store.send(.next)
        // No requeue on a mock paper: one question left, not two.
        XCTAssertEqual(store.state.queue.map(\.id), ["b"])
        await store.send(.chose("あ"))          // right
        await store.send(.next)

        XCTAssertTrue(store.state.isFinished)
        XCTAssertEqual(store.state.firstTryCorrect, 1)
        XCTAssertEqual(store.state.scoreRatio, 0.5)
        XCTAssertFalse(store.state.passed)     // 5級 needs 70%
        XCTAssertEqual(store.state.sectionTallies.map(\.correct), [0, 1])
    }

    func testDrillRequeuesAMissUntilCleared() async {
        var state = KankenExamFeature.State(level: "5級")
        state.activeSection = ExamType.kanken.sections(for: "5級").first
        let store = TestStore(initialState: state) { KankenExamFeature() } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 1_000)
            $0.wrongNoteStore.update = { transform in transform([]) }
        }
        store.exhaustivity = .off

        await store.send(.loaded([question("a")]))
        await store.send(.chose("い"))
        await store.send(.next)
        XCTAssertEqual(store.state.queue.map(\.id), ["a"])   // back for another go
        await store.send(.chose("あ"))
        await store.send(.next)
        XCTAssertTrue(store.state.isFinished)
        XCTAssertEqual(store.state.firstTryCorrect, 0)       // it was missed first time
    }

    func testNotebookShowsOnlyTheCurrentLevel() async {
        let notes = [
            WrongNote(question: question("n3"), savedDay: 1, level: "N3"),
            WrongNote(question: question("k2"), savedDay: 2, level: "2級"),
            WrongNote(question: question("old"), savedDay: 0),   // saved before levels
        ]
        let store = TestStore(initialState: KankenExamFeature.State(level: "2級")) {
            KankenExamFeature()
        } withDependencies: {
            $0.wrongNoteStore.load = { notes }
            $0.date.now = Date(timeIntervalSince1970: 0)
        }
        store.exhaustivity = .off

        await store.send(.onAppear(level: "2級", language: .ko))
        await store.receive(\.wrongCountLoaded) { $0.wrongCount = 2 }
        await store.send(.selectWrongNote)
        await store.receive(\.loaded)
        XCTAssertEqual(Set(store.state.queue.map(\.id)), ["k2", "old"])
    }

    func testLateLoadAfterLeavingIsIgnored() async {
        let store = TestStore(initialState: KankenExamFeature.State(level: "5級")) {
            KankenExamFeature()
        }
        store.exhaustivity = .off
        // Nothing is playing (the learner went back to the hub) — a load that
        // arrives now must not start a session.
        await store.send(.loaded([question("a")]))
        XCTAssertTrue(store.state.queue.isEmpty)
        XCTAssertFalse(store.state.started)
    }
}

final class WrongNoteScheduleTests: XCTestCase {
    private let note = WrongNote(
        question: KankenQuestion(id: "q", type: .reading, kanjiID: 1, prompt: "p",
                                 options: ["a", "b"], answer: "a"),
        savedDay: 10)

    func testClearsSpaceOutThenRetire() {
        let first = note.reviewed(correct: true, today: 10)
        XCTAssertEqual(first?.box, 1)
        XCTAssertEqual(first?.due, 13)                 // 3 days
        let second = first?.reviewed(correct: true, today: 13)
        XCTAssertEqual(second?.due, 20)                // 7 days
        XCTAssertNil(second?.reviewed(correct: true, today: 20))   // retired
    }

    func testAMissComesBackTomorrow() {
        let missed = note.reviewed(correct: true, today: 10)?.reviewed(correct: false, today: 13)
        XCTAssertEqual(missed?.box, 0)
        XCTAssertEqual(missed?.due, 14)
        XCTAssertTrue(note.isDue(on: 0))               // unscheduled = due now
    }
}

@MainActor
final class WeakSpotAndTimerTests: XCTestCase {
    func testWeakSectionsAreLowestAccuracyThenUntried() {
        var state = KankenExamFeature.State(level: "5級")
        let sections = ExamType.kanken.sections(for: "5級")
        let strong = sections[0], weak = sections[1], thin = sections[2]
        state.stats = [
            SectionStat.key(level: "5級", section: strong.id): SectionStat(attempts: 10, correct: 9),
            SectionStat.key(level: "5級", section: weak.id): SectionStat(attempts: 10, correct: 3),
            // Too few answers to judge — not "weak", but not untried either.
            SectionStat.key(level: "5級", section: thin.id): SectionStat(attempts: 2, correct: 0),
        ]
        let picked = state.weakSections.map(\.id)
        XCTAssertEqual(picked.first, weak.id)
        XCTAssertEqual(picked.count, 3)
        XCTAssertFalse(picked.contains(thin.id))
    }

    func testTimeUpCountsTheRestAsUnanswered() async {
        var state = KankenExamFeature.State(level: "5級")
        state.isMockExam = true
        let store = TestStore(initialState: state) { KankenExamFeature() } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 1_000)
        }
        store.exhaustivity = .off
        let questions = (0..<3).map {
            KankenQuestion(id: "\($0)", type: .reading, kanjiID: 1, prompt: "p",
                           options: ["a", "b"], answer: "a", sectionID: "reading")
        }
        await store.send(.loaded(questions))
        XCTAssertEqual(store.state.timeLimit, 3 * KankenExamFeature.secondsPerQuestion)
        await store.send(.timeUp)
        XCTAssertTrue(store.state.isFinished)
        XCTAssertEqual(store.state.firstTryCorrect, 0)
        XCTAssertEqual(store.state.firstTry.count, 3)
        await store.send(.exitToHub)                   // cancels the timer
    }
}

final class KankenPaperTests: XCTestCase {
    private let levels = ["10級", "9級", "8級", "7級", "6級", "5級",
                          "4級", "3級", "準2級", "2級", "準1級", "1級"]

    func testEveryPaperAddsUpToItsOfficialTotal() {
        for level in levels {
            let paper = try? XCTUnwrap(KankenPaper.official(for: level))
            XCTAssertNotNil(paper, level)
            guard let paper else { continue }
            XCTAssertEqual(paper.parts.reduce(0) { $0 + $1.maxPoints }, paper.total, level)
            XCTAssertEqual(Double(paper.pass) / Double(paper.total),
                           ExamType.kanken.passRatio(for: level), accuracy: 0.001, level)
            XCTAssertEqual(paper.minutes, ExamType.kanken.officialMinutes(for: level), level)
        }
    }

    func testEveryPartIsAnsweredByAPlayableHubSection() {
        for level in levels {
            guard let paper = KankenPaper.official(for: level) else { continue }
            let hub = Set(ExamType.kanken.sections(for: level).filter(\.available).map(\.id))
            for part in paper.parts {
                XCTAssertTrue(hub.contains(part.sectionID), "\(level) \(part.title)")
            }
        }
    }

    func testAssembleFillsEachPartOnceAndTopsUpShortOnes() {
        let paper = try! XCTUnwrap(KankenPaper.official(for: "10級"))
        func pool(_ prefix: String, _ n: Int, _ section: String) -> [KankenQuestion] {
            (0..<n).map {
                KankenQuestion(id: "\(prefix)\($0)", type: .reading, kanjiID: 1, prompt: "p",
                               options: ["a", "b"], answer: "a", sectionID: section)
            }
        }
        // Reading answers three 大問 (20 + 8 + 5); 筆順 comes up 2 short.
        let pools = [
            "reading": pool("r", 33 + 30, "reading"),
            "hitsujun": pool("h", 10, "hitsujun"),
            "okuri": pool("o", 6, "okuri"),
            "hantai": pool("t", 10, "hantai"),
            "writing": pool("w", 20 + 30, "writing"),
        ]
        let items = KankenExamFeature.assemble(paper, pools: pools)
        XCTAssertEqual(items.count, paper.questionCount)
        XCTAssertEqual(Set(items.map(\.id)).count, items.count)       // no repeats
        XCTAssertEqual(items.reduce(0) { $0 + ($1.points ?? 0) }, paper.total)
        let hitsujun = items.filter { $0.partIndex == 1 }
        XCTAssertEqual(hitsujun.count, 12)
        XCTAssertEqual(hitsujun.filter { $0.sectionID == "writing" }.count, 2)
        XCTAssertEqual(items.map { $0.partIndex ?? -1 }, items.map { $0.partIndex ?? -1 }.sorted())
    }
}

@MainActor
final class RealExamFeatureTests: XCTestCase {
    func testRealPaperScoresInPointsAndMarksOnlyAtTheEnd() async {
        var state = KankenExamFeature.State(level: "2級")
        state.isMockExam = true
        state.paper = KankenPaper.official(for: "2級")
        let store = TestStore(initialState: state) { KankenExamFeature() } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 1_000)
            $0.wrongNoteStore.update = { transform in transform([]) }
        }
        store.exhaustivity = .off
        func item(_ id: String, points: Int, part: Int) -> KankenQuestion {
            var q = KankenQuestion(id: id, type: .reading, kanjiID: 1, prompt: "p",
                                   options: ["a", "b"], answer: "a", sectionID: "reading")
            q.points = points
            q.partIndex = part
            return q
        }
        await store.send(.loaded([item("r", points: 1, part: 0), item("w", points: 2, part: 8)]))
        XCTAssertEqual(store.state.timeLimit, 60 * 60)
        await store.send(.chose("b"))            // wrong — moves straight on
        await store.receive(\.next)
        XCTAssertEqual(store.state.queue.map(\.id), ["w"])
        await store.send(.chose("a"))
        await store.receive(\.next)

        XCTAssertTrue(store.state.isFinished)
        XCTAssertEqual(store.state.earnedPoints, 2)
        XCTAssertEqual(store.state.maxPoints, 3)
        // 160/200 scaled to a 3-point sitting.
        XCTAssertEqual(store.state.passPoints, 3)
        XCTAssertFalse(store.state.passed)
        XCTAssertEqual(store.state.sectionTallies.map(\.earnedPoints), [0, 2])
        XCTAssertEqual(store.state.missedItems.map(\.id), ["r"])
        XCTAssertEqual(store.state.chosenAnswers["r"], "b")
        await store.send(.exitToHub)
        XCTAssertNil(store.state.paper)
    }
}
