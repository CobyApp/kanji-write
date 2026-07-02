import ComposableArchitecture
import Foundation

/// Persists the set of bookmarked kanji ids (a plain favorites list — separate
/// from the FSRS review records and the word wordbook).
@DependencyClient
public struct KanjiBookmarkStore: Sendable {
    public var load: @Sendable () async -> [Int] = { [] }
    public var save: @Sendable (_ ids: [Int]) async -> Void
}

extension KanjiBookmarkStore {
    public static func directory(_ directory: URL, file: String = "kanji_bookmarks.json") -> KanjiBookmarkStore {
        let url = directory.appending(path: file)
        return KanjiBookmarkStore(
            load: {
                guard let data = try? Data(contentsOf: url),
                      let ids = try? JSONDecoder().decode([Int].self, from: data)
                else { return [] }
                return ids
            },
            save: { ids in
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(ids) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        )
    }
}

extension KanjiBookmarkStore: DependencyKey {
    public static let liveValue = KanjiBookmarkStore.directory(URL.applicationSupportDirectory)
}

extension KanjiBookmarkStore: TestDependencyKey {
    public static let testValue = KanjiBookmarkStore()
}

extension DependencyValues {
    public var kanjiBookmarkStore: KanjiBookmarkStore {
        get { self[KanjiBookmarkStore.self] }
        set { self[KanjiBookmarkStore.self] = newValue }
    }
}
