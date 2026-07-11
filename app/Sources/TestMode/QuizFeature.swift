import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// One ready-to-show question, adapted from a pre-authored `JLPTQuestion`. The
/// `id` embeds the kanji so a due review question can be re-fetched by its kanji.
public struct QuizItem: Equatable, Identifiable, Sendable {
    public let id: String        // "q:<kanjiID>:<questionID>" — stable for SRS
    public let kanjiID: Int
    public let kind: String      // "reading" | "orthography" | "context"
    public let prompt: String
    public let options: [String]
    public let answer: String    // the correct option's text
    public let explanation: String?
    public let focus: String?    // substring of prompt to underline (target word)

    init(_ q: JLPTQuestion) {
        self.id = "q:\(q.kanjiID):\(q.id)"
        self.kanjiID = q.kanjiID
        self.kind = q.kind
        self.prompt = q.prompt
        self.options = q.options
        self.answer = q.options.indices.contains(q.answer) ? q.options[q.answer] : (q.options.first ?? "")
        self.explanation = q.explanation
        self.focus = q.focus
    }
}

/// A learn-what-you-studied quiz built from the offline JLPT question bank. It
/// serves questions for today's studied kanji (new material) woven together with
/// any questions whose spaced-repetition review is due. Wrong answers requeue
/// until every item is cleared (mastery loop), and each item's first-try result
/// schedules its next appearance (Leitner: 1 · 3 · 7 · 14 · 30 · 60 days).
@Reducer
public struct QuizFeature {
    @ObservableState
    public struct State: Equatable {
        public var level: String
        public var language: AppLanguage
        public var today = 0
        public var records: [String: QuizRecord] = [:]

        public var queue: [QuizItem] = []          // remaining this session (mastery loop)
        public var totalItems = 0                  // unique items this session
        public var mastered = 0                    // items cleared (first correct)
        public var missed: Set<String> = []        // items answered wrong ≥ once
        public var firstAttempt: [String: Bool] = [:]
        public var answeredOnce: Set<String> = []
        public var chosen: String?
        public var started = false
        public var isLoading = false

        public init(level: String, language: AppLanguage = .ko) {
            self.level = level
            self.language = language
        }

        public var current: QuizItem? { queue.first }
        public var isFinished: Bool { started && queue.isEmpty }
        public var answered: Bool { chosen != nil }
        public var isCorrect: Bool { chosen == current?.answer }
        public var isRetry: Bool { current.map { missed.contains($0.id) } ?? false }
    }

    public enum Action: Equatable {
        case onAppear(language: AppLanguage)
        case loaded(questions: [JLPTQuestion], studied: [Int], records: [QuizRecord], today: Int)
        case chose(String)
        case next
        case restart
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.quizStore) var quizStore
    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.date) var date
    @Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(language):
                state.language = language
                return load(state: &state)

            case .restart:
                return load(state: &state)

            case let .loaded(questions, studied, records, today):
                state.isLoading = false
                state.today = today
                state.records = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let studiedSet = Set(studied)
                var items: [QuizItem] = []
                withRandomNumberGenerator { rng in
                    var seen = Set<String>()
                    var newPerKanji: [Int: Int] = [:]
                    for q in questions {
                        let item = QuizItem(q)
                        guard item.options.count >= 2, seen.insert(item.id).inserted else { continue }
                        if let record = state.records[item.id] {
                            // Already scheduled — resurface only when review is due.
                            if record.due <= today { items.append(item) }
                        } else if studiedSet.contains(q.kanjiID) {
                            // New question — at most 2 per today's studied kanji.
                            let count = newPerKanji[q.kanjiID, default: 0]
                            if count < 2 { newPerKanji[q.kanjiID] = count + 1; items.append(item) }
                        }
                    }
                    items.shuffle(using: &rng)
                }
                state.queue = items
                state.totalItems = items.count
                state.mastered = 0
                state.missed = []
                state.firstAttempt = [:]
                state.answeredOnce = []
                state.chosen = nil
                state.started = true
                return .none

            case let .chose(option):
                guard state.chosen == nil else { return .none }
                state.chosen = option
                return .none

            case .next:
                guard let item = state.queue.first else { return .none }
                let correct = state.chosen == item.answer
                var save: Effect<Action> = .none
                // First attempt drives spaced repetition — schedule + persist right
                // away so review survives quitting mid-session.
                if state.answeredOnce.insert(item.id).inserted {
                    state.firstAttempt[item.id] = correct
                    let s = QuizSRS.schedule(box: state.records[item.id]?.box,
                                             correct: correct, today: state.today)
                    state.records[item.id] = QuizRecord(id: item.id, box: s.box, due: s.due)
                    let all = Array(state.records.values)
                    save = .run { _ in await quizStore.save(all) }
                }
                state.queue.removeFirst()
                if correct {
                    state.mastered += 1
                } else {
                    state.missed.insert(item.id)
                    state.queue.append(item)   // retry later this session
                }
                state.chosen = nil
                return save
            }
        }
    }

    private func load(state: inout State) -> Effect<Action> {
        state.isLoading = true
        state.started = false
        return .run { send in
            let today = Int(date.now.timeIntervalSince1970 / 86_400)
            // Read the kanji SRS fresh from disk (a study session may have just
            // written it) — kanji studied today OR due for review are the new
            // material; review questions are woven in from the quiz SRS below.
            let reviewRecords = await reviewStore.loadRecords()
            let studied = reviewRecords
                .filter { $0.lastReviewedDay == today || $0.due <= today }
                .map(\.kanjiID)
            let records = await quizStore.load()
            // Kanji referenced by any due quiz record → re-fetch their questions so
            // the specific due question can be resurfaced ("q:<kanjiID>:<qid>").
            var dueKanji = Set<Int>()
            for record in records where record.due <= today {
                let parts = record.id.split(separator: ":")
                if parts.count == 3, parts[0] == "q", let kid = Int(parts[1]) { dueKanji.insert(kid) }
            }
            let contextKanji = Array(Set(studied).union(dueKanji))
            // Pull every question for the context kanji; the reducer filters to
            // new-or-due and caps new questions per kanji.
            let questions = (try? await dictionaryClient.jlptQuestions(contextKanji, 99)) ?? []
            await send(.loaded(questions: questions, studied: studied, records: records, today: today))
        }
    }
}
