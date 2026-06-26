import Foundation
import XCTest

@testable import WritingCanvas

final class DrawingStoreTests: XCTestCase {
    func testSaveThenLoadRoundTrips() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "drawings-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = DrawingStore.directory(dir)
        let before = await store.loadDrawing(1)
        XCTAssertNil(before)

        let data = Data("ink".utf8)
        await store.saveDrawing(1, data)
        let after = await store.loadDrawing(1)
        XCTAssertEqual(after, data)

        let other = await store.loadDrawing(2)  // unsaved id
        XCTAssertNil(other)
    }
}
