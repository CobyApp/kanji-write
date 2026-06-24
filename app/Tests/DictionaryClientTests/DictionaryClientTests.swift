import XCTest

@testable import DictionaryClient

final class DictionaryClientTests: XCTestCase {
    func testLiveReadsBundledKanji() async throws {
        let client = DictionaryClient.liveValue
        let kanji = try await client.allKanji()

        // The bundled DB is the full jōyō set (2,136 kanji).
        XCTAssertEqual(kanji.count, 2136)

        let yama = try XCTUnwrap(kanji.first { $0.literal == "山" })
        XCTAssertEqual(yama.strokeCount, 3)
        XCTAssertEqual(yama.jlptLevel, "N5")
        XCTAssertTrue(yama.onReadings.contains("サン"))
        XCTAssertTrue(yama.kunReadings.contains("やま"))
    }

    func testLiveReadsStrokeOrderForKanji() async throws {
        let client = DictionaryClient.liveValue
        let all = try await client.allKanji()
        let yama = try XCTUnwrap(all.first { $0.literal == "山" })

        // Real KanjiVG geometry varies, so assert structure, not exact paths:
        // 山 has 3 strokes and every stroke is a non-empty SVG path starting at M.
        let strokes = try await client.strokeOrder(yama.id)
        XCTAssertEqual(strokes.count, 3)
        XCTAssertTrue(strokes.allSatisfy { $0.hasPrefix("M") })
    }
}
