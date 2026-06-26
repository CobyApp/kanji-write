import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

@Reducer
public struct ReviewFeature {
    /// How many never-seen kanji to introduce per session.
    static let newCardLimit = 10

    @ObservableState
    public struct State: Equatable {
        public var records: IdentifiedArrayOf<ReviewRecord> = []
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var today: Int = 0
        public var isLoading = false
        public init() {}

        /// Tracked cards that are due, plus a few brand-new kanji.
        public var dueKanji: [Kanji] {
            let dueTracked = kanji.filter { k in
                guard let r = records[id: k.id] else { return false }
                return srsIsDue(box: r.box, lastReviewedDay: r.lastReviewedDay, today: today)
            }
            let newCards = kanji.filter { records[id: $0.id] == nil }
                .prefix(ReviewFeature.newCardLimit)
            return dueTracked + Array(newCards)
        }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([ReviewRecord], [Kanji], Int)
        case grade(kanjiID: Int, correct: Bool)
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
            case let .grade(kanjiID, correct):
                let currentBox = state.records[id: kanjiID]?.box ?? 0
                let record = ReviewRecord(
                    kanjiID: kanjiID,
                    box: srsAdvance(box: currentBox, correct: correct),
                    lastReviewedDay: state.today)
                state.records[id: kanjiID] = record
                let all = Array(state.records)
                return .run { _ in await reviewStore.saveRecords(all) }
            }
        }
    }
}
