import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct KanjiDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public let kanji: Kanji
        public var glosses: [String: String] = [:]
        public var words: IdentifiedArrayOf<WordEntry> = []
        public var sentences: [ExampleSentence] = []
        public var isLoading = false
        public init(kanji: Kanji) { self.kanji = kanji }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([String: String], [WordEntry], [ExampleSentence])
        case writeTapped
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                let id = state.kanji.id
                return .run { send in
                    async let glosses = dictionaryClient.glosses(id)
                    async let words = dictionaryClient.words(id, 12)
                    async let sentences = dictionaryClient.sentences(id, 3)
                    await send(.loaded(
                        (try? await glosses) ?? [:],
                        (try? await words) ?? [],
                        (try? await sentences) ?? []
                    ))
                }
            case let .loaded(glosses, words, sentences):
                state.isLoading = false
                state.glosses = glosses
                state.words = IdentifiedArray(uniqueElements: words)
                state.sentences = sentences
                return .none
            case .writeTapped:
                return .none  // handled by the parent (navigation)
            }
        }
    }
}
