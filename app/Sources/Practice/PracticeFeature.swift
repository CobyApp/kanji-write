import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

/// Free-repetition writing notebook (한자노트). The learner picks a kanji and
/// writes it many times over a faint stroke-order guide. Ungraded muscle-memory
/// practice — no FSRS, no recognition.
@Reducer
public struct PracticeFeature {
    @ObservableState
    public struct State: Equatable {
        /// All kanji available to pick from (loaded on appear).
        public var kanji: IdentifiedArrayOf<Kanji> = []
        /// The kanji currently being practiced, if any.
        public var selected: Kanji?
        /// Faint stroke-order guide (KanjiVG path `d` strings) for `selected`.
        public var strokePaths: [String] = []
        /// Whether the faint guide is shown behind each cell.
        public var showGuide = true
        /// Incremented to force every canvas cell to reset (clear-all).
        public var clearToken = 0
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case kanjiLoaded([Kanji])
        case kanjiSelected(Kanji)
        case strokesLoaded([String])
        case toggleGuide
        case clearAll
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Reload only when empty so re-appearing keeps the selection.
                guard state.kanji.isEmpty else { return .none }
                return .run { send in
                    let all = (try? await dictionaryClient.allKanji()) ?? []
                    await send(.kanjiLoaded(all))
                }

            case let .kanjiLoaded(all):
                state.kanji = IdentifiedArray(uniqueElements: all)
                // Default to the first kanji so the notebook is usable immediately.
                if state.selected == nil, let first = all.first {
                    return .send(.kanjiSelected(first))
                }
                return .none

            case let .kanjiSelected(kanji):
                state.selected = kanji
                state.strokePaths = []
                state.clearToken += 1  // fresh page when switching kanji
                let id = kanji.id
                return .run { send in
                    let paths = (try? await dictionaryClient.strokeOrder(id)) ?? []
                    await send(.strokesLoaded(paths))
                }

            case let .strokesLoaded(paths):
                state.strokePaths = paths
                return .none

            case .toggleGuide:
                state.showGuide.toggle()
                return .none

            case .clearAll:
                state.clearToken += 1
                return .none
            }
        }
    }
}
