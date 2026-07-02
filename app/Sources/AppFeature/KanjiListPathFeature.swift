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
        /// Per-kanji glosses (kanjiID → lang code → meaning) for the row meanings.
        public let glosses: [Int: [String: String]]
        public init(title: String, kanji: [Kanji], glosses: [Int: [String: String]] = [:]) {
            self.title = title
            self.kanji = kanji
            self.glosses = glosses
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
