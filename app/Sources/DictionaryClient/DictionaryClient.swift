import ComposableArchitecture
import SharedModels

/// Errors surfaced by the dictionary data layer.
public enum DictionaryError: Error, Equatable {
    case databaseUnavailable
}

/// Read-only access to the bundled kanji dictionary. The single seam between
/// UI/features and the data layer; `liveValue` (added later) is GRDB-backed.
@DependencyClient
public struct DictionaryClient: Sendable {
    public var allKanji: @Sendable () async throws -> [Kanji]
    public var strokeOrder: @Sendable (_ kanjiID: Int) async throws -> [String]
    public var glosses: @Sendable (_ kanjiID: Int) async throws -> [String: String]
    /// Every kanji's glosses at once: kanjiID → (lang code → meaning). For list
    /// screens that show each kanji's meaning without an N+1 per-row fetch.
    public var allGlosses: @Sendable () async throws -> [Int: [String: String]]
    public var words: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [WordEntry]
    /// Verbs formed with a kanji (surface ends in kana okurigana, reading ends
    /// in a う-row mora) — for the study "활용" card (e.g. 開く / 開ける).
    public var verbs: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [WordEntry]
    public var sentences: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [ExampleSentence]
    public var relations: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [RelationEntry]
    /// Antonym pairs whose prompt word contains the given kanji — for the
    /// "pick the antonym" quiz (prompt word + reading + its opposite).
    public var antonyms: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [AntonymPair]

    // Word-centric reads (for the word detail screen).
    /// A single word by id (surface, reading, 4-language meanings).
    public var word: @Sendable (_ wordID: Int) async throws -> WordEntry?
    /// Example sentences containing a word (via `sentence_word`).
    public var sentencesForWord: @Sendable (_ wordID: Int, _ limit: Int) async throws -> [ExampleSentence]
    /// The jōyō kanji a word contains, ordered by their position in the surface.
    public var kanjiForWord: @Sendable (_ wordID: Int) async throws -> [Kanji]
    /// Words containing a kanji of the given JLPT level (common first) — the pool
    /// for the reading quiz (questions + distractor readings).
    public var quizWords: @Sendable (_ level: String, _ limit: Int) async throws -> [WordEntry]
    /// Free-text word search over surface / reading / meaning (any language) —
    /// for the word dictionary. Common words first.
    public var searchWords: @Sendable (_ query: String, _ limit: Int) async throws -> [WordEntry]
    /// Pre-authored JLPT questions for a set of kanji (the day's studied + due
    /// kanji), capped per kanji — the source for the quiz.
    public var jlptQuestions: @Sendable (_ kanjiIDs: [Int], _ perKanji: Int) async throws -> [JLPTQuestion]
    /// Pre-authored questions of one kind (reading / orthography / context) for
    /// kanji at the given level — the source for the exam hub's sections. The
    /// level's format picks the column: "N5" → jlpt_level, "10級" → kanken_level.
    public var examQuestions: @Sendable (_ level: String, _ kind: String, _ limit: Int) async throws -> [JLPTQuestion]
    /// Kanji + their radical for a level — the input to the 部首 question generator
    /// (distractors are drawn from the pool of real radicals).
    public var examRadicalItems: @Sendable (_ level: String, _ limit: Int) async throws -> [RadicalItem]
    /// Kanji + their stroke count for a level — the input to the 画数 question
    /// generator (distractors are nearby counts).
    public var examStrokeItems: @Sendable (_ level: String, _ limit: Int) async throws -> [StrokeItem]
    /// 四字熟語 at or below the given 漢検 級 (cumulative), for the 四字熟語 exam
    /// section. "N…" JLPT levels have no 四字熟語 and return [].
    public var examYojijukugo: @Sendable (_ level: String, _ limit: Int) async throws -> [Yojijukugo]
    /// Every 四字熟語 (idiom order), for the 사자성어 dictionary browse.
    public var allYojijukugo: @Sendable () async throws -> [Yojijukugo]
    /// Free-text 四字熟語 search over idiom / reading / meaning.
    public var searchYojijukugo: @Sendable (_ query: String, _ limit: Int) async throws -> [Yojijukugo]
}

extension DictionaryClient: TestDependencyKey {
    public static let testValue = DictionaryClient()
}

extension DependencyValues {
    public var dictionaryClient: DictionaryClient {
        get { self[DictionaryClient.self] }
        set { self[DictionaryClient.self] = newValue }
    }
}
