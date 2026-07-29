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
        /// A full paper: every playable 大問 of this level, in paper order.
        public var isMockExam = false
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
        public var isPlaying: Bool { activeSection != nil || isWrongNote || isMockExam }
        public var current: KankenQuestion? { queue.first }
        public var isFinished: Bool { started && total > 0 && queue.isEmpty }
        public var answered: Bool { chosen != nil }
        public var isCorrect: Bool { chosen == current?.answer }
        /// Section title shown in the session header.
        public var sessionTitle: String {
            if isWrongNote { return "오답노트" }
            if isMockExam { return L.mockExam[language] }
            return activeSection.map { "\($0.numeral)　\($0.jaTitle)" } ?? ""
        }
    }

    public enum Action: Equatable {
        case onAppear(level: String, language: AppLanguage)
        case wrongCountLoaded(Int)
        case selectSection(ExamSection)
        case selectWrongNote
        case selectMockExam(perSection: Int)
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

            case let .selectMockExam(perSection):
                state.isMockExam = true
                state.activeSection = nil
                state.isWrongNote = false
                state.isLoading = true
                state.started = false
                let level = state.level
                let language = state.language
                let unit = L.strokesUnit[language]
                // Paper order, not shuffled: a 漢検 sitting works through its
                // 大問 one after another, and keeping that makes the practice
                // feel like the exam rather than a shuffled quiz.
                let sections = ExamType.current.sections(for: level).filter(\.available)
                return .run { send in
                    var all: [KankenQuestion] = []
                    for section in sections {
                        let built = try? await questions(
                            for: section, level: level, language: language,
                            unit: unit, perSection: perSection)
                        all.append(contentsOf: built ?? [])
                    }
                    await send(.loaded(all))
                }

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
                state.isMockExam = false
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
            await send(.loaded(
                try await questions(for: section, level: level, language: language,
                                    unit: unit, perSection: 20)))
        }
    }

    /// Every question for one 大問, at the level given. Shared by a single
    /// section and by the mock paper, which needs all of them.
    private func questions(for section: ExamSection, level: String,
                           language: AppLanguage, unit: String,
                           perSection: Int) async throws -> [KankenQuestion] {
        let built: [KankenQuestion]
        if let kind = section.kind {
            let bank = (try? await dictionaryClient.examQuestions(level, kind, perSection)) ?? []
            // 用法 borrows 対義語・類義語's rendering (a word prompt, text options),
            // so it has to carry its own instruction or it would ask the reader
            // for a synonym.
            let label = kind == "youhou" ? L.quizUsage[language] : nil
            built = bank.map {
                KankenQuestion.from($0, type: section.renderType, language: language, label: label)
            }
        } else if section.renderType == .strokes {
            let items = (try? await dictionaryClient.examStrokeItems(level, 80)) ?? []
            built = KankenQuestion.strokeQuiz(items, count: perSection, unit: unit)
        } else if section.renderType == .yojijukugo {
            let items = (try? await dictionaryClient.examYojijukugo(level, 60)) ?? []
            built = KankenQuestion.yojijukugoQuiz(items, count: perSection, language: language)
        } else if section.renderType == .okurigana {
            let items = (try? await dictionaryClient.examOkurigana(level, 120)) ?? []
            built = KankenQuestion.okuriganaQuiz(items, count: perSection)
        } else if section.renderType == .taigirui {
            // 対義語-only sections (lower 級) filter to antonyms; 対義語・類義語 uses both.
            let relationOnly = section.id == "taigi" ? "対義" : nil
            let items = (try? await dictionaryClient.examTaigirui(level, relationOnly, 40)) ?? []
            built = KankenQuestion.taigiruiQuiz(items, count: perSection)
        } else if section.renderType == .hitsujun {
            let items = (try? await dictionaryClient.examStrokeOrderItems(level, 60)) ?? []
            built = KankenQuestion.hitsujunQuiz(items, count: perSection, unit: unit)
        } else if section.renderType == .onkun {
            let items = (try? await dictionaryClient.examOnKun(level, 40)) ?? []
            built = KankenQuestion.onKunQuiz(items, count: perSection)
        } else {
            let items = (try? await dictionaryClient.examRadicalItems(level, 80)) ?? []
            built = KankenQuestion.radicalQuiz(items, count: perSection)
        }
        return built.filter { $0.options.count >= 2 }
    }
}

extension KankenQuestion {
    /// Adapts a pre-authored `JLPTQuestion` into a 漢検 section question.
    static func from(_ q: JLPTQuestion, type: KankenQuestionType, language: AppLanguage,
                     label: String? = nil) -> KankenQuestion {
        let (clean, underlined) = JLPTQuestion.parseUnderline(q.prompt)
        let explanation = localizedExplanation(q.explanations, language)
        return KankenQuestion(
            id: "\(type.rawValue):\(q.kanjiID):\(q.id)", type: type, kanjiID: q.kanjiID,
            prompt: clean, focus: underlined ?? q.focus, options: q.options,
            answer: q.answerText, explanation: explanation, label: label)
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

    /// Builds 筆順 questions: the glyph is drawn with one stroke marked, and the
    /// answer is where that stroke falls in writing order. The strokes travel on
    /// the question so a 오답노트 entry still renders without another query.
    ///
    /// The marked stroke is never the first or the last: those are guessable from
    /// the shape alone, which tests recognition rather than stroke order.
    static func hitsujunQuiz(_ items: [StrokeOrderItem], count: Int,
                             unit: String) -> [KankenQuestion] {
        var out: [KankenQuestion] = []
        for (index, item) in items.enumerated() where out.count < count {
            let total = item.paths.count
            guard total >= 4 else { continue }
            var rng = SeededRNG(seed: UInt64(item.kanjiID &+ index &+ 11))
            let interior = Array(1..<(total - 1))
            guard let marked = interior.shuffled(using: &rng).first else { continue }
            let answer = "\(marked + 1)\(unit)"
            let others = (1...total).filter { $0 != marked + 1 }.map { "\($0)\(unit)" }
            let distractors = others.shuffled(using: &rng).prefix(3)
            guard distractors.count == 3 else { continue }
            let options = (Array(distractors) + [answer]).shuffled(using: &rng)
            out.append(KankenQuestion(
                id: "\(KankenQuestionType.hitsujun.rawValue):\(item.kanjiID):\(marked)",
                type: .hitsujun, kanjiID: item.kanjiID, prompt: item.literal,
                focus: nil, options: options, answer: answer, explanation: nil,
                strokePaths: item.paths, markedStroke: marked))
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

    /// Builds 送りがな questions: the word is shown in katakana; pick where the
    /// kanji ends and the okurigana begins. Distractors shift the okurigana
    /// boundary (the classic 送りがな trap), keeping the same kanji stem.
    static func okuriganaQuiz(_ items: [WordEntry], count: Int) -> [KankenQuestion] {
        // Endings that mark a conjugating word (verb う-row / i-adj / na-adj か…).
        let okuriEndings: Set<Character> = ["う", "く", "ぐ", "す", "つ", "ぬ", "ぶ", "む", "る", "い", "か"]
        var out: [KankenQuestion] = []
        var used = Set<String>()
        func isKanji(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
        }
        func isHiragana(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { (0x3040...0x309F).contains($0.value) }
        }
        for item in items where out.count < count {
            let surface = item.surface
            guard let first = surface.first, isKanji(first) else { continue }
            let okurigana = String(surface.dropFirst())
            // Single-kanji stem only: everything after the kanji must be hiragana
            // (rejects compounds like 飲み干す / 引け値 that the SQL GLOB lets through).
            guard !okurigana.isEmpty, okurigana.allSatisfy(isHiragana) else { continue }
            let kanjiPart = String(first)
            guard let last = okurigana.last, okuriEndings.contains(last), !used.contains(surface) else { continue }
            let readingChars = Array(item.reading)
            let okuriLen = okurigana.count
            let kanjiKanaLen = readingChars.count - okuriLen
            guard kanjiKanaLen >= 1, !readingChars.isEmpty else { continue }
            // Boundary-shift distractors: same kanji, different okurigana length.
            var distractors: [String] = []
            for delta in [1, 2, -1] {
                let newLen = okuriLen + delta
                guard newLen >= 0, newLen <= readingChars.count - 1 else { continue }
                let variant = kanjiPart + String(readingChars.suffix(newLen))
                if variant != surface, !distractors.contains(variant) { distractors.append(variant) }
            }
            guard distractors.count >= 2 else { continue }
            let kata = item.reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? item.reading
            var rng = SeededRNG(seed: UInt64(item.id &+ 11))
            let options = (Array(distractors.prefix(3)) + [surface]).shuffled(using: &rng)
            used.insert(surface)
            out.append(KankenQuestion(
                id: "okuri:\(item.id)", type: .okurigana, kanjiID: item.id,
                prompt: kata, focus: nil, options: options, answer: surface,
                explanation: item.meaningKo, label: "送りがな"))
        }
        return out
    }

    /// Builds 対義語・類義語 questions: the prompt word is shown; pick its antonym or
    /// synonym from four real words (distractors are other answers in the pool).
    static func taigiruiQuiz(_ items: [TaigiruiPair], count: Int) -> [KankenQuestion] {
        guard items.count >= 4 else { return [] }
        let pool = items.map(\.answer)
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.id &+ index &+ 5))
            let options = quizOptions(answer: item.answer, pool: pool, rng: &rng)
            guard options.count >= 2 else { continue }
            out.append(KankenQuestion(
                id: "taigi:\(item.id)", type: .taigirui, kanjiID: item.id,
                prompt: item.word, focus: nil, options: options, answer: item.answer,
                explanation: "\(item.answer)（\(item.answerReading)）",
                label: item.relation == "対義" ? "対義語" : "類義語"))
        }
        return out
    }

    /// Builds 音読み・訓読み questions: show the kanji, pick one of its 音読み (or
    /// 訓読み) readings. Distractors are same-type readings (katakana for 音 /
    /// hiragana for 訓) from other kanji, so the script alone doesn't give it away.
    static func onKunQuiz(_ items: [OnKunItem], count: Int) -> [KankenQuestion] {
        let onPool = items.flatMap(\.onReadings)
        let kunPool = items.flatMap(\.kunReadings)
        guard onPool.count >= 4 || kunPool.count >= 4 else { return [] }
        var out: [KankenQuestion] = []
        for (index, item) in items.enumerated() where out.count < count {
            let canOn = !item.onReadings.isEmpty && onPool.count >= 4
            let canKun = !item.kunReadings.isEmpty && kunPool.count >= 4
            let askOn: Bool
            if index % 2 == 0, canOn { askOn = true }
            else if index % 2 == 1, canKun { askOn = false }
            else if canOn { askOn = true }
            else if canKun { askOn = false }
            else { continue }
            var rng = SeededRNG(seed: UInt64(item.kanjiID &+ index &+ 13))
            let answer = askOn ? item.onReadings[0] : item.kunReadings[0]
            let options = quizOptions(answer: answer, pool: askOn ? onPool : kunPool, rng: &rng)
            guard options.count >= 2 else { continue }
            out.append(KankenQuestion(
                id: "onkun:\(askOn ? "o" : "k"):\(item.kanjiID)", type: .onkun, kanjiID: item.kanjiID,
                prompt: item.literal, focus: nil, options: options, answer: answer,
                explanation: nil, label: askOn ? "音読み" : "訓読み"))
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
