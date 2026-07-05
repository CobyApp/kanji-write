import ComposableArchitecture
import Foundation
import SharedModels

/// Persists per-quiz-item spaced-repetition records (Leitner box + due day) so
/// items resurface on schedule across sessions. Separate file from the kanji /
/// word SRS.
@DependencyClient
public struct QuizStore: Sendable {
    public var load: @Sendable () async -> [QuizRecord] = { [] }
    public var save: @Sendable (_ records: [QuizRecord]) async -> Void
}

extension QuizStore {
    public static func directory(_ directory: URL, file: String = "quiz_srs.json") -> QuizStore {
        let url = directory.appending(path: file)
        return QuizStore(
            load: {
                guard let data = try? Data(contentsOf: url),
                      let records = try? JSONDecoder().decode([QuizRecord].self, from: data)
                else { return [] }
                return records
            },
            save: { records in
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(records) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        )
    }
}

extension QuizStore: DependencyKey {
    public static let liveValue = QuizStore.directory(URL.applicationSupportDirectory)
}

extension QuizStore: TestDependencyKey {
    public static let testValue = QuizStore()
}

extension DependencyValues {
    public var quizStore: QuizStore {
        get { self[QuizStore.self] }
        set { self[QuizStore.self] = newValue }
    }
}
