import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

@Reducer
public struct KanjiDetailFeature {
    @ObservableState
    public struct State: Equatable {
        public let kanji: Kanji
        public var glosses: [String: String] = [:]
        public var words: IdentifiedArrayOf<WordEntry> = []
        public var sentences: [ExampleSentence] = []
        public var relations: [RelationEntry] = []
        public var strokePaths: [String] = []
        public var isLoading = false
        public init(kanji: Kanji) { self.kanji = kanji }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([String: String], [WordEntry], [ExampleSentence], [RelationEntry], [String])
        case writeTapped
        case addToReview
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.date) var date

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.glosses.isEmpty else { return .none }
                state.isLoading = true
                let id = state.kanji.id
                return .run { send in
                    async let glosses = dictionaryClient.glosses(id)
                    async let words = dictionaryClient.words(id, 12)
                    async let sentences = dictionaryClient.sentences(id, 3)
                    async let relations = dictionaryClient.relations(id, 20)
                    async let strokes = dictionaryClient.strokeOrder(id)
                    await send(.loaded(
                        (try? await glosses) ?? [:],
                        (try? await words) ?? [],
                        (try? await sentences) ?? [],
                        (try? await relations) ?? [],
                        (try? await strokes) ?? []
                    ))
                }
            case let .loaded(glosses, words, sentences, relations, strokePaths):
                state.isLoading = false
                state.glosses = glosses
                state.words = IdentifiedArray(uniqueElements: words)
                state.sentences = sentences
                state.relations = relations
                state.strokePaths = strokePaths
                return .none
            case .writeTapped:
                return .none  // handled by the parent (navigation)
            case .addToReview:
                let kanjiID = state.kanji.id
                let today = Int(date.now.timeIntervalSince1970 / 86_400)
                return .run { _ in
                    var records = await reviewStore.loadRecords()
                    guard !records.contains(where: { $0.kanjiID == kanjiID }) else { return }
                    records.append(
                        ReviewRecord(kanjiID: kanjiID, box: 0, lastReviewedDay: today))
                    await reviewStore.saveRecords(records)
                }
            }
        }
    }
}
