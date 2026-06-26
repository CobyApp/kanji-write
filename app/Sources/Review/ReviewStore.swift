import ComposableArchitecture
import Foundation
import SharedModels

/// Persists the learner's SRS records.
@DependencyClient
public struct ReviewStore: Sendable {
    public var loadRecords: @Sendable () async -> [ReviewRecord] = { [] }
    public var saveRecords: @Sendable (_ records: [ReviewRecord]) async -> Void
}

extension ReviewStore {
    public static func directory(_ directory: URL) -> ReviewStore {
        let url = directory.appending(path: "reviews.json")
        return ReviewStore(
            loadRecords: {
                guard let data = try? Data(contentsOf: url),
                      let records = try? JSONDecoder().decode([ReviewRecord].self, from: data)
                else { return [] }
                return records
            },
            saveRecords: { records in
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(records) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        )
    }
}

extension ReviewStore: DependencyKey {
    public static let liveValue = ReviewStore.directory(URL.applicationSupportDirectory)
}

extension ReviewStore: TestDependencyKey {
    public static let testValue = ReviewStore()
}

extension DependencyValues {
    public var reviewStore: ReviewStore {
        get { self[ReviewStore.self] }
        set { self[ReviewStore.self] = newValue }
    }
}
