import ComposableArchitecture
import DictionaryClient
import Foundation
import Review
import SharedModels

/// The kinds of question the quiz mixes.
public enum QuizKind: String, Equatable, Sendable {
    case kanjiMeaning   // 한자 → 뜻
    case wordReading    // 단어 → 읽기(かな)
    case wordMeaning    // 단어 → 뜻
}

/// One ready-to-show question (prompt + four options, correct answer known).
public struct QuizItem: Equatable, Identifiable, Sendable {
    public let id: String        // "<kind>:<entityID>" — stable for SRS
    public let kind: QuizKind
    public let prompt: String    // kanji glyph or word surface
    public let subtitle: String? // a hint (word meaning / reading)
    public let answer: String
    public let options: [String]
}

/// A learn-what-you-studied quiz. It mixes question types (kanji meaning, word
/// reading, word meaning) over today's kanji + any items whose spaced-repetition
/// review is due. It loops in phases — wrong answers requeue until every item is
/// answered correctly — and records each item's first-try result to schedule its
/// next appearance (Leitner: 1 · 3 · 7 · 14 · 30 · 60 days).
@Reducer
public struct QuizFeature {
    @ObservableState
    public struct State: Equatable {
        public var level: String
        public var kanjiIDs: [Int]
        public var language: AppLanguage
        public var today = 0
        public var records: [String: QuizRecord] = [:]

        public var queue: [QuizItem] = []          // remaining this session (mastery loop)
        public var totalItems = 0                  // unique items this session
        public var mastered = 0                    // items cleared (first correct)
        public var missed: Set<String> = []        // items answered wrong ≥ once
        public var firstAttempt: [String: Bool] = [:]
        public var answeredOnce: Set<String> = []
        public var chosen: String?
        public var started = false
        public var isLoading = false

        public init(level: String, kanjiIDs: [Int] = [], language: AppLanguage = .ko) {
            self.level = level
            self.kanjiIDs = kanjiIDs
            self.language = language
        }

        public var current: QuizItem? { queue.first }
        public var isFinished: Bool { started && queue.isEmpty }
        public var answered: Bool { chosen != nil }
        public var isRetry: Bool { current.map { missed.contains($0.id) } ?? false }
    }

    public enum Action: Equatable {
        case onAppear(language: AppLanguage)
        case loaded(kanji: [Kanji], glosses: [Int: [String: String]],
                    words: [WordEntry], pool: [WordEntry], records: [QuizRecord], today: Int)
        case chose(String)
        case next
        case restart
    }

    @Dependency(\.dictionaryClient) var dictionaryClient
    @Dependency(\.quizStore) var quizStore
    @Dependency(\.reviewStore) var reviewStore
    @Dependency(\.date) var date
    @Dependency(\.withRandomNumberGenerator) var withRandomNumberGenerator

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .onAppear(language):
                state.language = language
                return load(state: &state)

            case .restart:
                return load(state: &state)

            case let .loaded(kanji, glosses, words, pool, records, today):
                state.isLoading = false
                state.today = today
                state.records = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                let lang = state.language
                var items: [QuizItem] = []
                withRandomNumberGenerator { rng in
                    let kanjiMeanings = glosses.values.compactMap { localizedText($0, lang) }
                        .filter { !$0.isEmpty }
                    for k in kanji {
                        guard let answer = localizedText(glosses[k.id] ?? [:], lang), !answer.isEmpty
                        else { continue }
                        items.append(QuizItem(
                            id: "kanjiMeaning:\(k.id)", kind: .kanjiMeaning, prompt: k.literal,
                            subtitle: nil, answer: answer,
                            options: choiceOptions(answer: answer, pool: kanjiMeanings, using: &rng)))
                    }
                    let readingPool = Set((words + pool).map(\.reading)).filter { !$0.isEmpty }
                    let meaningPool = (words + pool).compactMap { wordMeaning($0, lang) }
                        .filter { !$0.isEmpty }
                    var seenWord = Set<Int>()
                    for w in words where seenWord.insert(w.id).inserted && !w.surface.isEmpty {
                        if !w.reading.isEmpty {
                            items.append(QuizItem(
                                id: "wordReading:\(w.id)", kind: .wordReading, prompt: w.surface,
                                subtitle: wordMeaning(w, lang), answer: w.reading,
                                options: readingOptions(answer: w.reading, pool: readingPool, using: &rng)))
                        }
                        if let answer = wordMeaning(w, lang), !answer.isEmpty {
                            items.append(QuizItem(
                                id: "wordMeaning:\(w.id)", kind: .wordMeaning,
                                prompt: "\(w.surface)（\(w.reading)）", subtitle: nil, answer: answer,
                                options: choiceOptions(answer: answer, pool: meaningPool, using: &rng)))
                        }
                    }
                    // Keep only new or SRS-due items (with ≥2 options), dedup, shuffle.
                    var seenID = Set<String>()
                    var active = items.filter { item in
                        guard seenID.insert(item.id).inserted, item.options.count >= 2 else { return false }
                        if let record = state.records[item.id] { return record.due <= today }
                        return true
                    }
                    active.shuffle(using: &rng)
                    state.queue = active
                }
                state.totalItems = state.queue.count
                state.mastered = 0
                state.missed = []
                state.firstAttempt = [:]
                state.answeredOnce = []
                state.chosen = nil
                state.started = true
                return .none

            case let .chose(option):
                guard state.chosen == nil else { return .none }
                state.chosen = option
                return .none

            case .next:
                guard let item = state.queue.first else { return .none }
                let correct = state.chosen == item.answer
                var save: Effect<Action> = .none
                // First attempt drives spaced repetition — schedule + persist right
                // away so review survives quitting mid-session.
                if state.answeredOnce.insert(item.id).inserted {
                    state.firstAttempt[item.id] = correct
                    let s = QuizSRS.schedule(box: state.records[item.id]?.box,
                                             correct: correct, today: state.today)
                    state.records[item.id] = QuizRecord(id: item.id, box: s.box, due: s.due)
                    let all = Array(state.records.values)
                    save = .run { _ in await quizStore.save(all) }
                }
                state.queue.removeFirst()
                if correct {
                    state.mastered += 1
                } else {
                    state.missed.insert(item.id)
                    state.queue.append(item)   // retry later this session
                }
                state.chosen = nil
                return save
            }
        }
    }

    private func load(state: inout State) -> Effect<Action> {
        state.isLoading = true
        state.started = false
        let level = state.level
        return .run { send in
            let today = Int(date.now.timeIntervalSince1970 / 86_400)
            // Read the kanji SRS fresh from disk (a study session may have just
            // written it) — kanji learned today OR due for review feed the quiz,
            // so review is woven into the same session as new material.
            let reviewRecords = await reviewStore.loadRecords()
            let kanjiIDs = reviewRecords
                .filter { $0.lastReviewedDay == today || $0.due <= today }
                .map(\.kanjiID)
            let records = await quizStore.load()
            // Entities whose SRS review is due today (regardless of today's study).
            var dueKanji = Set<Int>(), dueWords = Set<Int>()
            for record in records where record.due <= today {
                let parts = record.id.split(separator: ":")
                guard parts.count == 2, let eid = Int(parts[1]) else { continue }
                switch parts[0] {
                case "kanjiMeaning": dueKanji.insert(eid)
                case "wordReading", "wordMeaning": dueWords.insert(eid)
                default: break
                }
            }
            let allKanji = (try? await dictionaryClient.allKanji()) ?? []
            let byID = Dictionary(allKanji.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            let contextKanji = Set(kanjiIDs).union(dueKanji).compactMap { byID[$0] }
            let glosses = (try? await dictionaryClient.allGlosses()) ?? [:]
            var words: [WordEntry] = []
            for kid in kanjiIDs { words += (try? await dictionaryClient.words(kid, 4)) ?? [] }
            for wid in dueWords { if let w = try? await dictionaryClient.word(wid) { words.append(w) } }
            let pool = (try? await dictionaryClient.quizWords(level, 300)) ?? []
            await send(.loaded(kanji: contextKanji, glosses: glosses, words: words,
                               pool: pool, records: records, today: today))
        }
    }
}

/// Four shuffled options: the answer + three distinct distractors from `pool`.
func choiceOptions<G: RandomNumberGenerator>(
    answer: String, pool: [String], using rng: inout G
) -> [String] {
    var distractors = Array(Set(pool).subtracting([answer]))
    distractors.shuffle(using: &rng)
    var options = [answer] + distractors.prefix(3)
    options.shuffle(using: &rng)
    return options
}

/// Reading options: minimal-pair traps of `answer`, filled from `pool` if short.
func readingOptions<G: RandomNumberGenerator>(
    answer: String, pool: Set<String>, using rng: inout G
) -> [String] {
    var traps = phoneticTraps(answer)
    traps.shuffle(using: &rng)
    var distractors = Array(traps.prefix(3))
    if distractors.count < 3 {
        let near = pool.subtracting(distractors + [answer])
            .map { (reading: $0, distance: kanaDistance($0, answer)) }
            .sorted { $0.distance < $1.distance }
            .map(\.reading)
        distractors += near.prefix(3 - distractors.count)
    }
    var options = [answer] + distractors
    options.shuffle(using: &rng)
    return options
}

/// A localized meaning from a gloss map, with a deterministic fallback.
func localizedText(_ dict: [String: String], _ language: AppLanguage) -> String? {
    for key in [language.glossKey, "en", "ja", "ko", "zh"] {
        if let value = dict[key], !value.isEmpty { return value }
    }
    return dict.values.first { !$0.isEmpty }
}

/// A word's meaning in the selected language (falling back to English).
func wordMeaning(_ word: WordEntry, _ language: AppLanguage) -> String? {
    switch language {
    case .ko: word.meaningKo ?? word.meaningEn
    case .ja: word.meaningJa ?? word.meaningEn
    case .zh: word.meaningZh ?? word.meaningEn
    case .en: word.meaningEn
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
