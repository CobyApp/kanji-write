import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// A writing test. The learner picks a level and a range, then for each item
/// sees only its meaning + readings and writes the answer from memory on a blank
/// canvas. Nothing is auto-graded: at the end every answer is shown next to the
/// real one so the learner checks at a glance.
///
/// Two modes share all of this. 한자쓰기 tests a single kanji; 단어쓰기 tests a
/// whole word, which is the harder and more practical skill — knowing 学 and 校
/// separately is not the same as producing 学校 on demand.

/// One thing to write: the answer, and the clues shown in its place.
public struct PracticeItem: Equatable, Identifiable {
    public let id: Int
    /// What the learner has to write — a kanji, or a whole word.
    public let answer: String
    /// Meanings by language key, shown instead of the answer.
    public let glosses: [String: String]
    /// Kana reading, shown for words (a kanji shows 음/훈 lines instead).
    public let reading: String?
    public let onReadings: [String]
    public let kunReadings: [String]
    /// Set only when the answer is a single kanji, so the 힌트 can show its
    /// stroke order. A multi-kanji word has no single stroke-order animation.
    public let strokeOrderKanjiID: Int?

    public init(id: Int, answer: String, glosses: [String: String], reading: String? = nil,
                onReadings: [String] = [], kunReadings: [String] = [],
                strokeOrderKanjiID: Int? = nil) {
        self.id = id
        self.answer = answer
        self.glosses = glosses
        self.reading = reading
        self.onReadings = onReadings
        self.kunReadings = kunReadings
        self.strokeOrderKanjiID = strokeOrderKanjiID
    }
}
@Reducer
public struct PracticeFeature {
    @ObservableState
    public struct State: Equatable {
        public enum Phase: Equatable { case setup, testing, review }
        /// 한자쓰기 vs 단어쓰기 — same flow, different thing to write.
        public enum Mode: String, Equatable, CaseIterable { case kanji, word }
        public var phase: Phase = .setup
        public var mode: Mode = .kanji

        /// All kanji + glosses (loaded on appear).
        public var kanji: IdentifiedArrayOf<Kanji> = []
        public var glossesByID: [Int: [String: String]] = [:]
        /// Level vocabulary for 단어쓰기, reloaded when the level changes.
        public var words: [WordEntry] = []

        /// Chosen level + range.
        public var level = "N5"
        public var start = 0        // 0-based index within levelKanji
        public var count = 20       // how many to test

        /// What is being tested this run, in study order.
        public var questions: [PracticeItem] = []
        public var index = 0
        /// Per-question PKDrawing data (question index → serialized drawing).
        public var drawings: [Int: Data] = [:]
        /// 힌트: the answer kanji and its stroke order, hidden until asked for.
        /// Reset on every navigation so the next question starts covered.
        public var hintShown = false
        public var hintStrokes: [String] = []

        public init() {}

        /// The level's kanji in study order (JLPT → strokes → id).
        public var levelKanji: [Kanji] {
            studyOrder(kanji.elements, exam: ExamType.current, level: level)
                .filter(\.hasVerifiedStrokeOrder)
        }
        /// Every item available at this level, in the current mode.
        public var levelItems: [PracticeItem] {
            switch mode {
            case .kanji:
                return levelKanji.map { k in
                    PracticeItem(
                        id: k.id, answer: k.literal, glosses: glossesByID[k.id] ?? [:],
                        onReadings: k.onReadings, kunReadings: k.kunReadings,
                        strokeOrderKanjiID: k.id)
                }
            case .word:
                // Single-kanji entries would just be the 한자쓰기 test again.
                return words
                    .filter { $0.surface.count >= 2 }
                    .map { w in
                        PracticeItem(
                            id: w.id, answer: w.surface,
                            glosses: [
                                "ko": w.meaningKo, "ja": w.meaningJa,
                                "zh": w.meaningZh, "en": w.meaningEn,
                            ].compactMapValues { $0 },
                            reading: w.reading)
                    }
            }
        }
        public var levelCount: Int { levelItems.count }
        /// Largest valid start index.
        public var maxStart: Int { max(0, levelCount - 1) }
        public var current: PracticeItem? {
            questions.indices.contains(index) ? questions[index] : nil
        }
        public var isLast: Bool { index >= questions.count - 1 }
        /// Exclusive range end (clamped) for the summary label.
        public var rangeEnd: Int { min(start + count, levelCount) }
    }

    public enum Action: Equatable {
        case onAppear
        case loaded([Kanji], [Int: [String: String]])
        case levelSelected(String)
        case modeSelected(State.Mode)
        case wordsLoaded([WordEntry])
        case setStart(Double)
        case setCount(Int)
        case startTest
        case saveDrawing(Data)   // commit the current canvas into `drawings`
        case next
        case prev
        case toggleHint
        case hintStrokesLoaded([String])
        case finish              // → review
        case restart             // → setup
    }

    @Dependency(\.dictionaryClient) var dictionaryClient

    /// 단어쓰기 needs the level's vocabulary; 한자쓰기 already has every kanji.
    private func loadWords(_ level: String) -> Effect<Action> {
        .run { send in
            let words = (try? await dictionaryClient.quizWords(level, 400)) ?? []
            await send(.wordsLoaded(words))
        }
    }

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
                // Keep the chosen level valid for the current exam (e.g. after
                // switching JLPT↔漢検 the old "N5" wouldn't exist under 漢検).
                if !ExamType.current.levels.contains(state.level) {
                    state.level = ExamType.current.defaultLevel
                }
                return .none

            case let .levelSelected(level):
                state.level = level
                state.start = 0          // reset range to the top of the new level
                return state.mode == .word ? loadWords(level) : .none

            case let .setStart(value):
                state.start = max(0, min(Int(value), state.maxStart))
                return .none

            case let .setCount(count):
                state.count = count
                return .none

            case let .modeSelected(mode):
                state.mode = mode
                state.start = 0
                return mode == .word ? loadWords(state.level) : .none

            case let .wordsLoaded(words):
                state.words = words
                state.start = min(state.start, max(0, state.levelCount - 1))
                return .none

            case .startTest:
                let lk = state.levelItems
                guard !lk.isEmpty else { return .none }
                let s = min(state.start, max(0, lk.count - 1))
                let e = min(s + state.count, lk.count)
                state.questions = Array(lk[s..<e])
                state.index = 0
                state.drawings = [:]
                state.hintShown = false
                state.hintStrokes = []
                state.phase = .testing
                return .none

            case let .saveDrawing(data):
                state.drawings[state.index] = data
                return .none

            case .toggleHint:
                state.hintShown.toggle()
                guard state.hintShown, state.hintStrokes.isEmpty,
                      let id = state.current?.strokeOrderKanjiID else { return .none }
                return .run { [id] send in
                    let paths = (try? await dictionaryClient.strokeOrder(id)) ?? []
                    await send(.hintStrokesLoaded(paths))
                }

            case let .hintStrokesLoaded(paths):
                state.hintStrokes = paths
                return .none

            case .next:
                if state.index < state.questions.count - 1 { state.index += 1 }
                state.hintShown = false
                state.hintStrokes = []
                return .none

            case .prev:
                if state.index > 0 { state.index -= 1 }
                state.hintShown = false
                state.hintStrokes = []
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
