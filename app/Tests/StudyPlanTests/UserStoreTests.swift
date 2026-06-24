import Foundation
import XCTest

@testable import StudyPlan

final class UserStoreTests: XCTestCase {
    func testJSONFileRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "userstore-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = UserStore.jsonFile(at: dir.appending(path: "plan.json"))
        let before = await store.loadPlan()
        XCTAssertNil(before)

        let plan = StudyPlan(axisLabel: "学年", durationDays: 2,
                             dayAssignments: [[1], [2]], completedKanjiIDs: [1])
        await store.savePlan(plan)

        let after = await store.loadPlan()
        XCTAssertEqual(after, plan)
    }
}
