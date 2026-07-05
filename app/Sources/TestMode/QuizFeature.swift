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
                    let pool = (try? await dictionaryClient.quizWords(level, 400)) ?? []
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

    /// Builds the 4 shuffled options for the current question and clears the
    /// previous choice. Distractors are *generated* as minimal pairs of the
    /// correct reading — the exact things learners confuse: voicing (か/が), long
    /// vowels (こう/こ), small tsu (きって/きて), yōon (きゃ/きや). If a reading is
    /// too short to yield three traps, the nearest pool readings fill in.
    private func buildOptions(_ state: inout State) {
        state.chosen = nil
        guard let correct = state.current?.reading else {
            state.options = []
            return
        }
        var traps = phoneticTraps(correct)
        withRandomNumberGenerator { traps.shuffle(using: &$0) }
        var distractors = Array(traps.prefix(3))
        if distractors.count < 3 {
            // Fallback: nearest real readings from the pool.
            let near = Set(state.readingPool)
                .subtracting(distractors + [correct])
                .map { (reading: $0, distance: kanaDistance($0, correct)) }
                .sorted { $0.distance < $1.distance }
                .map(\.reading)
            distractors += near.prefix(3 - distractors.count)
        }
        var options = [correct] + distractors
        withRandomNumberGenerator { options.shuffle(using: &$0) }
        state.options = options
    }
}

/// Voicing groups: members are one dakuten/handakuten toggle apart.
private let voicingGroups: [[Character]] = [
    ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
    ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
    ["た", "だ"], ["ち", "ぢ"], ["つ", "づ"], ["て", "で"], ["と", "ど"],
    ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"],
    ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"],
]

private let iRowKana: Set<Character> = [
    "い", "き", "し", "ち", "に", "ひ", "み", "り", "ぎ", "じ", "ぢ", "び", "ぴ",
]
/// Kana that a long-vowel う naturally follows (o-row and u-row).
private let ouRowKana: Set<Character> = [
    "う", "く", "す", "つ", "ぬ", "ふ", "む", "ゆ", "る", "ぐ", "ず", "づ", "ぶ", "ぷ",
    "お", "こ", "そ", "と", "の", "ほ", "も", "よ", "ろ", "ご", "ぞ", "ど", "ぼ", "ぽ", "ょ",
]
/// Kana that a long-vowel い naturally follows (e-row).
private let eRowKana: Set<Character> = [
    "え", "け", "せ", "て", "ね", "へ", "め", "れ", "げ", "ぜ", "で", "べ", "ぺ",
]
private let smallLeadingKana: Set<Character> = [
    "っ", "ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ー",
]
private let plainVowelKana: Set<Character> = ["あ", "い", "う", "え", "お"]

/// Whether a kana string is a pronounceable reading — rejects impossible shapes
/// (leading っ/ー/small kana, trailing っ, っ before a vowel, orphan yōon).
func isPlausibleKana(_ s: String) -> Bool {
    let a = Array(s)
    guard let first = a.first, !smallLeadingKana.contains(first) else { return false }
    guard a.last != "っ" else { return false }
    for i in a.indices {
        if a[i] == "っ" {
            guard i + 1 < a.count else { return false }
            let next = a[i + 1]
            if plainVowelKana.contains(next) || next == "っ" || next == "ん" || next == "ー" {
                return false
            }
        }
        if a[i] == "ゃ" || a[i] == "ゅ" || a[i] == "ょ" {
            guard i > 0, iRowKana.contains(a[i - 1]) else { return false }
        }
    }
    return true
}

/// Plausible-but-wrong readings one confusion away from `reading`: voicing
/// toggles, long-vowel add/drop, small-tsu add/drop, and yōon big/small swaps.
/// These minimal pairs are exactly the traps learners fall for. Impossible kana
/// shapes are filtered out so every option reads naturally.
func phoneticTraps(_ reading: String) -> [String] {
    let chars = Array(reading)
    guard !chars.isEmpty else { return [] }
    var out = Set<String>()

    // 1) Voicing toggles (か↔が, は↔ば↔ぱ …).
    for i in chars.indices {
        for group in voicingGroups where group.contains(chars[i]) {
            for alt in group where alt != chars[i] {
                var c = chars; c[i] = alt; out.insert(String(c))
            }
        }
    }
    // 2) Long vowels: drop a vowel/長音, or lengthen only where natural
    //    (う after o/u-row, い after e-row).
    let vowels: Set<Character> = ["あ", "い", "う", "え", "お", "ー"]
    for i in chars.indices where vowels.contains(chars[i]) {
        var c = chars; c.remove(at: i); out.insert(String(c))
    }
    for i in chars.indices {
        if ouRowKana.contains(chars[i]) {
            var c = chars; c.insert("う", at: i + 1); out.insert(String(c))
        } else if eRowKana.contains(chars[i]) {
            var c = chars; c.insert("い", at: i + 1); out.insert(String(c))
        }
    }
    // 3) Small tsu: drop it, or insert one before an interior kana.
    if chars.contains("っ") {
        for i in chars.indices where chars[i] == "っ" {
            var c = chars; c.remove(at: i); out.insert(String(c))
        }
    } else if chars.count >= 2 {
        for i in 1..<chars.count {
            var c = chars; c.insert("っ", at: i); out.insert(String(c))
        }
    }
    // 4) Yōon big/small swap (きゃ↔きや).
    let yoon: [Character: Character] = [
        "ゃ": "や", "ゅ": "ゆ", "ょ": "よ", "や": "ゃ", "ゆ": "ゅ", "よ": "ょ",
    ]
    for i in chars.indices {
        if let alt = yoon[chars[i]] { var c = chars; c[i] = alt; out.insert(String(c)) }
    }

    out.remove(reading)
    return out.filter(isPlausibleKana)
}

/// Levenshtein edit distance between two kana readings. Small distance = the
/// readings differ by only a mora / voicing / length — i.e. confusingly close.
func kanaDistance(_ a: String, _ b: String) -> Int {
    let s = Array(a), t = Array(b)
    if s.isEmpty { return t.count }
    if t.isEmpty { return s.count }
    var prev = Array(0...t.count)
    var curr = [Int](repeating: 0, count: t.count + 1)
    for i in 1...s.count {
        curr[0] = i
        for j in 1...t.count {
            let cost = s[i - 1] == t[j - 1] ? 0 : 1
            curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &curr)
    }
    return prev[t.count]
}
