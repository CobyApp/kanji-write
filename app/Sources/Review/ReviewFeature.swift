import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct ReviewFeature {
    @ObservableState
    public struct State: Equatable {
        public var records: IdentifiedArrayOf<ReviewRecord> = []
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var today: Int = 0
        public var isLoading = false
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([ReviewRecord], [Kanji], Int)
        case grade(kanjiID: Int, grade: Grade)
        case kanjiTapped(Kanji)
    }

    @Dependency(\.reviewStore) var reviewStore
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
                    async let records = reviewStore.loadRecords()
                    let kanji = (try? await dictionaryClient.allKanji()) ?? []
                    await send(.loaded(await records, kanji, today))
                }
            case let .loaded(records, kanji, today):
                state.isLoading = false
                state.records = IdentifiedArray(uniqueElements: records)
                state.kanji = IdentifiedArray(uniqueElements: kanji)
                state.today = today
                return .none
            case let .grade(kanjiID, grade):
                let today = state.today
                let updated: ReviewRecord
                if let rec = state.records[id: kanjiID] {
                    let result = FSRS.schedule(
                        state: MemoryState(stability: rec.stability, difficulty: rec.difficulty),
                        grade: grade, elapsedDays: today - rec.lastReviewedDay)
                    updated = ReviewRecord(
                        kanjiID: kanjiID, stability: result.state.stability,
                        difficulty: result.state.difficulty, due: today + result.intervalDays,
                        lastReviewedDay: today, lapses: rec.lapses + (grade == .again ? 1 : 0),
                        reps: rec.reps + 1)
                } else {
                    let result = FSRS.schedule(state: nil, grade: grade, elapsedDays: 0)
                    updated = ReviewRecord(
                        kanjiID: kanjiID, stability: result.state.stability,
                        difficulty: result.state.difficulty, due: today + result.intervalDays,
                        lastReviewedDay: today, lapses: grade == .again ? 1 : 0, reps: 1)
                }
                state.records[id: kanjiID] = updated
                let all = Array(state.records)
                return .run { _ in await reviewStore.saveRecords(all) }
            case .kanjiTapped:
                return .none
            }
        }
    }
}
