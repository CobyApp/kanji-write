import ComposableArchitecture
import DictionaryClient
import Foundation
import SharedModels

/// A multiple-choice reading quiz: show a word, pick its correct kana reading
/// from four options. Questions come from the target JLPT level (or the saved
/// wordbook); wrong options are drawn from other words' readings.
@Reducer
public struct QuizFeature {
    @ObservableState
    public struct State: Equatable {
        public var level: String
        public var useWordbook: Bool
        /// Saved words (passed in by the parent) used when `useWordbook` is on.
        public var wordbookWords: [WordEntry]
        public var questions: [WordEntry] = []
        public var readingPool: [String] = []
        public var index = 0
        public var options: [String] = []
        public var chosen: String?
        public var correctCount = 0
        public var isLoading = false

        public init(level: String, useWordbook: Bool = false, wordbookWords: [WordEntry] = []) {
            self.level = level
            self.useWordbook = useWordbook
            self.wordbookWords = wordbookWords
        }

        public var current: WordEntry? {
            questions.indices.contains(index) ? questions[index] : nil
        }
        public var isFinished: Bool { !questions.isEmpty && index >= questions.count }
        public var answered: Bool { chosen != nil }
        public var total: Int { questions.count }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([WordEntry])
        case setWordbook(Bool)
        case chose(String)
        case next
        case restart
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear, .restart:
                state.isLoading = true
                let level = state.level
                return .run { send in
                    let pool = (try? await dictionaryClient.quizWords(level, 200)) ?? []
                    await send(.loaded(pool))
                }

            case let .loaded(pool):
                state.isLoading = false
                // Questions: from the wordbook or the level pool — deduped, valid,
                // shuffled, capped at 20.
                let source = state.useWordbook ? state.wordbookWords : pool
                var seen = Set<Int>()
                var qs = source.filter { word in
                    guard !word.surface.isEmpty, !word.reading.isEmpty else { return false }
                    return seen.insert(word.id).inserted
                }
                withRandomNumberGenerator { qs.shuffle(using: &$0) }
                state.questions = Array(qs.prefix(20))
                // Distractor readings: every reading in the level pool + wordbook.
                let readings = Set((pool + state.wordbookWords).map(\.reading))
                    .filter { !$0.isEmpty }
                state.readingPool = Array(readings)
                state.index = 0
                state.correctCount = 0
                buildOptions(&state)
                return .none

            case let .setWordbook(useWordbook):
                state.useWordbook = useWordbook
                return .send(.onAppear)

            case let .chose(reading):
                guard !state.answered else { return .none }
                state.chosen = reading
                if reading == state.current?.reading { state.correctCount += 1 }
                return .none

            case .next:
                state.index += 1
                if !state.isFinished { buildOptions(&state) }
                return .none
            }
        }
    }

    /// Builds the 4 shuffled options for the current question (correct + up to 3
    /// distinct distractor readings) and clears the previous choice.
    private func buildOptions(_ state: inout State) {
        state.chosen = nil
        guard let correct = state.current?.reading else {
            state.options = []
            return
        }
        var distractors = state.readingPool.filter { $0 != correct }
        withRandomNumberGenerator { distractors.shuffle(using: &$0) }
        var options = [correct] + distractors.prefix(3)
        withRandomNumberGenerator { options.shuffle(using: &$0) }
        state.options = options
    }
}
