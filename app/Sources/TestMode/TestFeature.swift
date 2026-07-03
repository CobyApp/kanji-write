import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// Builds the ordered flashcard queue for the test: every FSRS-due card, mapped
/// from `todaysSession(...).dueIDs` to the matching `Kanji`. IDs whose kanji is
/// missing from `kanji` are dropped so the queue never holds an unshowable card.
/// Order is preserved from `dueIDs` (already sorted by due then difficulty).
public func buildTestQueue(
    records: [ReviewRecord], kanji: [Kanji], today: Int
) -> [Kanji] {
    let session = todaysSession(records: records, order: [], today: today, newPerDay: 0)
    let byID = Dictionary(kanji.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return session.dueIDs.compactMap { byID[$0] }
}

@Reducer
public struct TestFeature {
    @ObservableState
    public struct State: Equatable {
        /// All persisted SRS records, keyed by kanji id.
        public var records: IdentifiedArrayOf<ReviewRecord> = []
        /// The due queue for today, ordered by due then difficulty.
        public var queue: [Kanji] = []
        /// Index into `queue` of the card being shown.
        public var index = 0
        /// Today as an integer epoch-day number.
        public var today = 0
        /// Whether the answer (glyph + readings + guide) is revealed for this card.
        public var revealed = false
        /// Raw gloss map (lang code → meaning) for the current card; the view
        /// resolves the display gloss per app-language with a fallback.
        public var glosses: [String: String] = [:]
        /// KanjiVG stroke-order guide for the current card (shown only after reveal).
        public var strokePaths: [String] = []
        /// Bumped whenever the canvas should reset to a blank page (new card).
        public var clearToken = 0
        public var isLoading = false
        /// All kanji, kept to draw multiple-choice distractors (iPhone review).
        public var pool: [Kanji] = []
        /// The current card's shuffled choices (correct + 3 distractors), for the
        /// iPhone multiple-choice mode.
        public var options: [Kanji] = []
        /// The option the learner tapped this card (kanji id) — drives the
        /// correct/wrong highlight before advancing.
        public var selected: Int?

        public init() {}

        /// The card currently under test, or nil when the queue is exhausted.
        public var current: Kanji? {
            queue.indices.contains(index) ? queue[index] : nil
        }

        /// True once every card in the queue has been graded.
        public var isFinished: Bool { index >= queue.count }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([ReviewRecord], [Kanji], Int)
        case cardContentLoaded(glosses: [String: String], strokePaths: [String])
        case showAnswerTapped
        case optionSelected(Int)  // iPhone multiple-choice tap (kanji id)
        case graded(pass: Bool)
    }

    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.queue.isEmpty, !state.isLoading else { return .none }
                state.isLoading = true
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    async let records = reviewStore.loadRecords()
                    let kanji = (try? await dictionaryClient.allKanji()) ?? []
                    await send(.loaded(await records, kanji, today))
                }

            case let .loaded(records, kanji, today):
                state.isLoading = false
                state.records = IdentifiedArray(uniqueElements: records)
                state.today = today
                state.pool = kanji
                state.queue = buildTestQueue(records: records, kanji: kanji, today: today)
                state.index = 0
                setOptions(&state)
                return loadCardContent(state: &state)

            case let .cardContentLoaded(glosses, strokePaths):
                state.glosses = glosses
                state.strokePaths = strokePaths
                return .none

            case .showAnswerTapped:
                state.revealed = true
                return .none

            case let .optionSelected(id):
                guard !state.revealed else { return .none }
                state.selected = id
                state.revealed = true
                return .none

            case let .graded(pass):
                guard let kanji = state.current else { return .none }
                let today = state.today
                let grade: Grade = pass ? .good : .again
                let updated: ReviewRecord
                if let rec = state.records[id: kanji.id] {
                    let result = FSRS.schedule(
                        state: MemoryState(stability: rec.stability, difficulty: rec.difficulty),
                        grade: grade, elapsedDays: today - rec.lastReviewedDay)
                    updated = ReviewRecord(
                        kanjiID: kanji.id, stability: result.state.stability,
                        difficulty: result.state.difficulty, due: today + result.intervalDays,
                        lastReviewedDay: today, lapses: rec.lapses + (grade == .again ? 1 : 0),
                        reps: rec.reps + 1)
                } else {
                    let result = FSRS.schedule(state: nil, grade: grade, elapsedDays: 0)
                    updated = ReviewRecord(
                        kanjiID: kanji.id, stability: result.state.stability,
                        difficulty: result.state.difficulty, due: today + result.intervalDays,
                        lastReviewedDay: today, lapses: grade == .again ? 1 : 0, reps: 1)
                }
                state.records[id: kanji.id] = updated
                let all = Array(state.records)

                // Advance to the next card and reset per-card view state.
                state.index += 1
                state.revealed = false
                state.selected = nil
                state.glosses = [:]
                state.strokePaths = []
                state.clearToken += 1
                setOptions(&state)

                let loadNext = loadCardContent(state: &state)
                return .merge(
                    .run { _ in await reviewStore.saveRecords(all) },
                    loadNext)
            }
        }
    }

    /// Builds the current card's multiple-choice options: the correct kanji plus
    /// up to three distractors drawn from the pool, shuffled.
    private func setOptions(_ state: inout State) {
        guard let correct = state.current else { state.options = []; return }
        let distractors = state.pool.filter { $0.id != correct.id }.shuffled().prefix(3)
        state.options = (Array(distractors) + [correct]).shuffled()
    }

    /// Loads the localized meaning + stroke-order guide for the current card.
    /// The gloss language is resolved at render time; here we fetch all glosses
    /// and pick with the app-language fallback (mirrors KanjiDetail's helper).
    private func loadCardContent(state: inout State) -> Effect<Action> {
        guard let kanji = state.current else { return .none }
        let id = kanji.id
        return .run { send in
            async let glossesTask = try? await dictionaryClient.glosses(id)
            let paths = (try? await dictionaryClient.strokeOrder(id)) ?? []
            let glosses = await glossesTask ?? [:]
            await send(.cardContentLoaded(glosses: glosses, strokePaths: paths))
        }
    }
}
