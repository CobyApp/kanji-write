import ComposableArchitecture
import KanjiDetail
import KanjiListFeature
import Practice
import Reminders
import Review
import SharedModels
import TestMode
import Worksheet
import WritingCanvas

@Reducer
public struct RootFeature {
    /// Which sidebar item is selected (regular width). `.level` carries a `KanjiLevel.id`.
    public enum SidebarSelection: Hashable, Sendable {
        case study     // 学習: worksheet for new kanji
        case practice  // 練習: free repetition writing
        case test      // テスト: FSRS flashcard quiz
        case words
        case settings
        case level(String)
    }

    /// The bottom-tab selection on compact width (iPhone).
    public enum Tab: Hashable, Sendable {
        case study     // worksheet
        case practice
        case test
        case browse
        case settings
    }

    /// One screen on the navigation stack. Kanji ↔ word drilling appends to the
    /// stack, so it can go arbitrarily deep.
    @Reducer(state: .equatable)
    public enum Path {
        case kanjiList(KanjiListPathFeature)
        case kanji(KanjiDetailFeature)
        case word(WordDetailFeature)
        case writing(KanjiWritingFeature)
    }

    @ObservableState
    public struct State: Equatable {
        // Data + FSRS session + grading (loads kanji/records/today).
        public var review = ReviewFeature.State()
        // The wordbook + its own (word-only) FSRS review.
        public var wordReview = WordReviewFeature.State()
        // The three study modes.
        public var worksheet = WorksheetFeature.State()
        public var practice = PracticeFeature.State()
        public var test = TestFeature.State()
        // Settings (new-per-day / language / reminder).
        public var reminder = ReminderFeature.State()

        public var sidebar: SidebarSelection? = .study
        // The active bottom tab on compact width (iPhone).
        public var tab: Tab = .study
        public var searchText = ""

        // The detail navigation stack (kanji / word / writing / a level's list).
        // On regular width it's the split view's detail column; on compact it's
        // the active tab's NavigationStack.
        public var path = StackState<Path.State>()

        public init() {}
    }

    public enum Action {
        case onAppear
        case review(ReviewFeature.Action)
        case wordReview(WordReviewFeature.Action)
        case worksheet(WorksheetFeature.Action)
        case practice(PracticeFeature.Action)
        case test(TestFeature.Action)
        case reminder(ReminderFeature.Action)
        case sidebarSelected(SidebarSelection?)
        case tabSelected(Tab)
        case searchChanged(String)
        case kanjiSelected(Kanji)   // open a kanji as a fresh stack root
        case levelSelected(KanjiLevel)  // open a level's kanji list (compact browse)
        case path(StackActionOf<Path>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.review, action: \.review) { ReviewFeature() }
        Scope(state: \.wordReview, action: \.wordReview) { WordReviewFeature() }
        Scope(state: \.worksheet, action: \.worksheet) { WorksheetFeature() }
        Scope(state: \.practice, action: \.practice) { PracticeFeature() }
        Scope(state: \.test, action: \.test) { TestFeature() }
        Scope(state: \.reminder, action: \.reminder) { ReminderFeature() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.review(.onAppear))

            case let .sidebarSelected(selection):
                state.sidebar = selection
                state.path.removeAll()  // switching section resets any pushed detail
                return .none

            // Switching tabs (compact) resets the stack so it never leaks from
            // one tab into another.
            case let .tabSelected(tab):
                state.tab = tab
                state.path.removeAll()
                return .none

            case let .searchChanged(text):
                state.searchText = text
                return .none

            // Selecting a kanji (list / search / session) pushes its detail.
            case let .kanjiSelected(kanji):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .review(.kanjiTapped(kanji)):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none

            // Tapping a word in the 単語 hub pushes its detail.
            case let .wordReview(.wordTapped(word)):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none

            // Opening a level's kanji list (compact 一覧 tab).
            case let .levelSelected(level):
                let items = kanjiIn(state.review.kanji.elements, in: level)
                state.path = StackState([
                    .kanjiList(KanjiListPathFeature.State(title: level.label, kanji: items))
                ])
                return .none

            // A kanji tapped inside a pushed level list → push its detail.
            case let .path(.element(id: _, action: .kanjiList(.kanjiTapped(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none

            // A word tapped inside a kanji detail → push the word detail.
            case let .path(.element(id: _, action: .kanji(.wordTapped(word)))):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none

            // A kanji tapped inside a word detail → push the kanji detail.
            case let .path(.element(id: _, action: .word(.kanjiTapped(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none

            // "書いて練習" inside a kanji detail → push the writing canvas.
            case let .path(.element(id: id, action: .kanji(.writeTapped))):
                guard case let .kanji(detail)? = state.path[id: id] else { return .none }
                state.path.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                return .none

            case .review, .wordReview, .worksheet, .practice, .test, .reminder, .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
