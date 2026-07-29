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
        ///
        /// Driven by the exam's own level list rather than a literal, so a level
        /// that gains 四字熟語 later shows up on its own — 準1級 and 1級 had data
        /// and no chip, because the list predated them.
        public var levels: [String] {
            let present = Set(all.map(\.level))
            return ExamType.kanken.levels.filter(present.contains)
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
        public var yoji: Yojijukugo
        public var siblings: [Yojijukugo]
        public var index: Int
        public var kanji: [Kanji] = []

        public init(yoji: Yojijukugo, siblings: [Yojijukugo] = [], index: Int = 0) {
            self.yoji = yoji
            self.siblings = siblings.isEmpty ? [yoji] : siblings
            self.index = siblings.isEmpty ? 0 : index
        }

        public var hasPrev: Bool { index > 0 }
        public var hasNext: Bool { index < siblings.count - 1 }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([Kanji])
        case showSibling(delta: Int)
        case kanjiTapped(Kanji)   // delegate → parent pushes the kanji detail
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.kanji.isEmpty else { return .none }
                return load(state.yoji.yoji)
            case let .loaded(kanji):
                state.kanji = kanji
                return .none
            case let .showSibling(delta):
                let new = state.index + delta
                guard state.siblings.indices.contains(new) else { return .none }
                state.index = new
                state.yoji = state.siblings[new]
                state.kanji = []
                return load(state.yoji.yoji)
            case .kanjiTapped:
                return .none  // handled by the parent (navigation)
            }
        }
    }

    private func load(_ yoji: String) -> Effect<Action> {
        .run { send in
            await send(.loaded((try? await dictionaryClient.kanjiForYoji(yoji)) ?? []))
        }
    }
}
