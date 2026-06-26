import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import WritingCanvas

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanjiList = KanjiListFeature.State()
        public var path = StackState<Path.State>()
        public init() {}
    }

    // StackActionOf<Path> is not Equatable, so Action intentionally omits Equatable.
    public enum Action {
        case kanjiList(KanjiListFeature.Action)
        case path(StackActionOf<Path>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.kanjiList, action: \.kanjiList) {
            KanjiListFeature()
        }
        Reduce { state, action in
            switch action {
            case let .kanjiList(.kanjiTapped(kanji)):
                state.path.append(.detail(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .path(.element(id: id, action: .detail(.writeTapped))):
                if case let .detail(detail) = state.path[id: id] {
                    state.path.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                }
                return .none
            case .kanjiList, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
