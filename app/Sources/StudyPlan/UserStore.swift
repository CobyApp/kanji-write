import ComposableArchitecture
import Foundation

/// Persists the learner's active study plan. The seam behind which storage can
/// later become SwiftData; v1 is a single JSON file.
@DependencyClient
public struct UserStore: Sendable {
    public var loadPlan: @Sendable () async -> StudyPlan?
    public var savePlan: @Sendable (StudyPlan) async -> Void
}

extension UserStore {
    /// A store backed by a single JSON file at `url`.
    public static func jsonFile(at url: URL) -> UserStore {
        UserStore(
            loadPlan: {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(StudyPlan.self, from: data)
            },
            savePlan: { plan in
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true)
                if let data = try? JSONEncoder().encode(plan) {
                    try? data.write(to: url, options: .atomic)
                }
            }
        )
    }
}

extension UserStore: DependencyKey {
    public static let liveValue = UserStore.jsonFile(
        at: URL.applicationSupportDirectory.appending(path: "study_plan.json"))
}

extension UserStore: TestDependencyKey {
    public static let testValue = UserStore()
}

extension DependencyValues {
    public var userStore: UserStore {
        get { self[UserStore.self] }
        set { self[UserStore.self] = newValue }
    }
}
