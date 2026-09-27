import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

@Reducer
public struct KanjiDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanji: Kanji
        /// The list this detail was opened from + the current position, so prev/
        /// next can step through it without returning to the list.
        public var siblings: [Kanji]
        public var index: Int
        public var glosses: [String: String] = [:]
        public var words: IdentifiedArrayOf<WordEntry> = []
        public var sentences: [ExampleSentence] = []
        public var relations: [RelationEntry] = []
        /// 旧字 forms, when this kanji has one. Almost none do.
        public var variants: [KanjiVariant] = []
        /// Look-alike kanji (same parts), for telling 待 from 持 and 特.
        public var similar: [KanjiRef] = []
        public var strokePaths: [String] = []
        public var isLoading = false
        public var addedToReview = false
        public var isBookmarked = false

        public init(kanji: Kanji, siblings: [Kanji] = [], index: Int = 0) {
            self.kanji = kanji
            self.siblings = siblings.isEmpty ? [kanji] : siblings
            self.index = siblings.isEmpty ? 0 : index
        }

        public var hasPrev: Bool { index > 0 }
        public var hasNext: Bool { index < siblings.count - 1 }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([String: String], [WordEntry], [ExampleSentence], [RelationEntry], [String],
                [KanjiVariant])
        case bookmarkLoaded(Bool)
        case similarLoaded([KanjiRef])
        case similarTapped(KanjiRef)  // delegate → parent pushes that kanji
        case showSibling(delta: Int)   // prev (-1) / next (+1)
        case writeTapped
        case wordTapped(WordEntry)  // delegate → parent pushes the word detail
        case relationTapped(String) // an antonym/related surface → resolve → word
        case addToReview
        case markedAddedToReview
        case toggleBookmark
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.kanjiBookmarkStore) var kanjiBookmarkStore
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.glosses.isEmpty else { return .none }
                state.isLoading = true
                return load(state.kanji.id)

            case let .showSibling(delta):
                let new = state.index + delta
                guard state.siblings.indices.contains(new) else { return .none }
                state.index = new
                state.kanji = state.siblings[new]
                // Reset the previous kanji's loaded content and re-fetch.
                state.glosses = [:]
                state.words = []
                state.sentences = []
                state.relations = []
                state.variants = []
                state.similar = []
                state.strokePaths = []
                state.addedToReview = false
                state.isLoading = true
                return load(state.kanji.id)
            case let .loaded(glosses, words, sentences, relations, strokePaths, variants):
                state.isLoading = false
                state.glosses = glosses
                state.words = IdentifiedArray(uniqueElements: words)
                state.sentences = sentences
                state.relations = relations
                state.strokePaths = strokePaths
                state.variants = variants
                return .none
            case let .bookmarkLoaded(bookmarked):
                state.isBookmarked = bookmarked
                return .none
            case let .similarLoaded(similar):
                state.similar = similar
                return .none
            case .similarTapped:
                return .none  // handled by the parent (navigation)
            case .toggleBookmark:
                state.isBookmarked.toggle()
                let id = state.kanji.id
                let nowBookmarked = state.isBookmarked
                return .run { _ in
                    var ids = await kanjiBookmarkStore.load()
                    if nowBookmarked {
                        if !ids.contains(id) { ids.append(id) }
                    } else {
                        ids.removeAll { $0 == id }
                    }
                    await kanjiBookmarkStore.save(ids)
                }
            case .writeTapped, .wordTapped:
                return .none  // handled by the parent (navigation)
            case let .relationTapped(surface):
                // A related/antonym word is stored only as a surface string; look
                // it up and, if found, hand it to the parent as a normal word tap.
                return .run { send in
                    if let word = try? await dictionaryClient.searchWords(surface, 1).first {
                        await send(.wordTapped(word))
                    }
                }
            case .addToReview:
                let kanjiID = state.kanji.id
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    var records = await reviewStore.loadRecords()
                    guard !records.contains(where: { $0.kanjiID == kanjiID }) else {
                        await send(.markedAddedToReview)
                        return
                    }
                    let initial = FSRS.initialState(.good)
                    records.append(ReviewRecord(
                        kanjiID: kanjiID, stability: initial.stability,
                        difficulty: initial.difficulty, due: today,
                        lastReviewedDay: today, lapses: 0, reps: 0))
                    await reviewStore.saveRecords(records)
                    await send(.markedAddedToReview)
                }
            case .markedAddedToReview:
                state.addedToReview = true
                return .none
            }
        }
    }

    /// Fetch a kanji's detail content (glosses / words / sentences / relations /
    /// strokes) plus its bookmark state.
    private func load(_ id: Int) -> Effect<Action> {
        .run { send in
            async let glosses = dictionaryClient.glosses(id)
            async let words = dictionaryClient.words(id, 12)
            async let sentences = dictionaryClient.sentences(id, 3)
            async let relations = dictionaryClient.relations(id, 20)
            async let strokes = dictionaryClient.strokeOrder(id)
            async let variants = dictionaryClient.variants(id)
            await send(.loaded(
                (try? await glosses) ?? [:],
                (try? await words) ?? [],
                (try? await sentences) ?? [],
                (try? await relations) ?? [],
                (try? await strokes) ?? [],
                (try? await variants) ?? []
            ))
            await send(.bookmarkLoaded(await kanjiBookmarkStore.load().contains(id)))
            await send(.similarLoaded((try? await dictionaryClient.similarKanji(id, 6)) ?? []))
        }
    }
}
