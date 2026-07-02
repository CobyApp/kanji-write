import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
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
        /// The JLPT level whose kanji are shown in the picker strip.
        public var level = "N5"
        /// The kanji currently being practiced, if any.
        public var selected: Kanji?

        /// The kanji shown in the picker, filtered to `level` and in the same
        /// order as study / the dictionary (JLPT → stroke count → id).
        public var levelKanji: [Kanji] {
            studyOrder(kanji.elements, level: level)
        }
        /// Faint stroke-order guide (KanjiVG path `d` strings) for `selected`.
        public var strokePaths: [String] = []
        /// Whether the faint guide is shown behind each cell.
        public var showGuide = true
        /// Incremented to force every canvas cell to reset (clear-all).
        public var clearToken = 0
        /// How many write cells the notebook shows (grows by 10 on demand).
        public var cellCount = 10
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear(selectedID: Int?)
        case kanjiLoaded([Kanji], selectedID: Int?)
        case kanjiSelected(Kanji)
        case levelSelected(String)
        case strokesLoaded([String])
        case toggleGuide
        case clearAll
        case addCells
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(selectedID):
                // Reload only when empty so re-appearing keeps the selection.
                guard state.kanji.isEmpty else { return .none }
                return .run { send in
                    let all = (try? await dictionaryClient.allKanji()) ?? []
                    await send(.kanjiLoaded(all, selectedID: selectedID))
                }

            case let .kanjiLoaded(all, selectedID):
                state.kanji = IdentifiedArray(uniqueElements: all)
                guard state.selected == nil else { return .none }
                // Restore the last-practiced kanji (jump to its level); otherwise
                // default to the first kanji of the current level.
                if let id = selectedID, let restored = state.kanji[id: id] {
                    state.level = restored.jlptLevel ?? state.level
                    return .send(.kanjiSelected(restored))
                }
                if let first = state.levelKanji.first {
                    return .send(.kanjiSelected(first))
                }
                return .none

            case let .levelSelected(level):
                state.level = level
                // Jump the notebook to the first kanji of the newly picked level.
                if let first = state.levelKanji.first {
                    return .send(.kanjiSelected(first))
                }
                return .none

            case let .kanjiSelected(kanji):
                state.selected = kanji
                state.strokePaths = []
                state.clearToken += 1  // fresh page when switching kanji
                state.cellCount = 10   // reset the notebook length
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

            case .addCells:
                state.cellCount += 10
                return .none
            }
        }
    }
}
