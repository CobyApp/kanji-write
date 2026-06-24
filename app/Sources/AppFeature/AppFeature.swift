import ComposableArchitecture
import KanjiListFeature

@Reducer
public struct AppFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanjiList = KanjiListFeature.State()
        public init() {}
    }

    public enum Action {
        case kanjiList(KanjiListFeature.Action)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.kanjiList, action: \.kanjiList) {
            KanjiListFeature()
        }
    }
}
