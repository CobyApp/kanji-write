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
