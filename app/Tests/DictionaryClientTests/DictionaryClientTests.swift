import XCTest

@testable import DictionaryClient

final class DictionaryClientTests: XCTestCase {
    func testLiveReadsBundledKanji() async throws {
        let client = DictionaryClient.liveValue
        let kanji = try await client.allKanji()

        XCTAssertEqual(kanji.map(\.literal), ["山", "学"])

        let yama = try XCTUnwrap(kanji.first { $0.literal == "山" })
        XCTAssertEqual(yama.strokeCount, 3)
        XCTAssertEqual(yama.jlptLevel, "N5")
        XCTAssertTrue(yama.onReadings.contains("サン"))
        XCTAssertTrue(yama.kunReadings.contains("やま"))
    }
}
