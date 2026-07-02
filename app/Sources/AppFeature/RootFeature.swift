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
    /// The four top-level destinations (tab on iPhone, sidebar on iPad).
    public enum Destination: Hashable, Sendable {
        case home        // 오늘: glanceable progress dashboard + quick continue
        case study       // 학습: the study-mode launcher hub (learn / review / practice)
        case dictionary  // 사전: browse / search / detail / wordbook
        case settings
    }

    /// One screen on the dictionary navigation stack (kanji ↔ word ↔ writing).
    @Reducer(state: .equatable)
    public enum Path {
        case kanjiList(KanjiListPathFeature)
        case kanji(KanjiDetailFeature)
        case word(WordDetailFeature)
        case writing(KanjiWritingFeature)
    }

    /// A full-screen study session launched from Home.
    @Reducer(state: .equatable)
    public enum Session {
        case worksheet(WorksheetFeature)
        case test(TestFeature)
        case practice(PracticeFeature)
    }

    @ObservableState
    public struct State: Equatable {
        // Data source (kanji / records / today) powering Home's plan summary and
        // due count; also the dictionary's kanji list.
        public var review = ReviewFeature.State()
        // The wordbook (reached inside 사전).
        public var wordReview = WordReviewFeature.State()
        // Settings (plan / language / reminder).
        public var reminder = ReminderFeature.State()

        public var destination: Destination = .home
        public var searchText = ""
        public var path = StackState<Path.State>()
        // The active full-screen study session, if any.
        @Presents public var session: Session.State?

        public init() {}
    }

    public enum Action {
        case onAppear
        case review(ReviewFeature.Action)
        case wordReview(WordReviewFeature.Action)
        case reminder(ReminderFeature.Action)
        case destinationSelected(Destination)
        case searchChanged(String)
        case kanjiSelected(Kanji)
        case levelSelected(KanjiLevel)
        case startStudy
        case startReview
        case startPractice
        case path(StackActionOf<Path>)
        case session(PresentationAction<Session.Action>)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.review, action: \.review) { ReviewFeature() }
        Scope(state: \.wordReview, action: \.wordReview) { WordReviewFeature() }
        Scope(state: \.reminder, action: \.reminder) { ReminderFeature() }
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.review(.onAppear))

            case let .destinationSelected(destination):
                state.destination = destination
                state.path.removeAll()
                return .none

            case let .searchChanged(text):
                state.searchText = text
                return .none

            case let .kanjiSelected(kanji):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none

            case let .levelSelected(level):
                let items = kanjiIn(state.review.kanji.elements, in: level)
                state.path.append(
                    .kanjiList(KanjiListPathFeature.State(
                        title: level.label, kanji: items, glosses: state.review.glosses)))
                return .none

            case let .wordReview(.wordTapped(word)):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none

            // Home session launchers → full-screen cover.
            case .startStudy:
                state.session = .worksheet(WorksheetFeature.State())
                return .none
            case .startReview:
                state.session = .test(TestFeature.State())
                return .none
            case .startPractice:
                state.session = .practice(PracticeFeature.State())
                return .none

            // Dictionary drill routing.
            case let .path(.element(id: _, action: .kanjiList(.kanjiTapped(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .path(.element(id: _, action: .kanji(.wordTapped(word)))):
                state.path.append(.word(WordDetailFeature.State(word: word)))
                return .none
            case let .path(.element(id: _, action: .word(.kanjiTapped(kanji)))):
                state.path.append(.kanji(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .path(.element(id: id, action: .kanji(.writeTapped))):
                guard case let .kanji(detail)? = state.path[id: id] else { return .none }
                state.path.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                return .none

            case .review, .wordReview, .reminder, .path, .session:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$session, action: \.session)
    }
}
