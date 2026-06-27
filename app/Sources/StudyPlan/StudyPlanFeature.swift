import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct StudyPlanFeature {
    @ObservableState
    public struct State: Equatable {
        public var plan: StudyPlan?
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var isLoading = false
        public var today: Int = 0
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case loaded(StudyPlan?, [Kanji], Int)
        case createPlan(days: Int)
        case markDone(Int)
        case kanjiTapped(Kanji)
    }

    @Dependency(\.userStore) var userStore
    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.kanji.isEmpty else { return .none }
                state.isLoading = true
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    async let plan = userStore.loadPlan()
                    let kanji = (try? await dictionaryClient.allKanji()) ?? []
                    await send(.loaded(await plan, kanji, today))
                }
            case let .loaded(plan, kanji, today):
                state.isLoading = false
                state.plan = plan
                state.kanji = IdentifiedArray(uniqueElements: kanji)
                state.today = today
                return .none
            case let .createPlan(days):
                let assignments = PlanScheduler.distribute(
                    kanjiIDs: state.kanji.map(\.id), days: days)
                let today = state.today
                let plan = StudyPlan(axisLabel: "学年", durationDays: days,
                                     dayAssignments: assignments, startDay: today)
                state.plan = plan
                return .run { _ in await userStore.savePlan(plan) }
            case let .markDone(id):
                guard var plan = state.plan else { return .none }
                plan.completedKanjiIDs.insert(id)
                state.plan = plan
                return .run { [plan] _ in await userStore.savePlan(plan) }
            case .kanjiTapped:
                return .none
            }
        }
    }
}
