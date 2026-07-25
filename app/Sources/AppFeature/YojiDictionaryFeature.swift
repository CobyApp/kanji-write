import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

/// The 사자성어(四字熟語) dictionary browse: the full idiom list with a per-級 filter
/// and free-text search over idiom / reading / meaning. Loaded once; filtering is
/// client-side (the dataset is small).
@Reducer
public struct YojiDictionaryFeature {
    @ObservableState
    public struct State: Equatable {
        public var all: [Yojijukugo] = []
        public var searchText = ""
        /// nil = all levels; otherwise a 漢検 級 filter.
        public var level: String?
        public var isLoading = false

        public init() {}

        public var isSearching: Bool {
            !searchText.trimmingCharacters(in: .whitespaces).isEmpty
        }

        /// The idioms to show: search overrides the 級 filter.
        public var visible: [Yojijukugo] {
            if isSearching {
                let q = searchText.trimmingCharacters(in: .whitespaces)
                return all.filter {
                    $0.yoji.contains(q) || $0.reading.contains(q)
                        || ($0.meaningKo?.contains(q) ?? false)
                        || ($0.meaningJa?.contains(q) ?? false)
                }
            }
            guard let level else { return all }
            return all.filter { $0.level == level }
        }

        /// The 級 present in the data, in exam order (for the filter chips).
        public var levels: [String] {
            let order = ["5級", "4級", "3級", "準2級", "2級"]
            let present = Set(all.map(\.level))
            return order.filter(present.contains)
        }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([Yojijukugo])
        case searchChanged(String)
        case levelSelected(String?)
        case yojiSelected(Yojijukugo)   // delegate → parent pushes the idiom detail
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.all.isEmpty else { return .none }
                state.isLoading = true
                return .run { send in
                    let all = (try? await dictionaryClient.allYojijukugo()) ?? []
                    await send(.loaded(all))
                }
            case let .loaded(all):
                state.isLoading = false
                state.all = all
                return .none
            case let .searchChanged(text):
                state.searchText = text
                return .none
            case let .levelSelected(level):
                state.level = level
                return .none
            case .yojiSelected:
                return .none  // handled by the parent (navigation)
            }
        }
    }
}

/// The 四字熟語 detail: the idiom with reading + meaning, and its constituent kanji
/// as tappable cards that drill into the kanji detail (like the word detail).
@Reducer
public struct YojiDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public let yoji: Yojijukugo
        public var kanji: [Kanji] = []
        public init(yoji: Yojijukugo) { self.yoji = yoji }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([Kanji])
        case kanjiTapped(Kanji)   // delegate → parent pushes the kanji detail
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.kanji.isEmpty else { return .none }
                let yoji = state.yoji.yoji
                return .run { send in
                    await send(.loaded((try? await dictionaryClient.kanjiForYoji(yoji)) ?? []))
                }
            case let .loaded(kanji):
                state.kanji = kanji
                return .none
            case .kanjiTapped:
                return .none  // handled by the parent (navigation)
            }
        }
    }
}
