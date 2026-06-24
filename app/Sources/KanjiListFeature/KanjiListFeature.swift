import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct KanjiListFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var isLoading = false
        public var loadError: String?
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case kanjiLoaded([Kanji])
        case loadFailed(String)
        case kanjiTapped(Kanji)
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                state.loadError = nil
                return .run { send in
                    do {
                        await send(.kanjiLoaded(try await dictionaryClient.allKanji()))
                    } catch {
                        await send(.loadFailed(error.localizedDescription))
                    }
                }
            case let .kanjiLoaded(kanji):
                state.isLoading = false
                state.kanji = IdentifiedArray(uniqueElements: kanji)
                return .none
            case let .loadFailed(message):
                state.isLoading = false
                state.loadError = message
                return .none
            case .kanjiTapped:
                return .none
            }
        }
    }
}
