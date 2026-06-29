import Foundation
import SharedModels
import XCTest

@testable import Review

final class ReviewStoreTests: XCTestCase {
    func testSaveLoadRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "reviews-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ReviewStore.directory(dir)
        let empty = await store.loadRecords()
        XCTAssertEqual(empty, [])

        let records = [ReviewRecord(
            kanjiID: 1, stability: 12.5, difficulty: 5.2, due: 112,
            lastReviewedDay: 100, lapses: 1, reps: 3)]
        await store.saveRecords(records)
        let loaded = await store.loadRecords()
        XCTAssertEqual(loaded, records)
    }
}
