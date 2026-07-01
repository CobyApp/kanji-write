import ComposableArchitecture
import SharedModels

/// A pushed kanji list (one JLPT level's kanji), as a navigation-stack element.
/// Stateless beyond its items; taps delegate up to the parent, which pushes the
/// selected kanji's detail.
@Reducer
public struct KanjiListPathFeature {
    @ObservableState
    public struct State: Equatable {
        public let title: String
        public let kanji: [Kanji]
        public init(title: String, kanji: [Kanji]) {
            self.title = title
            self.kanji = kanji
        }
    }

    public enum Action: Equatable {
        case kanjiTapped(Kanji)  // delegate → parent pushes the kanji detail
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { _, _ in .none }
    }
}
