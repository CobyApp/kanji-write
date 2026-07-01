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
    public var words: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [WordEntry]
    public var sentences: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [ExampleSentence]
    public var relations: @Sendable (_ kanjiID: Int, _ limit: Int) async throws -> [RelationEntry]

    // Word-centric reads (for the word detail screen).
    /// A single word by id (surface, reading, 4-language meanings).
    public var word: @Sendable (_ wordID: Int) async throws -> WordEntry?
    /// Example sentences containing a word (via `sentence_word`).
    public var sentencesForWord: @Sendable (_ wordID: Int, _ limit: Int) async throws -> [ExampleSentence]
    /// The jōyō kanji a word contains, ordered by their position in the surface.
    public var kanjiForWord: @Sendable (_ wordID: Int) async throws -> [Kanji]
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
