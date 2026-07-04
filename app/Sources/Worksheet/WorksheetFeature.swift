import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// Builds today's guided-study queue: the next `newPerDay` never-seen kanji from
/// `studyOrder(kanji)`, mapped from `todaysSession(...).newIDs` to the matching
/// `Kanji`. IDs whose kanji is missing are dropped so the queue never holds an
/// unshowable lesson. Order is preserved from `newIDs` (JLPT → strokes → id).
public func buildWorksheetQueue(
    records: [ReviewRecord], kanji: [Kanji], today: Int, newPerDay: Int, level: String? = nil
) -> [Kanji] {
    let session = todaysSession(
        records: records, order: studyOrder(kanji, level: level), today: today, newPerDay: newPerDay)
    let byID = Dictionary(kanji.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    return session.newIDs.compactMap { byID[$0] }
}

/// A guided study-sheet for today's NEW kanji: for each one, write it once over
/// the stroke-order guide, see one word that uses it, and one example sentence.
/// Finishing schedules an initial FSRS record for every kanji learned so it
/// enters the review cycle.
@Reducer
public struct WorksheetFeature {
    @ObservableState
    public struct State: Equatable {
        /// All persisted SRS records, keyed by kanji id.
        public var records: IdentifiedArrayOf<ReviewRecord> = []
        /// Today's new-kanji lesson queue, in study order.
        public var queue: [Kanji] = []
        /// Index into `queue` of the kanji currently being studied.
        public var index = 0
        /// Today as an integer epoch-day number.
        public var today = 0
        /// New kanji per day (from `@AppStorage("newPerDay")`, passed on appear).
        public var newPerDay = 7
        /// Target JLPT level for the plan (from `@AppStorage("targetLevel")`); new
        /// kanji are drawn only from this level. nil = all levels.
        public var targetLevel: String? = "N5"
        /// Words that use the current kanji (a few, in commonness order).
        public var words: [WordEntry] = []
        /// Example sentences for the current kanji (a few).
        public var sentences: [ExampleSentence] = []
        /// KanjiVG stroke-order guide (path `d` strings) for the current kanji.
        public var strokePaths: [String] = []
        /// Raw gloss map (lang code → meaning) for the current kanji; the view
        /// resolves the display meaning per app-language with a fallback.
        public var glosses: [String: String] = [:]
        /// Bumped whenever the write canvas should reset to a blank page.
        public var clearToken = 0
        /// Never-seen kanji remaining in the target level (for the finish estimate).
        public var remaining = 0
        public var isLoading = false
        /// True once today's queue has been built at least once. Until then the
        /// view shows a loading placeholder instead of the "no kanji" empty state.
        public var hasLoaded = false
        public var isFinished = false

        public init() {}

        /// The kanji currently being studied, or nil when the queue is exhausted.
        public var current: Kanji? {
            queue.indices.contains(index) ? queue[index] : nil
        }

        /// True when the current kanji is the last one in the queue.
        public var isLast: Bool { index >= queue.count - 1 }
    }

    public enum Action: Equatable {
        case onAppear(newPerDay: Int, level: String?)
        case loaded([ReviewRecord], [Kanji], Int)
        case cardContentLoaded(
            words: [WordEntry], sentences: [ExampleSentence], strokePaths: [String],
            glosses: [String: String])
        case nextTapped
        case doneTapped
        case kanjiTapped(Kanji)   // delegate → parent drills into the kanji detail
        case wordTapped(WordEntry) // delegate → parent drills into the word detail
    }

    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(newPerDay, level):
                guard state.queue.isEmpty, !state.isFinished, !state.isLoading else { return .none }
                state.isLoading = true
                state.newPerDay = max(1, newPerDay)  // never let a 0/day plan blank the lesson
                state.targetLevel = level
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    async let records = reviewStore.loadRecords()
                    let kanji = (try? await dictionaryClient.allKanji()) ?? []
                    await send(.loaded(await records, kanji, today))
                }

            case let .loaded(records, kanji, today):
                state.isLoading = false
                state.hasLoaded = true
                state.records = IdentifiedArray(uniqueElements: records)
                state.today = today
                state.queue = buildWorksheetQueue(
                    records: records, kanji: kanji, today: today, newPerDay: state.newPerDay,
                    level: state.targetLevel)
                state.remaining = remainingNew(
                    order: studyOrder(kanji, level: state.targetLevel), records: records)
                state.index = 0
                return loadCardContent(state: &state)

            case let .cardContentLoaded(words, sentences, strokePaths, glosses):
                state.words = words
                state.sentences = sentences
                state.strokePaths = strokePaths
                state.glosses = glosses
                return .none

            case .nextTapped:
                guard !state.isLast else { return .none }
                state.index += 1
                state.words = []
                state.sentences = []
                state.strokePaths = []
                state.glosses = [:]
                state.clearToken += 1
                return loadCardContent(state: &state)

            case .doneTapped:
                let today = state.today
                // Each learned kanji gets an initial FSRS record (rated Good) so it
                // enters the review cycle, due today + the first interval. Never
                // overwrite an existing record.
                for kanji in state.queue where state.records[id: kanji.id] == nil {
                    let initial = FSRS.initialState(.good)
                    let interval = FSRS.interval(stability: initial.stability, retention: 0.9)
                    state.records[id: kanji.id] = ReviewRecord(
                        kanjiID: kanji.id, stability: initial.stability,
                        difficulty: initial.difficulty, due: today + interval,
                        lastReviewedDay: today, lapses: 0, reps: 1)
                }
                state.isFinished = true
                let all = Array(state.records)
                return .run { _ in await reviewStore.saveRecords(all) }

            case .kanjiTapped, .wordTapped:
                return .none  // handled by the parent (in-session navigation)
            }
        }
    }

    /// Loads the first word, first example sentence, and stroke-order guide for
    /// the current kanji. All are optional/non-critical: on any failure the
    /// worksheet still shows the glyph + write canvas.
    private func loadCardContent(state: inout State) -> Effect<Action> {
        guard let kanji = state.current else { return .none }
        let id = kanji.id
        return .run { send in
            async let wordsTask = try? await dictionaryClient.words(id, 4)
            async let sentencesTask = try? await dictionaryClient.sentences(id, 3)
            async let glossesTask = try? await dictionaryClient.glosses(id)
            let paths = (try? await dictionaryClient.strokeOrder(id)) ?? []
            let words = await wordsTask ?? []
            let sentences = await sentencesTask ?? []
            let glosses = await glossesTask ?? [:]
            await send(.cardContentLoaded(
                words: words, sentences: sentences, strokePaths: paths, glosses: glosses))
        }
    }
}
