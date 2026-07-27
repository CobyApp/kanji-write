import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// The word detail screen: a saved/usage word with its reading, native meaning,
/// example sentences, and the kanji it contains (each tappable → kanji detail).
@Reducer
public struct WordDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public var word: WordEntry
        /// The list this detail was opened from + position, for prev/next.
        public var siblings: [WordEntry]
        public var index: Int
        public var sentences: [ExampleSentence] = []
        public var kanji: [Kanji] = []
        /// KanjiVG stroke-order guides for the word's kanji (kanji id → path d's),
        /// used by the word tracing grid.
        public var strokesByID: [Int: [String]] = [:]
        /// Each contained kanji's glosses (kanji id → lang code → meaning), for
        /// the richer 한자 section (meaning + readings per kanji).
        public var glossesByID: [Int: [String: String]] = [:]
        public var isLoading = false
        public var loaded = false
        public var addedToWordbook = false

        public init(word: WordEntry, siblings: [WordEntry] = [], index: Int = 0) {
            self.word = word
            self.siblings = siblings.isEmpty ? [word] : siblings
            self.index = siblings.isEmpty ? 0 : index
        }

        public var hasPrev: Bool { index > 0 }
        public var hasNext: Bool { index < siblings.count - 1 }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([ExampleSentence], [Kanji], [Int: [String]], [Int: [String: String]])
        case showSibling(delta: Int)
        case kanjiTapped(Kanji)  // delegate → parent pushes the kanji detail
        case addToWordbook
        case markedAddedToWordbook
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.wordReviewStore) var wordReviewStore
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.loaded else { return .none }
                state.isLoading = true
                return load(state.word.id)

            case let .showSibling(delta):
                let new = state.index + delta
                guard state.siblings.indices.contains(new) else { return .none }
                state.index = new
                state.word = state.siblings[new]
                state.loaded = false
                state.sentences = []
                state.kanji = []
                state.strokesByID = [:]
                state.glossesByID = [:]
                state.addedToWordbook = false
                state.isLoading = true
                return load(state.word.id)

            case let .loaded(sentences, kanji, strokes, glosses):
                state.isLoading = false
                state.loaded = true
                state.sentences = sentences
                state.kanji = kanji
                state.strokesByID = strokes
                state.glossesByID = glosses
                return .none
            case .kanjiTapped:
                return .none  // handled by the parent (navigation)
            case .addToWordbook:
                let wordID = state.word.id
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    var records = await wordReviewStore.loadRecords()
                    guard !records.contains(where: { $0.kanjiID == wordID }) else {
                        await send(.markedAddedToWordbook)
                        return
                    }
                    let initial = FSRS.initialState(.good)
                    records.append(ReviewRecord(
                        kanjiID: wordID, stability: initial.stability,
                        difficulty: initial.difficulty, due: today,
                        lastReviewedDay: today, lapses: 0, reps: 0))
                    await wordReviewStore.saveRecords(records)
                    await send(.markedAddedToWordbook)
                }
            case .markedAddedToWordbook:
                state.addedToWordbook = true
                return .none
            }
        }
    }

    /// Fetch a word's example sentences and its constituent kanji (+ strokes/glosses).
    private func load(_ id: Int) -> Effect<Action> {
        .run { send in
            async let sentencesTask = dictionaryClient.sentencesForWord(id, 5)
            let kanji = (try? await dictionaryClient.kanjiForWord(id)) ?? []
            var strokes: [Int: [String]] = [:]
            var glosses: [Int: [String: String]] = [:]
            for k in kanji {
                strokes[k.id] = (try? await dictionaryClient.strokeOrder(k.id)) ?? []
                glosses[k.id] = (try? await dictionaryClient.glosses(k.id)) ?? [:]
            }
            let sentences = (try? await sentencesTask) ?? []
            await send(.loaded(sentences, kanji, strokes, glosses))
        }
    }
}
