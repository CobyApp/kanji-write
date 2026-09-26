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

    init(_ q: JLPTQuestion, language: AppLanguage) {
        self.id = "q:\(q.kanjiID):\(q.id)"
        self.kanjiID = q.kanjiID
        self.kind = q.kind
        self.options = q.options
        self.answer = q.options.indices.contains(q.answer) ? q.options[q.answer] : (q.options.first ?? "")
        self.explanation = Self.localized(q.explanations, language)
        // Some prompts wrap the target word in <u>…</u>. Strip the tags for
        // display and use the wrapped text as the underline target (falling back
        // to the focus column when there are no tags).
        let (cleaned, underlined) = QuizItem.parseUnderline(q.prompt)
        self.prompt = cleaned
        self.focus = underlined ?? q.focus
    }

    /// Returns the prompt with any `<u>…</u>` tags removed, and the first wrapped
    /// substring (nil if the prompt has no tags).
    static func parseUnderline(_ raw: String) -> (clean: String, target: String?) {
        guard let open = raw.range(of: "<u>"), let close = raw.range(of: "</u>"),
              open.upperBound <= close.lowerBound else {
            return (raw, nil)
        }
        let target = String(raw[open.upperBound..<close.lowerBound])
        let clean = raw.replacingOccurrences(of: "<u>", with: "")
            .replacingOccurrences(of: "</u>", with: "")
        return (clean, target.isEmpty ? nil : target)
    }

    /// The same question in the exam hub's shape, for the 오답노트.
    public var asExamQuestion: KankenQuestion {
        let type: KankenQuestionType = switch kind {
        case "reading": .reading
        case "orthography": .writing
        default: .context
        }
        return KankenQuestion(
            id: "quiz:\(id)", type: type, kanjiID: kanjiID, prompt: prompt, focus: focus,
            options: options, answer: answer, explanation: explanation,
            sectionID: kind == "orthography" ? "orthography" : kind)
    }

    /// The 해설 in the chosen language, falling back deterministically.
    static func localized(_ dict: [String: String], _ language: AppLanguage) -> String? {
        for key in [language.glossKey, "en", "ko", "ja", "zh"] {
            if let value = dict[key], !value.isEmpty { return value }
        }
        return dict.values.first { !$0.isEmpty }
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
        /// Today's planned new kanji (from the study plan) — quizzable even before
        /// they've been studied, so the quiz is never empty on a fresh day.
        public var plannedIDs: [Int]
        public var today = 0
        public var records: [String: QuizRecord] = [:]

        public var queue: [QuizItem] = []          // remaining this session (mastery loop)
        public var sessionItems: [QuizItem] = []   // the full set this session, for 다시 풀기
        public var totalItems = 0                  // unique items this session
        public var mastered = 0                    // items cleared (first correct)
        public var missed: Set<String> = []        // items answered wrong ≥ once
        public var firstAttempt: [String: Bool] = [:]
        public var answeredOnce: Set<String> = []
        public var chosen: String?
        public var started = false
        public var isLoading = false
        // True during a 다시 풀기 replay: the mastery loop still runs, but first
        // attempts don't reschedule/persist SRS (scheduling happened on pass 1).
        public var isReplay = false
        /// Bumped on every attempt so the view resets its answer input, even
        /// when a missed question comes straight back.
        public var attempt = 0

        public init(level: String, plannedIDs: [Int] = [], language: AppLanguage = .ko) {
            self.level = level
            self.plannedIDs = plannedIDs
            self.language = language
        }

        public var current: QuizItem? { queue.first }
        // Finished only when there was actually something to solve — an empty
        // session (nothing due/new) shows the "nothing to review" card instead.
        public var isFinished: Bool { started && totalItems > 0 && queue.isEmpty }
        public var answered: Bool { chosen != nil }
        public var isCorrect: Bool { chosen == current?.answer }
        public var isRetry: Bool { current.map { missed.contains($0.id) } ?? false }
    }

    public enum Action: Equatable {
        case onAppear(language: AppLanguage)
        case loaded(questions: [JLPTQuestion], studied: [Int], records: [QuizRecord],
                    today: Int, order: [Int: Int])
        case chose(String)
        case next
        case restart
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.quizStore) var quizStore
    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.wrongNoteStore) var wrongNoteStore
    @Dependency(\.studyLogStore) var studyLogStore
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(language):
                state.language = language
                return load(state: &state)

            case .restart:
                // 다시 풀기 replays the same set as a fresh practice pass (no
                // re-query, so it never collapses to 0/0 once items are scheduled).
                state.queue = state.sessionItems
                state.mastered = 0
                state.missed = []
                state.firstAttempt = [:]
                state.answeredOnce = []
                state.chosen = nil
                state.started = true
                state.isReplay = true
                state.attempt += 1
                return .none

            case let .loaded(questions, studied, records, today, order):
                state.isLoading = false
                state.today = today
                state.records = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let studiedSet = Set(studied)
                let lang = state.language
                var items: [QuizItem] = []
                var seen = Set<String>()
                var newPerKanji: [Int: Int] = [:]
                for q in questions {
                    let item = QuizItem(q, language: lang)
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
                // Serve questions in the order the kanji were learned (study order:
                // JLPT level → strokes → id), grouping a kanji's questions together.
                items.sort { a, b in
                    let ra = order[a.kanjiID] ?? Int.max
                    let rb = order[b.kanjiID] ?? Int.max
                    if ra != rb { return ra < rb }
                    return a.id < b.id
                }
                state.queue = items
                state.sessionItems = items
                state.totalItems = items.count
                state.isReplay = false
                state.mastered = 0
                state.missed = []
                state.firstAttempt = [:]
                state.answeredOnce = []
                state.chosen = nil
                state.started = true
                state.attempt += 1
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
                // away so review survives quitting mid-session. Replays don't
                // reschedule (scheduling already happened on the first pass).
                if state.answeredOnce.insert(item.id).inserted {
                    state.firstAttempt[item.id] = correct
                    if !state.isReplay {
                        let s = QuizSRS.schedule(box: state.records[item.id]?.box,
                                                 correct: correct, today: state.today)
                        state.records[item.id] = QuizRecord(id: item.id, box: s.box, due: s.due)
                        let all = Array(state.records.values)
                        let today = state.today
                        save = .run { _ in
                            await quizStore.save(all)
                            await studyLogStore.record(today, correct)
                        }
                        // A first miss joins the 오답노트, the same notebook the
                        // exam hub reviews — the daily quiz used to forget it.
                        if !correct {
                            let note = WrongNote(question: item.asExamQuestion, savedDay: state.today,
                                                 level: state.level)
                            save = .merge(save, .run { _ in
                                _ = await wrongNoteStore.update { notes in
                                    notes.filter { $0.id != note.id } + [note]
                                }
                            })
                        }
                    }
                }
                state.queue.removeFirst()
                if correct {
                    state.mastered += 1
                } else {
                    state.missed.insert(item.id)
                    state.queue.append(item)   // retry later this session
                }
                state.chosen = nil
                state.attempt += 1
                return save
            }
        }
    }

    private func load(state: inout State) -> Effect<Action> {
        state.isLoading = true
        state.started = false
        let planned = state.plannedIDs
        return .run { send in
            let today = Int(date.now.timeIntervalSince1970 / 86_400)
            // Read the kanji SRS fresh from disk (a study session may have just
            // written it) — kanji studied today OR due for review are the new
            // material. Today's *planned* kanji are folded in too so the quiz
            // works even before today's study is done.
            let reviewRecords = await reviewStore.loadRecords()
            let studiedRecords = reviewRecords
                .filter { $0.lastReviewedDay == today || $0.due <= today }
                .map(\.kanjiID)
            let studied = Array(Set(studiedRecords).union(planned))
            let records = await quizStore.load()
            // Kanji referenced by any due quiz record → re-fetch their questions so
            // the specific due question can be resurfaced ("q:<kanjiID>:<qid>").
            var dueKanji = Set<Int>()
            for record in records where record.due <= today {
                let parts = record.id.split(separator: ":")
                if parts.count == 3, parts[0] == "q", let kid = Int(parts[1]) { dueKanji.insert(kid) }
            }
            let contextSet = Set(studied).union(dueKanji)
            let contextKanji = Array(contextSet)
            // Pull every question for the context kanji; the reducer filters to
            // new-or-due and caps new questions per kanji.
            let questions = (try? await dictionaryClient.jlptQuestions(contextKanji, 99)) ?? []
            // Rank each context kanji by its position in the study curriculum so
            // the reducer can serve questions in learned order.
            let allKanji = (try? await dictionaryClient.allKanji()) ?? []
            var order: [Int: Int] = [:]
            for (index, kanji) in studyOrder(allKanji, exam: ExamType.current).enumerated() where contextSet.contains(kanji.id) {
                order[kanji.id] = index
            }
            await send(.loaded(questions: questions, studied: studied, records: records,
                               today: today, order: order))
        }
    }
}
