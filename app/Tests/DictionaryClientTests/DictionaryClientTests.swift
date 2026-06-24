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

    func testLiveReadsStrokeOrderForKanji() async throws {
        let client = DictionaryClient.liveValue
        let all = try await client.allKanji()
        let yama = try XCTUnwrap(all.first { $0.literal == "山" })

        let strokes = try await client.strokeOrder(yama.id)
        XCTAssertEqual(strokes, ["M21,30 L21,70", "M50,20 L50,80", "M79,30 L79,70"])
    }
}
