import ComposableArchitecture
import DictionaryClient
import SharedModels

/// How the browse list is narrowed.
public enum KanjiFilter: Equatable, Sendable {
    case all
    case jlpt(String)  // "N5" … "N1"
    case grade(Int)    // 1…6 (小学), 8 (中学 bucket)
}

/// Pure predicate: narrow `kanji` by `filter` then by free-text `search`
/// (matches the literal or any on/kun reading; kun-reading dots are ignored).
public func kanjiMatching(_ kanji: [Kanji], filter: KanjiFilter, search: String) -> [Kanji] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return kanji.filter { k in
        let passesFilter: Bool
        switch filter {
        case .all: passesFilter = true
        case let .jlpt(level): passesFilter = k.jlptLevel == level
        case let .grade(g): passesFilter = k.grade == g
        }
        guard passesFilter else { return false }
        guard !query.isEmpty else { return true }
        if k.literal.contains(query) { return true }
        let readings = (k.onReadings + k.kunReadings).map { $0.replacingOccurrences(of: ".", with: "") }
        return readings.contains { $0.contains(query) }
    }
}

@Reducer
public struct KanjiListFeature {
    @ObservableState
    public struct State: Equatable {
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var isLoading = false
        public var loadError: String?
        public var filter: KanjiFilter = .all
        public var searchText: String = ""
        public init() {}

        /// The kanji actually shown, after filter + search.
        public var visibleKanji: [Kanji] {
            kanjiMatching(kanji.elements, filter: filter, search: searchText)
        }
    }

    public enum Action: Equatable {
        case onAppear
        case kanjiLoaded([Kanji])
        case loadFailed(String)
        case kanjiTapped(Kanji)
        case filterChanged(KanjiFilter)
        case searchChanged(String)
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
            case let .filterChanged(filter):
                state.filter = filter
                return .none
            case let .searchChanged(text):
                state.searchText = text
                return .none
            }
        }
    }
}
