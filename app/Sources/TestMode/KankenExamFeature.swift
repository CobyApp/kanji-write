import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

/// The exam-question hub: real-exam-shaped practice organized by the exam's 大問
/// sections. From the hub the learner picks a section to drill, sits a mock
/// paper, or opens the 오답노트 (wrong-answer notebook).
///
/// * A section drill is a mastery loop — wrong answers requeue until cleared.
/// * A mock paper is sat once through, like the real thing, and scored against
///   the level's pass line, per 大問.
/// * Every first miss is saved to the 오답노트 under the current level; clearing
///   a note in 오답노트 mode removes it.
@Reducer
public struct KankenExamFeature {
    @ObservableState
    public struct State: Equatable {
        public var level: String
        public var language: AppLanguage
        /// Count of saved 오답노트 entries at this level (badge on the hub).
        public var wrongCount = 0
        /// Of those, how many are due for review today.
        public var wrongDue = 0
        public var today = 0
        /// First-try accuracy per section, keyed by `SectionStat.key`.
        public var stats: [String: SectionStat] = [:]

        // Session state — nil `activeSection` and not `isWrongNote` means the hub.
        public var activeSection: ExamSection?
        public var isWrongNote = false
        /// A full paper: every playable 大問 of this level, in paper order.
        public var isMockExam = false
        /// A drill over the learner's weakest sections, mixed together.
        public var isWeakMix = false
        /// Mock papers are timed: seconds allowed for the whole paper.
        public var timeLimit: Int?
        public var queue: [KankenQuestion] = []
        public var sessionItems: [KankenQuestion] = []
        public var total = 0
        public var mastered = 0
        public var missed: Set<String> = []
        public var chosen: String?
        public var isLoading = false
        public var started = false
        /// Whether each question was answered right the first time it came up.
        /// A drill requeues misses until they are cleared, so this — not
        /// `mastered` — is what the result reports.
        public var firstTry: [String: Bool] = [:]
        /// 大問 titles by section id, for the mock paper's breakdown.
        public var sectionTitles: [String: String] = [:]
        public var startedAt: Date?
        public var finishedAt: Date?
        /// Bumped on every new attempt, including a missed question that comes
        /// straight back (same id) — the view resets its answer input on it.
        public var attempt = 0

        public init(level: String, language: AppLanguage = .ko) {
            self.level = level
            self.language = language
        }

        /// True while a section / 오답노트 session is running (vs. the hub).
        public var isPlaying: Bool { activeSection != nil || isWrongNote || isMockExam || isWeakMix }
        public var current: KankenQuestion? { queue.first }
        public var isFinished: Bool { started && total > 0 && queue.isEmpty }
        public var answered: Bool { chosen != nil }
        public var isCorrect: Bool { chosen == current?.answer }
        /// Section title shown in the session header.
        public var sessionTitle: String {
            if isWrongNote { return L.wrongNote[language] }
            if isMockExam { return L.mockExam[language] }
            if isWeakMix { return L.weakMix[language] }
            return activeSection.map { "\($0.numeral)　\($0.jaTitle)" } ?? ""
        }
        /// The number shown against `total` in the header: questions answered on
        /// a mock paper (no retries there), questions cleared in a drill.
        public var progressCount: Int { isMockExam ? total - queue.count : mastered }

        public var firstTryCorrect: Int { firstTry.values.filter { $0 }.count }

        public func stat(for section: ExamSection) -> SectionStat? {
            stats[SectionStat.key(level: level, section: section.id)]
        }

        /// The sections to drill in a weak-spot session: the lowest first-try
        /// accuracy among those tried at least five times, then any not yet
        /// tried at all — up to three.
        public var weakSections: [ExamSection] {
            let playable = ExamType.of(level: level).sections(for: level).filter(\.available)
            let tried = playable
                .compactMap { section in stat(for: section).map { (section, $0) } }
                .filter { $0.1.attempts >= 5 }
                .sorted { $0.1.accuracy < $1.1.accuracy }
                .map(\.0)
            let untried = playable.filter { stat(for: $0) == nil }
            return Array((tried + untried).prefix(3))
        }
        public var scoreRatio: Double {
            total > 0 ? Double(firstTryCorrect) / Double(total) : 0
        }
        public var passRatio: Double { ExamType.of(level: level).passRatio(for: level) }
        public var passed: Bool { scoreRatio >= passRatio }
        public var elapsedSeconds: Int {
            guard let startedAt, let finishedAt else { return 0 }
            return Int(finishedAt.timeIntervalSince(startedAt))
        }

        /// Per-大問 results in paper order: (title, right first time, total).
        public var sectionTallies: [SectionTally] {
            var order: [String] = []
            var right: [String: Int] = [:]
            var count: [String: Int] = [:]
            for item in sessionItems {
                let key = item.sectionID ?? ""
                if count[key] == nil { order.append(key) }
                count[key, default: 0] += 1
                if firstTry[item.id] == true { right[key, default: 0] += 1 }
            }
            return order.map { key in
                SectionTally(id: key, title: sectionTitles[key] ?? key,
                             correct: right[key, default: 0], total: count[key, default: 0])
            }
        }
    }

    public struct SectionTally: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let correct: Int
        public let total: Int
    }

    public enum Action: Equatable {
        case onAppear(level: String, language: AppLanguage)
        case levelChanged(String)
        case wrongCountLoaded(Int)
        case wrongDueLoaded(Int)
        case statsLoaded([String: SectionStat])
        case selectWeakMix
        case timeUp
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

    enum CancelID { case load, timer }

    /// Seconds per question on a mock paper — the real 漢検 pace (60 minutes
    /// for a 2級 paper of about 130 answers is ~28s each).
    static let secondsPerQuestion = 30

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.wrongNoteStore) var wrongNoteStore
    @Dependency(\.sectionStatsStore) var sectionStatsStore
    @Dependency(\.studyLogStore) var studyLogStore
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(level, language):
                state.level = level
                state.language = language
                state.today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .merge(refreshWrongCount(level: level, today: state.today), loadStats())

            case let .levelChanged(level):
                guard level != state.level else { return .none }
                state.level = level
                return refreshWrongCount(level: level, today: state.today)

            case let .wrongCountLoaded(count):
                state.wrongCount = count
                return .none

            case let .wrongDueLoaded(count):
                state.wrongDue = count
                return .none

            case let .statsLoaded(stats):
                state.stats = stats
                return .none

            case .selectWeakMix:
                let sections = state.weakSections
                guard !sections.isEmpty else { return .none }
                state.isWeakMix = true
                state.isMockExam = false
                state.activeSection = nil
                state.isWrongNote = false
                state.isLoading = true
                state.started = false
                state.sectionTitles = Dictionary(
                    sections.map { ($0.id, "\($0.numeral)　\($0.jaTitle)") },
                    uniquingKeysWith: { first, _ in first })
                let level = state.level
                let language = state.language
                return .run { send in
                    var all: [KankenQuestion] = []
                    for section in sections {
                        let built = try? await questions(
                            for: section, level: level, language: language, perSection: 7)
                        all.append(contentsOf: built ?? [])
                    }
                    await send(.loaded(all.shuffled()))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case .timeUp:
                // Time's up on a mock paper: whatever is left counts as unanswered.
                guard state.isMockExam, !state.queue.isEmpty else { return .none }
                for item in state.queue where state.firstTry[item.id] == nil {
                    state.firstTry[item.id] = false
                }
                state.queue = []
                state.chosen = nil
                state.finishedAt = date.now
                return .none

            case let .selectMockExam(perSection):
                state.isMockExam = true
                state.activeSection = nil
                state.isWrongNote = false
                state.isWeakMix = false
                state.isLoading = true
                state.started = false
                let level = state.level
                let language = state.language
                // Paper order, not shuffled: a sitting works through its 大問 one
                // after another, and keeping that makes the practice feel like
                // the exam rather than a shuffled quiz.
                let sections = ExamType.of(level: level).sections(for: level).filter(\.available)
                state.sectionTitles = Dictionary(
                    sections.map { ($0.id, "\($0.numeral)　\($0.jaTitle)") },
                    uniquingKeysWith: { first, _ in first })
                return .run { send in
                    var all: [KankenQuestion] = []
                    for section in sections {
                        let built = try? await questions(
                            for: section, level: level, language: language,
                            perSection: perSection)
                        all.append(contentsOf: built ?? [])
                    }
                    await send(.loaded(all))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .selectSection(section):
                state.activeSection = section
                state.isWrongNote = false
                state.isMockExam = false
                state.isWeakMix = false
                state.sectionTitles = [section.id: "\(section.numeral)　\(section.jaTitle)"]
                return loadSection(state: &state, section: section)

            case .selectWrongNote:
                state.activeSection = nil
                state.isWrongNote = true
                state.isMockExam = false
                state.isWeakMix = false
                state.isLoading = true
                state.started = false
                let level = state.level
                let today = state.today
                return .run { send in
                    let notes = await wrongNoteStore.load()
                        .filter { $0.belongs(to: level) }
                        .sorted { $0.savedDay > $1.savedDay }
                    // Today's due notes; if nothing is due, the whole notebook
                    // (reviewing ahead is still useful).
                    let due = notes.filter { $0.isDue(on: today) }
                    await send(.loaded((due.isEmpty ? notes : due).map(\.question)))
                }
                .cancellable(id: CancelID.load, cancelInFlight: true)

            case let .loaded(questions):
                // A load that lands after the learner went back to the hub
                // belongs to a session that no longer exists.
                guard state.isPlaying else { return .none }
                state.isLoading = false
                state.queue = questions
                state.sessionItems = questions
                state.total = questions.count
                beginRun(&state)
                return startTimer(&state)

            case let .chose(option):
                guard state.chosen == nil else { return .none }
                state.chosen = option
                return .none

            case .next:
                guard let item = state.queue.first else { return .none }
                let correct = state.chosen == item.answer
                state.queue.removeFirst()
                state.chosen = nil
                let isFirstTry = state.firstTry[item.id] == nil
                if isFirstTry { state.firstTry[item.id] = correct }
                let level = state.level
                let today = state.today
                var effect: Effect<Action> = .none
                if isFirstTry, state.isWrongNote {
                    // A review answer moves the note along its schedule: a clear
                    // pushes it out (1 → 3 → 7 days, then it retires), a miss
                    // brings it back tomorrow.
                    let id = item.id
                    effect = .run { send in
                        let notes = await wrongNoteStore.update { notes in
                            notes.compactMap { note in
                                note.id == id ? note.reviewed(correct: correct, today: today) : note
                            }
                        }
                        let mine = notes.filter { $0.belongs(to: level) }
                        await send(.wrongCountLoaded(mine.count))
                        await send(.wrongDueLoaded(mine.filter { $0.isDue(on: today) }.count))
                    }
                } else if isFirstTry, let section = item.sectionID {
                    let key = SectionStat.key(level: level, section: section)
                    let delta = SectionStat(attempts: 1, correct: correct ? 1 : 0, lastDay: today)
                    effect = .run { send in
                        await send(.statsLoaded(await sectionStatsStore.record([key: delta])))
                    }
                }
                if isFirstTry {
                    effect = .merge(effect, .run { _ in await studyLogStore.record(today, correct) })
                }
                if correct {
                    state.mastered += 1
                } else {
                    // A drill brings a miss back until it is cleared; a mock
                    // paper, like the real one, is sat once through.
                    if !state.isMockExam { state.queue.append(item) }
                    // A first miss is saved to the 오답노트 (once).
                    if !state.isWrongNote, state.missed.insert(item.id).inserted {
                        let note = WrongNote(question: item, savedDay: state.today, level: level)
                        effect = .merge(effect, .run { send in
                            let notes = await wrongNoteStore.update { notes in
                                notes.filter { $0.id != note.id } + [note]
                            }
                            let mine = notes.filter { $0.belongs(to: level) }
                            await send(.wrongCountLoaded(mine.count))
                            await send(.wrongDueLoaded(mine.filter { $0.isDue(on: today) }.count))
                        })
                    }
                }
                state.attempt += 1
                if state.queue.isEmpty {
                    state.finishedAt = date.now
                    return .merge(effect, .cancel(id: CancelID.timer))
                }
                return effect

            case .restart:
                // The notebook may have shrunk since this run began; re-read it
                // rather than replaying notes that were already cleared.
                if state.isWrongNote { return .send(.selectWrongNote) }
                // A mock paper keeps paper order, as the real sitting does.
                if !state.isMockExam { state.sessionItems.shuffle() }
                state.queue = state.sessionItems
                beginRun(&state)
                return startTimer(&state)

            case .exitToHub:
                state.activeSection = nil
                state.isWrongNote = false
                state.isMockExam = false
                state.isWeakMix = false
                state.timeLimit = nil
                state.isLoading = false
                state.queue = []
                state.sessionItems = []
                state.total = 0
                state.mastered = 0
                state.missed = []
                state.firstTry = [:]
                state.chosen = nil
                state.started = false
                state.startedAt = nil
                state.finishedAt = nil
                return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.timer))

            case .closeTapped:
                // the parent dismisses
                return .merge(.cancel(id: CancelID.load), .cancel(id: CancelID.timer))
            }
        }
    }

    private func beginRun(_ state: inout State) {
        state.mastered = 0
        state.missed = []
        state.firstTry = [:]
        state.chosen = nil
        state.started = true
        state.startedAt = date.now
        state.finishedAt = nil
        state.attempt += 1
    }

    private func refreshWrongCount(level: String, today: Int) -> Effect<Action> {
        .run { send in
            let mine = await wrongNoteStore.load().filter { $0.belongs(to: level) }
            await send(.wrongCountLoaded(mine.count))
            await send(.wrongDueLoaded(mine.filter { $0.isDue(on: today) }.count))
        }
    }

    private func loadStats() -> Effect<Action> {
        .run { send in await send(.statsLoaded(await sectionStatsStore.load())) }
    }

    /// A mock paper runs against the clock; anything else is untimed.
    private func startTimer(_ state: inout State) -> Effect<Action> {
        guard state.isMockExam, state.total > 0 else {
            state.timeLimit = nil
            return .cancel(id: CancelID.timer)
        }
        let limit = state.total * Self.secondsPerQuestion
        state.timeLimit = limit
        return .run { send in
            try await Task.sleep(for: .seconds(limit))
            await send(.timeUp)
        }
        .cancellable(id: CancelID.timer, cancelInFlight: true)
    }

    /// Loads and builds one section's questions from real data.
    private func loadSection(state: inout State, section: ExamSection) -> Effect<Action> {
        state.isLoading = true
        state.started = false
        let level = state.level
        let language = state.language
        return .run { send in
            await send(.loaded(
                try await questions(for: section, level: level, language: language,
                                    perSection: 20)))
        }
        .cancellable(id: CancelID.load, cancelInFlight: true)
    }

    /// Every question for one 大問, at the level given. Shared by a single
    /// section and by the mock paper, which needs all of them.
    private func questions(for section: ExamSection, level: String,
                           language: AppLanguage,
                           perSection: Int) async throws -> [KankenQuestion] {
        let built: [KankenQuestion]
        if let kind = section.kind {
            let bank = (try? await dictionaryClient.examQuestions(level, kind, perSection)) ?? []
            // Every bank section carries its own instruction: ten of them share
            // a render type, and the type's generic wording would ask for the
            // wrong thing (用法 is not a synonym question, 誤字訂正 not 書き取り).
            built = bank.map {
                KankenQuestion.from($0, type: section.renderType, language: language,
                                    label: section.instruction(language))
            }
        } else {
            switch section.renderType {
            case .strokes:
                let items = (try? await dictionaryClient.examStrokeItems(level, 80)) ?? []
                built = KankenQuestion.strokeQuiz(items, count: perSection, language: language)
            case .yojijukugo:
                let items = (try? await dictionaryClient.examYojijukugo(level, 80)) ?? []
                built = KankenQuestion.yojijukugoQuiz(items, count: perSection, language: language)
            case .okurigana:
                let items = (try? await dictionaryClient.examOkurigana(level, 120)) ?? []
                built = KankenQuestion.okuriganaQuiz(items, count: perSection, language: language)
            case .taigirui:
                let items = (try? await dictionaryClient.examTaigirui(level, nil, 60)) ?? []
                built = KankenQuestion.taigiruiQuiz(items, count: perSection, language: language)
            case .hitsujun:
                let items = (try? await dictionaryClient.examStrokeOrderItems(level, 60)) ?? []
                built = KankenQuestion.hitsujunQuiz(items, count: perSection, language: language)
            case .onkun:
                let items = (try? await dictionaryClient.examOnKun(level, 60)) ?? []
                built = KankenQuestion.onKunQuiz(items, count: perSection, language: language)
            default:
                let items = (try? await dictionaryClient.examRadicalItems(level, 80)) ?? []
                built = KankenQuestion.radicalQuiz(items, count: perSection)
            }
        }
        return built
            .filter { $0.options.count >= 2 }
            .map { question in
                var question = question
                question.sectionID = section.id
                return question
            }
    }
}

extension KankenQuestion {
    /// Adapts a pre-authored `JLPTQuestion` into an exam section question.
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
    /// As on the real paper, the wrong answers are the kanji's own other parts
    /// (聞: 門 is offered against the answer 耳), topped up with other radicals
    /// from the same 級 when a kanji has too few parts.
    static func radicalQuiz(_ items: [RadicalItem], count: Int) -> [KankenQuestion] {
        let pool = Array(Set(items.map(\.radical)))
        guard pool.count >= 4 else { return [] }
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.kanjiID &+ index &+ 1))
            // Single-character parts only, never the answer or the kanji itself.
            var distractors: [String] = []
            for part in item.parts where part.count == 1 && part != item.radical
                && part != item.literal && !distractors.contains(part) {
                distractors.append(part)
            }
            distractors = Array(distractors.shuffled(using: &rng).prefix(3))
            for other in pool.shuffled(using: &rng) where distractors.count < 3 {
                if other != item.radical && !distractors.contains(other) { distractors.append(other) }
            }
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
    /// choices. Distractors are nearby counts (±3) so the choice is non-trivial.
    static func strokeQuiz(_ items: [StrokeItem], count: Int, language: AppLanguage) -> [KankenQuestion] {
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.kanjiID &+ index &+ 7))
            let answer = L.strokeCount(item.strokeCount, language)
            let nearby = (max(1, item.strokeCount - 3)...(item.strokeCount + 3))
                .filter { $0 != item.strokeCount }.map { L.strokeCount($0, language) }
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
    /// answer is where that stroke falls in writing order — an ordinal ("3画目"),
    /// as the real paper asks it, not a stroke count. The strokes travel on the
    /// question so a 오답노트 entry still renders without another query.
    ///
    /// The marked stroke is never the first or the last: those are guessable from
    /// the shape alone, which tests recognition rather than stroke order.
    static func hitsujunQuiz(_ items: [StrokeOrderItem], count: Int,
                             language: AppLanguage) -> [KankenQuestion] {
        var out: [KankenQuestion] = []
        for (index, item) in items.enumerated() where out.count < count {
            let total = item.paths.count
            guard total >= 4 else { continue }
            var rng = SeededRNG(seed: UInt64(item.kanjiID &+ index &+ 11))
            let interior = Array(1..<(total - 1))
            guard let marked = interior.shuffled(using: &rng).first else { continue }
            let answer = L.strokeOrdinal(marked + 1, language)
            // Neighbouring positions are the realistic mistakes.
            let others = (1...total).filter { $0 != marked + 1 }
                .sorted { abs($0 - (marked + 1)) < abs($1 - (marked + 1)) }
                .prefix(5).shuffled(using: &rng)
                .map { L.strokeOrdinal($0, language) }
            let distractors = others.prefix(3)
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

    /// Builds 四字熟語 questions, alternating the two things the paper asks:
    /// write the missing kanji of an idiom (shown with its reading, as the exam
    /// gives the blank in kana), and pick the idiom's meaning. Blank distractors
    /// are kanji from the same position of other idioms, never one that would
    /// spell another idiom in the pool.
    static func yojijukugoQuiz(_ items: [Yojijukugo], count: Int, language: AppLanguage) -> [KankenQuestion] {
        guard items.count >= 4 else { return [] }
        let known = Set(items.map(\.yoji))
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.id &+ index &+ 3))
            let chars = Array(item.yoji)
            let askBlank = index % 2 == 0 && chars.count == 4
            if askBlank {
                let position = Int.random(in: 0..<4, using: &rng)
                let answer = String(chars[position])
                var candidates = Set<String>()
                for other in items where other.id != item.id {
                    let otherChars = Array(other.yoji)
                    guard otherChars.count == 4 else { continue }
                    let candidate = String(otherChars[position])
                    guard candidate != answer, !chars.contains(Character(candidate)) else { continue }
                    var respelled = chars
                    respelled[position] = Character(candidate)
                    guard !known.contains(String(respelled)) else { continue }
                    candidates.insert(candidate)
                }
                let options = quizOptions(answer: answer, pool: Array(candidates), rng: &rng)
                guard options.count == 4 else { continue }
                var blanked = chars
                blanked[position] = "□"
                let meaning = item.meaning(language).map { " — \($0)" } ?? ""
                out.append(KankenQuestion(
                    id: "yoji:b:\(item.id)", type: .yojijukugo, kanjiID: item.id,
                    prompt: "\(String(blanked))\n（\(item.reading)）", focus: nil,
                    options: options, answer: answer,
                    explanation: "\(item.yoji)（\(item.reading)）\(meaning)",
                    label: L.labelYojiBlank[language]))
            } else if let meaning = item.meaning(language), !meaning.isEmpty {
                let pool = items.compactMap { $0.meaning(language) }
                let options = quizOptions(answer: meaning, pool: pool, rng: &rng)
                guard options.count >= 2 else { continue }
                out.append(KankenQuestion(
                    id: "yoji:m:\(item.id)", type: .yojijukugo, kanjiID: item.id,
                    prompt: item.yoji, focus: nil, options: options, answer: meaning,
                    explanation: "\(item.yoji)（\(item.reading)）",
                    label: L.labelMeaning[language]))
            }
        }
        return out
    }

    /// Builds 送りがな questions: the word is shown in katakana with its meaning;
    /// pick where the kanji ends and the okurigana begins. Distractors shift the
    /// okurigana boundary (the classic 送りがな trap), keeping the same kanji stem.
    static func okuriganaQuiz(_ items: [WordEntry], count: Int,
                              language: AppLanguage) -> [KankenQuestion] {
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
            // The kanji has to carry at least one kana of its own, or every
            // variant would read as the kanji plus the whole word.
            guard kanjiKanaLen >= 1, !readingChars.isEmpty else { continue }
            // Boundary-shift distractors: same kanji, different okurigana length,
            // never swallowing the whole reading.
            var distractors: [String] = []
            for delta in [1, -1, 2] {
                let newLen = okuriLen + delta
                guard newLen >= 1, newLen <= readingChars.count - 1 else { continue }
                let variant = kanjiPart + String(readingChars.suffix(newLen))
                if variant != surface, !distractors.contains(variant) { distractors.append(variant) }
            }
            guard distractors.count >= 2 else { continue }
            let kata = item.reading.applyingTransform(.hiraganaToKatakana, reverse: false) ?? item.reading
            var rng = SeededRNG(seed: UInt64(item.id &+ 11))
            let options = (Array(distractors.prefix(3)) + [surface]).shuffled(using: &rng)
            used.insert(surface)
            let meaning = item.meaning(language)
            out.append(KankenQuestion(
                id: "okuri:\(item.id)", type: .okurigana, kanjiID: item.id,
                prompt: meaning.map { "\(kata)\n（\($0)）" } ?? kata, focus: kata,
                options: options, answer: surface,
                explanation: "\(surface)（\(item.reading)）" + (meaning.map { " — \($0)" } ?? ""),
                label: L.labelOkurigana[language]))
        }
        return out
    }

    /// Builds 対義語・類義語 questions: the prompt word is shown; pick its antonym or
    /// synonym. Distractors are answers of the same relation and the same length,
    /// so neither the shape nor the other relation's pairs give it away.
    static func taigiruiQuiz(_ items: [TaigiruiPair], count: Int,
                             language: AppLanguage) -> [KankenQuestion] {
        guard items.count >= 4 else { return [] }
        var out: [KankenQuestion] = []
        for (index, item) in items.prefix(count).enumerated() {
            var rng = SeededRNG(seed: UInt64(item.id &+ index &+ 5))
            let sameRelation = items.filter {
                $0.relation == item.relation && $0.id != item.id && $0.word != item.answer
            }
            var pool = sameRelation.filter { $0.answer.count == item.answer.count }.map(\.answer)
            if Set(pool).count < 3 { pool = sameRelation.map(\.answer) }
            if Set(pool).count < 3 { pool = items.map(\.answer) }
            // The prompt word itself is never an option.
            pool = pool.filter { $0 != item.word }
            let options = quizOptions(answer: item.answer, pool: pool, rng: &rng)
            guard options.count >= 2 else { continue }
            out.append(KankenQuestion(
                id: "taigi:\(item.id)", type: .taigirui, kanjiID: item.id,
                prompt: item.word, focus: nil, options: options, answer: item.answer,
                explanation: "\(item.word)（\(item.wordReading)）↔ \(item.answer)（\(item.answerReading)）",
                label: item.relation == "対義" ? L.labelAntonym[language] : L.labelSynonym[language]))
        }
        return out
    }

    /// Builds 音読み・訓読み questions: show the kanji, pick one of its 音読み (or
    /// 訓読み) readings. Distractors are same-type readings (katakana for 音 /
    /// hiragana for 訓) from other kanji, so the script alone doesn't give it
    /// away — and never another reading of this same kanji, which would also
    /// be correct (行: コウ and ギョウ).
    static func onKunQuiz(_ items: [OnKunItem], count: Int,
                          language: AppLanguage) -> [KankenQuestion] {
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
            let own = Set(item.onReadings + item.kunReadings)
            let pool = (askOn ? onPool : kunPool).filter { !own.contains($0) }
            let options = quizOptions(answer: answer, pool: pool, rng: &rng)
            guard options.count == 4 else { continue }
            out.append(KankenQuestion(
                id: "onkun:\(askOn ? "o" : "k"):\(item.kanjiID)", type: .onkun, kanjiID: item.kanjiID,
                prompt: item.literal, focus: nil, options: options, answer: answer,
                explanation: explainReadings(item),
                label: askOn ? L.labelOn[language] : L.labelKun[language]))
        }
        return out
    }

    /// "音: コウ・ギョウ　訓: い・ゆ" — all of a kanji's readings, shown after
    /// answering so one question teaches the whole set.
    private static func explainReadings(_ item: OnKunItem) -> String {
        var parts: [String] = []
        if !item.onReadings.isEmpty { parts.append("音: " + item.onReadings.joined(separator: "・")) }
        if !item.kunReadings.isEmpty { parts.append("訓: " + item.kunReadings.joined(separator: "・")) }
        return "\(item.literal)　" + parts.joined(separator: "　")
    }

    /// The answer plus up to 3 distinct distractors from `pool`, seeded-shuffled.
    private static func quizOptions(answer: String, pool: [String], rng: inout SeededRNG) -> [String] {
        var distractors = Array(Set(pool.filter { $0 != answer && !$0.isEmpty })).sorted()
        distractors.shuffle(using: &rng)
        let options = (Array(distractors.prefix(3)) + [answer]).shuffled(using: &rng)
        return options
    }

    private static func localizedExplanation(_ dict: [String: String], _ language: AppLanguage) -> String? {
        for key in [language.glossKey, "en", "ja", "ko", "zh"] {
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
