import ComposableArchitecture
import Foundation

/// The writing test's 즐겨찾기 list — the items a learner marked while checking
/// their answers, one list per mode (한자 / 단어 / 사자성어).
///
/// Separate from `KanjiBookmarkStore` on purpose. A bookmark means "keep this
/// where I can find it"; this means "I got this wrong, test me on it again", and
/// the two lists want to be different. It is also separate from 오답노트, which
/// belongs to the multiple-choice exam and can be graded automatically — a
/// writing test cannot be, so the learner marks these by hand.
///
/// Stored as mode → ids so the mode's own list survives switching modes. Ids are
/// resolved back to items at test time rather than the item being copied in,
/// which keeps a favourite's meaning current as translations are added.
@DependencyClient
public struct PracticeFavoriteStore: Sendable {
    public var load: @Sendable () async -> [String: [Int]] = { [:] }
    public var save: @Sendable (_ byMode: [String: [Int]]) async -> Void
}

extension PracticeFavoriteStore {
    public static func directory(
        _ directory: URL, file: String = "practice_favorites.json"
    ) -> PracticeFavoriteStore {
        let url = directory.appending(path: file)
        return PracticeFavoriteStore(
            load: {
                guard let data = try? Data(contentsOf: url),
                      let byMode = try? JSONDecoder().decode([String: [Int]].self, from: data)
                else { return [:] }
                return byMode
            },
            save: { byMode in
                try? FileManager.default.createDirectory(
                    at: directory, withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(byMode) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        )
    }
}

extension PracticeFavoriteStore: DependencyKey {
    public static let liveValue = PracticeFavoriteStore.directory(URL.applicationSupportDirectory)
}

extension PracticeFavoriteStore: TestDependencyKey {
    public static let testValue = PracticeFavoriteStore()
}

extension DependencyValues {
    public var practiceFavoriteStore: PracticeFavoriteStore {
        get { self[PracticeFavoriteStore.self] }
        set { self[PracticeFavoriteStore.self] = newValue }
    }
}
