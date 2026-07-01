import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

/// The word detail screen: a saved/usage word with its reading, native meaning,
/// example sentences, and the kanji it contains (each tappable → kanji detail).
@Reducer
public struct WordDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public let word: WordEntry
        public var sentences: [ExampleSentence] = []
        public var kanji: [Kanji] = []
        public var isLoading = false
        public var loaded = false
        public init(word: WordEntry) { self.word = word }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([ExampleSentence], [Kanji])
        case kanjiTapped(Kanji)  // delegate → parent pushes the kanji detail
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.loaded else { return .none }
                state.isLoading = true
                let id = state.word.id
                return .run { send in
                    async let sentences = dictionaryClient.sentencesForWord(id, 5)
                    async let kanji = dictionaryClient.kanjiForWord(id)
                    await send(.loaded(
                        (try? await sentences) ?? [],
                        (try? await kanji) ?? []))
                }
            case let .loaded(sentences, kanji):
                state.isLoading = false
                state.loaded = true
                state.sentences = sentences
                state.kanji = kanji
                return .none
            case .kanjiTapped:
                return .none  // handled by the parent (navigation)
            }
        }
    }
}
