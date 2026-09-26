import ComposableArchitecture
import DictionaryClient
import Foundation
import KanjiListFeature
import SharedModels

/// The word dictionary browse: pick a JLPT level to list its words (common
/// first), or search across every word by surface / reading / meaning. Word
/// selection delegates up to `RootFeature`, which pushes the word detail.
@Reducer
public struct WordDictionaryFeature {
    @ObservableState
    public struct State: Equatable {
        /// Current level, seeded from the active exam (JLPT "N5" / 漢検 "10級").
        public var level: String = ExamType.current.defaultLevel
        public var words: [WordEntry] = []          // current level's words
        public var searchText = ""
        public var searchResults: [WordEntry] = []
        public var isLoading = false
        /// true = 표현(expression) dictionary (phrases); false = plain 단어 dictionary.
        public var expressions = false

        public init(expressions: Bool = false) {
            self.expressions = expressions
        }

        public var isSearching: Bool {
            !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        }

        /// The level list, split to this dictionary's mode (word vs expression).
        public var visibleWords: [WordEntry] {
            words.filter { isExpressionSurface($0.surface) == expressions }
        }
        /// Search results, split to this dictionary's mode.
        public var visibleResults: [WordEntry] {
            searchResults.filter { isExpressionSurface($0.surface) == expressions }
        }
    }

    public enum Action: Equatable {
        case onAppear
        case levelSelected(String)
        case searchChanged(String)
        case levelLoaded([WordEntry])
        case searchLoaded(query: String, [WordEntry])
        case wordSelected(WordEntry)   // delegate → parent pushes the word detail
    }

    private enum CancelID { case search }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.words.isEmpty else { return .none }
                return loadLevel(state: &state)

            case let .levelSelected(level):
                state.level = level
                return loadLevel(state: &state)

            case let .levelLoaded(words):
                state.isLoading = false
                state.words = words
                return .none

            case let .searchChanged(text):
                state.searchText = text
                guard state.isSearching else {
                    state.searchResults = []
                    return .cancel(id: CancelID.search)
                }
                return .run { send in
                    let results = (try? await dictionaryClient.searchWords(text, 120)) ?? []
                    await send(.searchLoaded(query: text, results))
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)

            case let .searchLoaded(query, results):
                guard query == state.searchText else { return .none }  // ignore stale
                state.searchResults = results
                return .none

            case .wordSelected:
                return .none  // handled by the parent (navigation)
            }
        }
    }

    private func loadLevel(state: inout State) -> Effect<Action> {
        state.isLoading = true
        let level = state.level
        return .run { send in
            // A JLPT level lists that level's official vocabulary — what the
            // 文字・語彙 paper actually asks. 漢検 has no word list, so it keeps
            // "words written with this 級's kanji".
            var words: [WordEntry] = []
            if level.hasPrefix("N") {
                words = (try? await dictionaryClient.jlptVocabulary(level, 3000)) ?? []
            }
            if words.isEmpty {
                words = (try? await dictionaryClient.quizWords(level, 200)) ?? []
            }
            await send(.levelLoaded(words))
        }
    }
}
