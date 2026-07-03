import ComposableArchitecture
import KanjiListFeature
import SharedModels

/// The dictionary browse, reached as a menu inside the 학습 hub. Holds its own
/// snapshot of the kanji set + glosses (passed at push time) and delegates level
/// / kanji selection up to `RootFeature`, which pushes the next screen.
@Reducer
public struct DictionaryFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanji: [Kanji]
        public var glosses: [Int: [String: String]]
        public var searchText = ""
        public init(kanji: [Kanji], glosses: [Int: [String: String]]) {
            self.kanji = kanji
            self.glosses = glosses
        }

        public var searchResults: [Kanji] {
            let q = searchText.trimmingCharacters(in: .whitespaces)
            guard !q.isEmpty else { return [] }
            return kanji.filter { k in
                // Search the meaning across every language so 뜻 lookups work
                // regardless of the app language ("산"/"mountain" → 山).
                let meaning = glosses[k.id]?.values.joined(separator: " ")
                return searchMatches(k, searchText, meaning: meaning)
            }
        }
    }

    public enum Action: Equatable {
        case searchChanged(String)
        case levelSelected(KanjiLevel)  // delegate → parent pushes the level list
        case kanjiSelected(Kanji)       // delegate → parent pushes the kanji detail
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .searchChanged(text):
                state.searchText = text
                return .none
            case .levelSelected, .kanjiSelected:
                return .none  // handled by the parent (navigation)
            }
        }
    }
}
