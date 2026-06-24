import ComposableArchitecture
import KanjiListFeature
import WritingCanvas

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanjiList = KanjiListFeature.State()
        public var path = StackState<KanjiWritingFeature.State>()
        public init() {}
    }

    public enum Action {
        case kanjiList(KanjiListFeature.Action)
        case path(StackActionOf<KanjiWritingFeature>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.kanjiList, action: \.kanjiList) {
            KanjiListFeature()
        }
        Reduce { state, action in
            switch action {
            case let .kanjiList(.kanjiTapped(kanji)):
                state.path.append(KanjiWritingFeature.State(kanji: kanji))
                return .none
            case .kanjiList, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path) {
            KanjiWritingFeature()
        }
    }
}
