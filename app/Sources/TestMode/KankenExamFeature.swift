import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

/// The exam-question hub: real-exam-shaped practice organized by the exam's 大問
/// sections (漢検: 読み / 部首 / 書き取り — JLPT: 漢字読み / 表記 / 文脈規定). From the
/// hub the learner picks a section to practice, or opens the 오답노트 (wrong-answer
/// notebook). A section runs a mastery loop — wrong answers requeue until cleared,
/// and a first miss is saved to the 오답노트; clearing a note in 오답노트 mode
/// removes it. Questions are scoped to the current level.
@Reducer
public struct KankenExamFeature {
    @ObservableState
    public struct State: Equatable {
        public var level: String
        public var language: AppLanguage
        /// Count of saved 오답노트 entries (badge on the hub).
        public var wrongCount = 0
        public var today = 0

        // Session state — nil `activeSection` and not `isWrongNote` means the hub.
        public var activeSection: ExamSection?
        public var isWrongNote = false
        public var queue: [KankenQuestion] = []
        public var sessionItems: [KankenQuestion] = []
        public var total = 0
        public var mastered = 0
        public var missed: Set<String> = []
        public var chosen: String?
        public var isLoading = false
        public var started = false

        public init(level: String, language: AppLanguage = .ko) {
            self.level = level
            self.language = language
        }

        /// True while a section / 오답노트 session is running (vs. the hub).
        public var isPlaying: Bool { activeSection != nil || isWrongNote }
        public var current: KankenQuestion? { queue.first }
        public var isFinished: Bool { started && total > 0 && queue.isEmpty }
        public var answered: Bool { chosen != nil }
        public var isCorrect: Bool { chosen == current?.answer }
        /// Section title shown in the session header.
        public var sessionTitle: String {
            if isWrongNote { return "오답노트" }
            return activeSection.map { "\($0.numeral)　\($0.jaTitle)" } ?? ""
        }
    }

    public enum Action: Equatable {
        case onAppear(level: String, language: AppLanguage)
        case wrongCountLoaded(Int)
        case selectSection(ExamSection)
        case selectWrongNote
        case loaded([KankenQuestion])
        case chose(String)
        case next
        case restart
        case exitToHub
        case closeTapped   // delegate → parent dismisses the session
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.wrongNoteStore) var wrongNoteStore
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(level, language):
                state.level = level
                state.language = language
                state.today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    let notes = await wrongNoteStore.load()
                    await send(.wrongCountLoaded(notes.count))
                }

            case let .wrongCountLoaded(count):
                state.wrongCount = count
                return .none

            case let .selectSection(section):
                state.activeSection = section
                state.isWrongNote = false
                return loadSection(state: &state, section: section)

            case .selectWrongNote:
                state.activeSection = nil
                state.isWrongNote = true
                state.isLoading = true
                state.started = false
                return .run { send in
                    let notes = await wrongNoteStore.load()
                        .sorted { $0.savedDay > $1.savedDay }
                    await send(.loaded(notes.map(\.question)))
                }

            case let .loaded(questions):
                state.isLoading = false
                state.queue = questions
                state.sessionItems = questions
                state.total = questions.count
                state.mastered = 0
                state.missed = []
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
                state.queue.removeFirst()
                state.chosen = nil
                if correct {
                    state.mastered += 1
                    guard state.isWrongNote else { return .none }
                    // Clearing a note in 오답노트 mode removes it from the notebook.
                    let id = item.id
                    return .run { send in
                        let remaining = await wrongNoteStore.load().filter { $0.id != id }
                        await wrongNoteStore.save(remaining)
                        await send(.wrongCountLoaded(remaining.count))
                    }
                }
                state.queue.append(item)  // retry later this session
                // A first miss in a section is saved to the 오답노트 (once).
                guard !state.isWrongNote, state.missed.insert(item.id).inserted else { return .none }
                let note = WrongNote(question: item, savedDay: state.today)
                return .run { send in
                    var notes = await wrongNoteStore.load().filter { $0.id != note.id }
                    notes.append(note)
                    await wrongNoteStore.save(notes)
                    await send(.wrongCountLoaded(notes.count))
                }

            case .restart:
                state.queue = state.sessionItems
                state.mastered = 0
                state.missed = []
                state.chosen = nil
                state.started = true
                return .none

            case .exitToHub:
                state.activeSection = nil
                state.isWrongNote = false
                state.queue = []
                state.sessionItems = []
                state.total = 0
                state.mastered = 0
                state.missed = []
                state.chosen = nil
                state.started = false
                return .none

            case .closeTapped:
                return .none  // handled by the parent (dismiss)
            }
        }
    }

    /// Loads and builds a section's questions from real data. A section with a
    /// bank `kind` pulls pre-authored questions; one without (`kind == nil`) is the
    /// radical generator.
    private func loadSection(state: inout State, section: ExamSection) -> Effect<Action> {
        state.isLoading = true
        state.started = false
        let level = state.level
        let language = state.language
        let unit = L.strokesUnit[language]
        return .run { send in
            let questions: [KankenQuestion]
            if let kind = section.kind {
                let bank = (try? await dictionaryClient.examQuestions(level, kind, 20)) ?? []
                questions = bank.map { KankenQuestion.from($0, type: section.renderType, language: language) }
            } else if section.renderType == .strokes {
                let items = (try? await dictionaryClient.examStrokeItems(level, 80)) ?? []
                questions = KankenQuestion.strokeQuiz(items, count: 15, unit: unit)
            } else if section.renderType == .yojijukugo {
                let items = (try? await dictionaryClient.examYojijukugo(level, 60)) ?? []
                questions = KankenQuestion.yojijukugoQuiz(items, count: 15, language: language)
            } else {
                let items = (try? await dictionaryClient.examRadicalItems(level, 80)) ?? []
                questions = KankenQuestion.radicalQuiz(items, count: 15)
            }
            await send(.loaded(questions.filter { $0.options.count >= 2 }))
        }
    }
}

extension KankenQuestion {
    /// Adapts a pre-authored `JLPTQuestion` into a 漢検 section question.
    static func from(_ q: JLPTQuestion, type: KankenQuestionType, language: AppLanguage) -> KankenQuestion {
        let (clean, underlined) = JLPTQuestion.parseUnderline(q.prompt)
        let explanation = localizedExplanation(q.explanations, language)
        return KankenQuestion(
            id: "\(type.rawValue):\(q.kanjiID):\(q.id)", type: type, kanjiID: q.kanjiID,
            prompt: clean, focus: underlined ?? q.focus, options: q.options,
            answer: q.answerText, explanation: explanation)
    }

    /// Builds 部首 questions: show the kanji, pick its radical from four choices.
    /// Distractors are other real radicals drawn from the same 級 pool.
    static func radicalQuiz(_ items: [RadicalItem], count: Int) -> [KankenQuestion] {
        let pool = Array(Set(items.map(\.radical)))
        guard pool.count >= 4 else { return [] }
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.kanjiID &+ index &+ 1))
            let distractors = pool.filter { $0 != item.radical }.shuffled(using: &rng).prefix(3)
            guard distractors.count == 3 else { continue }
            let options = (Array(distractors) + [item.radical]).shuffled(using: &rng)
            out.append(KankenQuestion(
                id: "\(KankenQuestionType.radical.rawValue):\(item.kanjiID):r", type: .radical,
                kanjiID: item.kanjiID, prompt: item.literal, focus: nil,
                options: options, answer: item.radical, explanation: nil))
        }
        return out
    }

    /// Builds 画数 questions: show the kanji, pick its total stroke count from four
    /// choices. Distractors are nearby counts (±4) so the choice is non-trivial.
    static func strokeQuiz(_ items: [StrokeItem], count: Int, unit: String) -> [KankenQuestion] {
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.kanjiID &+ index &+ 7))
            let answer = "\(item.strokeCount)\(unit)"
            let nearby = (max(1, item.strokeCount - 4)...(item.strokeCount + 4))
                .filter { $0 != item.strokeCount }.map { "\($0)\(unit)" }
            let distractors = nearby.shuffled(using: &rng).prefix(3)
            guard distractors.count == 3 else { continue }
            let options = (Array(distractors) + [answer]).shuffled(using: &rng)
            out.append(KankenQuestion(
                id: "\(KankenQuestionType.strokes.rawValue):\(item.kanjiID):s", type: .strokes,
                kanjiID: item.kanjiID, prompt: item.literal, focus: nil,
                options: options, answer: answer, explanation: nil))
        }
        return out
    }

    /// Builds 四字熟語 questions, alternating two exam-authentic facets per idiom:
    /// its reading (options are readings) and its meaning (options are meanings).
    /// The idiom is shown; distractors are drawn from the other idioms in the pool.
    static func yojijukugoQuiz(_ items: [Yojijukugo], count: Int, language: AppLanguage) -> [KankenQuestion] {
        guard items.count >= 4 else { return [] }
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.id &+ index &+ 3))
            let askReading = index % 2 == 0
            if askReading {
                let pool = items.map(\.reading)
                let options = quizOptions(answer: item.reading, pool: pool, rng: &rng)
                guard options.count >= 2 else { continue }
                out.append(KankenQuestion(
                    id: "yoji:r:\(item.id)", type: .yojijukugo, kanjiID: item.id,
                    prompt: item.yoji, focus: nil, options: options, answer: item.reading,
                    explanation: item.meaning(language), label: "読み"))
            } else if let meaning = item.meaning(language), !meaning.isEmpty {
                let pool = items.compactMap { $0.meaning(language) }
                let options = quizOptions(answer: meaning, pool: pool, rng: &rng)
                guard options.count >= 2 else { continue }
                out.append(KankenQuestion(
                    id: "yoji:m:\(item.id)", type: .yojijukugo, kanjiID: item.id,
                    prompt: item.yoji, focus: nil, options: options, answer: meaning,
                    explanation: item.reading, label: "意味"))
            }
        }
        return out
    }

    /// The answer plus up to 3 distinct distractors from `pool`, seeded-shuffled.
    private static func quizOptions(answer: String, pool: [String], rng: inout SeededRNG) -> [String] {
        var distractors = Array(Set(pool.filter { $0 != answer && !$0.isEmpty })).sorted()
        distractors.shuffle(using: &rng)
        let options = (Array(distractors.prefix(3)) + [answer]).shuffled(using: &rng)
        return options
    }

    private static func localizedExplanation(_ dict: [String: String], _ language: AppLanguage) -> String? {
        for key in [language.glossKey, "ko", "ja", "en", "zh"] {
            if let value = dict[key], !value.isEmpty { return value }
        }
        return dict.values.first { !$0.isEmpty }
    }
}

/// A deterministic RNG so a section's options keep a stable order across the many
/// times SwiftUI re-evaluates the view (no flicker / reshuffle).
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
