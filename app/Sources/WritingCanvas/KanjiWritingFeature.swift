import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct KanjiWritingFeature {
    @ObservableState
    public struct State: Equatable {
        public let kanji: Kanji
        public var strokePaths: [String] = []
        public var showGuide = true
        public init(kanji: Kanji) { self.kanji = kanji }
    }

    public enum Action: Equatable {
        case onAppear
        case strokesLoaded([String])
        case toggleGuide
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                let id = state.kanji.id
                return .run { send in
                    let paths = (try? await dictionaryClient.strokeOrder(id)) ?? []
                    await send(.strokesLoaded(paths))
                }
            case let .strokesLoaded(paths):
                state.strokePaths = paths
                return .none
            case .toggleGuide:
                state.showGuide.toggle()
                return .none
            }
        }
    }
}
