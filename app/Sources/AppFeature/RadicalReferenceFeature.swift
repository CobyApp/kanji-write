import ComposableArchitecture
import DictionaryClient
import SharedModels

/// The 부수(部首) reference: browse the 214 Kangxi radicals (glyph, 部首名,
/// meaning in the app language, kanji count) and tap one to see the kanji that
/// use it. The drill is handled by the parent (RootFeature), which has the
/// kanji list.
@Reducer
public struct RadicalReferenceFeature {
    @ObservableState
    public struct State: Equatable {
        public var radicals: [RadicalEntry] = []
        public var isLoading = false
        public var searchText = ""

        public init() {}

        public var isSearching: Bool {
            !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        }

        /// Radicals matching the search (glyph, 部首名, a meaning, or the number),
        /// otherwise all of them in Kangxi order.
        public var visible: [RadicalEntry] {
            guard isSearching else { return radicals }
            let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
            return radicals.filter { r in
                r.glyph.contains(q) || r.nameJa.contains(q) || "\(r.number)" == q
                    || r.meaningJa.lowercased().contains(q)
                    || r.meaningKo.lowercased().contains(q)
                    || r.meaningZh.lowercased().contains(q)
                    || r.meaningEn.lowercased().contains(q)
            }
        }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([RadicalEntry])
        case searchChanged(String)
        case radicalTapped(RadicalEntry)   // delegate → parent pushes the kanji list
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.radicals.isEmpty else { return .none }
                state.isLoading = true
                return .run { send in
                    let radicals = (try? await dictionaryClient.radicals()) ?? []
                    await send(.loaded(radicals))
                }

            case let .loaded(radicals):
                state.isLoading = false
                state.radicals = radicals
                return .none

            case let .searchChanged(text):
                state.searchText = text
                return .none

            case .radicalTapped:
                return .none   // the parent drills into the kanji
            }
        }
    }
}
