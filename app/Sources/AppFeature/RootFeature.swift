import ComposableArchitecture
import KanjiDetail
import Reminders
import Review
import SharedModels
import WritingCanvas

@Reducer
public struct RootFeature {
    /// Which sidebar item is selected (regular width). `.level` carries a `KanjiLevel.id`.
    public enum SidebarSelection: Hashable, Sendable {
        case study
        case settings
        case level(String)
    }

    /// The bottom-tab selection on compact width (iPhone).
    public enum Tab: Hashable, Sendable {
        case study
        case browse
        case settings
    }

    @ObservableState
    public struct State: Equatable {
        // Data + FSRS session + grading (loads kanji/records/today).
        public var review = ReviewFeature.State()
        // Settings (new-per-day / language / reminder).
        public var reminder = ReminderFeature.State()

        public var sidebar: SidebarSelection? = .study
        // The active bottom tab on compact width (iPhone).
        public var tab: Tab = .study
        public var searchText = ""

        // The selected kanji's info + an optional pushed canvas. On regular width
        // these fill the detail column; on compact they push onto the active tab's
        // NavigationStack.
        @Presents public var detail: KanjiDetailFeature.State?
        @Presents public var writing: KanjiWritingFeature.State?

        public init() {}
    }

    public enum Action {
        case onAppear
        case review(ReviewFeature.Action)
        case reminder(ReminderFeature.Action)
        case sidebarSelected(SidebarSelection?)
        case tabSelected(Tab)
        case searchChanged(String)
        case kanjiSelected(Kanji)
        case detail(PresentationAction<KanjiDetailFeature.Action>)
        case writing(PresentationAction<KanjiWritingFeature.Action>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.review, action: \.review) { ReviewFeature() }
        Scope(state: \.reminder, action: \.reminder) { ReminderFeature() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.review(.onAppear))

            case let .sidebarSelected(selection):
                state.sidebar = selection
                return .none

            // Switching tabs (compact) resets any pushed detail/writing so the
            // shared detail state never leaks from one tab's stack into another.
            case let .tabSelected(tab):
                state.tab = tab
                state.detail = nil
                state.writing = nil
                return .none

            case let .searchChanged(text):
                state.searchText = text
                return .none

            // Selecting a kanji (from a level list, search, or the session) opens
            // it in the detail column.
            case let .kanjiSelected(kanji):
                state.detail = KanjiDetailFeature.State(kanji: kanji)
                state.writing = nil
                return .none
            case let .review(.kanjiTapped(kanji)):
                state.detail = KanjiDetailFeature.State(kanji: kanji)
                state.writing = nil
                return .none

            // "書いて練習" inside the detail column pushes the writing canvas.
            case .detail(.presented(.writeTapped)):
                if let kanji = state.detail?.kanji {
                    state.writing = KanjiWritingFeature.State(kanji: kanji)
                }
                return .none

            case .review, .reminder, .detail, .writing:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) { KanjiDetailFeature() }
        .ifLet(\.$writing, action: \.writing) { KanjiWritingFeature() }
    }
}
