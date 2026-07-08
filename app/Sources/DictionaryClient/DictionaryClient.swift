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
