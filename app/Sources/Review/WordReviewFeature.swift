import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

/// The word wordbook + its FSRS review, kept entirely separate from the kanji
/// engine (own store file). Saved words are the ones with a record; the session
/// is the saved words whose `due` has arrived. No new-per-day cap — the learner
/// curates the wordbook by saving words from word detail.
@Reducer
public struct WordReviewFeature {
    @ObservableState
    public struct State: Equatable {
        public var records: IdentifiedArrayOf<ReviewRecord> = []
        public var words: IdentifiedArrayOf<WordEntry> = []
        public var today: Int = 0
        public var isLoading = false
        public init() {}

        /// Saved words due for review (soonest due, then hardest), by word id.
        public var dueIDs: [Int] {
            records.filter { $0.due <= today }
                .sorted { ($0.due, $0.difficulty) < ($1.due, $1.difficulty) }
                .map(\.kanjiID)
        }
        /// Every saved word id (the wordbook), most-recently-added last.
        public var savedIDs: [Int] { records.map(\.kanjiID) }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([ReviewRecord], [WordEntry], Int)
        case grade(wordID: Int, grade: Grade)
        case wordTapped(WordEntry)  // delegate → parent pushes the word detail
    }

    @Dependency(\.wordReviewStore) var wordReviewStore
    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Reload each appearance so words just saved elsewhere show up.
                state.isLoading = true
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { send in
                    let records = await wordReviewStore.loadRecords()
                    var words: [WordEntry] = []
                    for record in records {
                        if let word = try? await dictionaryClient.word(record.kanjiID) {
                            words.append(word)
                        }
                    }
                    await send(.loaded(records, words, today))
                }
            case let .loaded(records, words, today):
                state.isLoading = false
                state.records = IdentifiedArray(uniqueElements: records)
                state.words = IdentifiedArray(uniqueElements: words)
                state.today = today
                return .none
            case let .grade(wordID, grade):
                let today = state.today
                let updated: ReviewRecord
                if let rec = state.records[id: wordID] {
                    let result = FSRS.schedule(
                        state: MemoryState(stability: rec.stability, difficulty: rec.difficulty),
                        grade: grade, elapsedDays: today - rec.lastReviewedDay)
                    updated = ReviewRecord(
                        kanjiID: wordID, stability: result.state.stability,
                        difficulty: result.state.difficulty, due: today + result.intervalDays,
                        lastReviewedDay: today, lapses: rec.lapses + (grade == .again ? 1 : 0),
                        reps: rec.reps + 1)
                } else {
                    let result = FSRS.schedule(state: nil, grade: grade, elapsedDays: 0)
                    updated = ReviewRecord(
                        kanjiID: wordID, stability: result.state.stability,
                        difficulty: result.state.difficulty, due: today + result.intervalDays,
                        lastReviewedDay: today, lapses: grade == .again ? 1 : 0, reps: 1)
                }
                state.records[id: wordID] = updated
                let all = Array(state.records)
                return .run { _ in await wordReviewStore.saveRecords(all) }
            case .wordTapped:
                return .none  // handled by the parent (navigation)
            }
        }
    }
}
