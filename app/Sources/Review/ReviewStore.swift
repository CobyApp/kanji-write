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
    public static func directory(_ directory: URL, file: String = "reviews.json") -> ReviewStore {
        let url = directory.appending(path: file)
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
    // A safe empty store: reads yield no records, writes are no-ops. Lets
    // features that reload records on navigation (e.g. RootFeature refreshing
    // home progress on session end) run in tests without stubbing.
    public static let testValue = ReviewStore(loadRecords: { [] }, saveRecords: { _ in })
}

extension DependencyValues {
    public var reviewStore: ReviewStore {
        get { self[ReviewStore.self] }
        set { self[ReviewStore.self] = newValue }
    }
}

/// The word wordbook/SRS store — same shape as `ReviewStore` but a separate file
/// so kanji and word progress never mix. Records key `kanjiID` holds a word id.
public enum WordReviewStoreKey: DependencyKey {
    public static let liveValue = ReviewStore.directory(
        URL.applicationSupportDirectory, file: "word_reviews.json")
    public static let testValue = ReviewStore(loadRecords: { [] }, saveRecords: { _ in })
}

extension DependencyValues {
    public var wordReviewStore: ReviewStore {
        get { self[WordReviewStoreKey.self] }
        set { self[WordReviewStoreKey.self] = newValue }
    }
}
