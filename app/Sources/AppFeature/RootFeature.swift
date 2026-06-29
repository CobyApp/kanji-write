import ComposableArchitecture
import KanjiDetail
import Reminders
import Review
import SharedModels
import WritingCanvas

@Reducer
public struct RootFeature {
    /// Which sidebar item is selected. `.level` carries a `KanjiLevel.id`.
    public enum SidebarSelection: Hashable, Sendable {
        case study
        case settings
        case level(String)
    }

    @ObservableState
    public struct State: Equatable {
        // Data + FSRS session + grading (loads kanji/records/today).
        public var review = ReviewFeature.State()
        // Settings (classification / new-per-day / language / reminder).
        public var reminder = ReminderFeature.State()

        public var sidebar: SidebarSelection? = .study
        public var searchText = ""

        // Detail column: the selected kanji's info + an optional pushed canvas.
        public var detail: KanjiDetailFeature.State?
        @Presents public var writing: KanjiWritingFeature.State?

        public init() {}
    }

    public enum Action {
        case onAppear
        case review(ReviewFeature.Action)
        case reminder(ReminderFeature.Action)
        case sidebarSelected(SidebarSelection?)
        case searchChanged(String)
        case kanjiSelected(Kanji)
        case detail(KanjiDetailFeature.Action)
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
            case .detail(.writeTapped):
                if let kanji = state.detail?.kanji {
                    state.writing = KanjiWritingFeature.State(kanji: kanji)
                }
                return .none

            case .review, .reminder, .detail, .writing:
                return .none
            }
        }
        .ifLet(\.detail, action: \.detail) { KanjiDetailFeature() }
        .ifLet(\.$writing, action: \.writing) { KanjiWritingFeature() }
    }
}
