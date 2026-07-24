import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// A kanji writing test (한자쓰기 테스트). The learner picks a JLPT level and a
/// range, then for each kanji sees only its meaning + readings and writes the
/// kanji from memory on a blank canvas. Nothing is auto-graded: at the end every
/// answer is shown next to the real kanji so the learner checks at a glance.
@Reducer
public struct PracticeFeature {
    @ObservableState
    public struct State: Equatable {
        public enum Phase: Equatable { case setup, testing, review }
        public var phase: Phase = .setup

        /// All kanji + glosses (loaded on appear).
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var glossesByID: [Int: [String: String]] = [:]

        /// Chosen level + range.
        public var level = "N5"
        public var start = 0        // 0-based index within levelKanji
        public var count = 20       // how many to test

        /// The kanji being tested this run, in study order.
        public var questions: [Kanji] = []
        public var index = 0
        /// Per-question PKDrawing data (question index → serialized drawing).
        public var drawings: [Int: Data] = [:]

        public init() {}

        /// The level's kanji in study order (JLPT → strokes → id).
        public var levelKanji: [Kanji] { studyOrder(kanji.elements, level: level) }
        public var levelCount: Int { levelKanji.count }
        /// Largest valid start index.
        public var maxStart: Int { max(0, levelCount - 1) }
        public var current: Kanji? { questions.indices.contains(index) ? questions[index] : nil }
        public var isLast: Bool { index >= questions.count - 1 }
        /// Exclusive range end (clamped) for the summary label.
        public var rangeEnd: Int { min(start + count, levelCount) }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([Kanji], [Int: [String: String]])
        case levelSelected(String)
        case setStart(Double)
        case setCount(Int)
        case startTest
        case saveDrawing(Data)   // commit the current canvas into `drawings`
        case next
        case prev
        case finish              // → review
        case restart             // → setup
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard state.kanji.isEmpty else { return .none }
                return .run { send in
                    let all = (try? await dictionaryClient.allKanji()) ?? []
                    let glosses = (try? await dictionaryClient.allGlosses()) ?? [:]
                    await send(.loaded(all, glosses))
                }

            case let .loaded(all, glosses):
                state.kanji = IdentifiedArray(uniqueElements: all)
                state.glossesByID = glosses
                return .none

            case let .levelSelected(level):
                state.level = level
                state.start = 0          // reset range to the top of the new level
                return .none

            case let .setStart(value):
                state.start = max(0, min(Int(value), state.maxStart))
                return .none

            case let .setCount(count):
                state.count = count
                return .none

            case .startTest:
                let lk = state.levelKanji
                guard !lk.isEmpty else { return .none }
                let s = min(state.start, max(0, lk.count - 1))
                let e = min(s + state.count, lk.count)
                state.questions = Array(lk[s..<e])
                state.index = 0
                state.drawings = [:]
                state.phase = .testing
                return .none

            case let .saveDrawing(data):
                state.drawings[state.index] = data
                return .none

            case .next:
                if state.index < state.questions.count - 1 { state.index += 1 }
                return .none

            case .prev:
                if state.index > 0 { state.index -= 1 }
                return .none

            case .finish:
                state.phase = .review
                return .none

            case .restart:
                state.phase = .setup
                state.questions = []
                state.drawings = [:]
                state.index = 0
                return .none
            }
        }
    }
}
