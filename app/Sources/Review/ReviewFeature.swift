import ComposableArchitecture
import DictionaryClient
import SharedModels

@Reducer
public struct ReviewFeature {
    @ObservableState
    public struct State: Equatable {
        public var records: IdentifiedArrayOf<ReviewRecord> = []
        public var kanji: IdentifiedArrayOf<Kanji> = []
        /// Every kanji's glosses (kanjiID → lang code → meaning), for list rows.
        public var glosses: [Int: [String: String]] = [:]
        public var today: Int = 0
        public var isLoading = false
        public init() {}
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([ReviewRecord], [Kanji], Int, [Int: [String: String]])
        case reloadRecords   // re-read SRS records from disk (after a study session)
        case recordsReloaded([ReviewRecord], Int)
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
                    async let glossesTask = try? await dictionaryClient.allGlosses()
                    let kanji = (try? await dictionaryClient.allKanji()) ?? []
                    let glosses = await glossesTask ?? [:]
                    await send(.loaded(await records, kanji, today, glosses))
                }
            case let .loaded(records, kanji, today, glosses):
                state.isLoading = false
                state.records = IdentifiedArray(uniqueElements: records)
                state.kanji = IdentifiedArray(uniqueElements: kanji)
                state.glosses = glosses
                state.today = today
                return .none

            // Re-read records from disk (kanji/glosses are static) so home
            // progress reflects a just-finished study/quiz session.
            case .reloadRecords:
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    await send(.recordsReloaded(await reviewStore.loadRecords(), today))
                }
            case let .recordsReloaded(records, today):
                state.records = IdentifiedArray(uniqueElements: records)
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
