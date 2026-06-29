import ComposableArchitecture
import KanjiDetail
import Reminders
import Review
import StudyPlan
import WritingCanvas

@Reducer
public struct RootFeature {
    @ObservableState
    public struct State: Equatable {
        public var selectedTab: Tab = .browse
        public var browse = AppFeature.State()
        public var plan = StudyPlanFeature.State()
        public var planPath = StackState<Path.State>()
        public var review = ReviewFeature.State()
        public var reminder = ReminderFeature.State()
        public init() {}

        public enum Tab: Equatable { case browse, study, settings }
    }

    // StackActionOf<Path> is not Equatable, so Action intentionally omits Equatable.
    public enum Action {
        case tabSelected(State.Tab)
        case browse(AppFeature.Action)
        case plan(StudyPlanFeature.Action)
        case planPath(StackActionOf<Path>)
        case review(ReviewFeature.Action)
        case reminder(ReminderFeature.Action)
    }

    public init() {}

    public var body: some ReducerOf<Self> {
        Scope(state: \.browse, action: \.browse) { AppFeature() }
        Scope(state: \.plan, action: \.plan) { StudyPlanFeature() }
        Scope(state: \.review, action: \.review) {
            ReviewFeature()
        }
        Scope(state: \.reminder, action: \.reminder) { ReminderFeature() }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
            case let .plan(.kanjiTapped(kanji)):
                state.planPath.append(.detail(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .review(.kanjiTapped(kanji)):
                state.planPath.append(.detail(KanjiDetailFeature.State(kanji: kanji)))
                return .none
            case let .planPath(.element(id: id, action: .detail(.writeTapped))):
                if case let .detail(detail) = state.planPath[id: id] {
                    state.planPath.append(.writing(KanjiWritingFeature.State(kanji: detail.kanji)))
                }
                return .none
            case .browse, .plan, .planPath, .review, .reminder:
                return .none
            }
        }
        .forEach(\.planPath, action: \.planPath)
    }
}
