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

    func testLiveReadsGlossesForKanji() async throws {
        let client = DictionaryClient.liveValue
        let allKanji = try await client.allKanji()
        let yama = try XCTUnwrap(allKanji.first { $0.literal == "山" })
        let glosses = try await client.glosses(yama.id)
        XCTAssertEqual(glosses["ko"], "메 산")
        XCTAssertNotNil(glosses["en"])
        XCTAssertNotNil(glosses["ja"])
        XCTAssertNotNil(glosses["zh"])
    }

    func testLiveReadsWordsAndSentencesForKanji() async throws {
        let client = DictionaryClient.liveValue
        let allKanji = try await client.allKanji()
        let yama = try XCTUnwrap(allKanji.first { $0.literal == "山" })

        let words = try await client.words(yama.id, 12)
        XCTAssertFalse(words.isEmpty)
        XCTAssertTrue(words.allSatisfy { !$0.surface.isEmpty && !$0.reading.isEmpty })
        // The bundled DB now carries both English and Korean word glosses.
        XCTAssertTrue(words.contains { $0.meaningEn != nil })
        XCTAssertTrue(words.contains { $0.meaningKo != nil })
        // ja/zh word glosses are not yet in the bundled DB (regenerated later).
        // Flip these to `contains { != nil }` after the DB is re-bundled.
        XCTAssertTrue(words.allSatisfy { $0.meaningJa == nil })
        XCTAssertTrue(words.allSatisfy { $0.meaningZh == nil })

        let sentences = try await client.sentences(yama.id, 3)
        XCTAssertFalse(sentences.isEmpty)
        XCTAssertTrue(sentences[0].textJa.contains("山"))
        XCTAssertFalse(sentences[0].translations.isEmpty)
    }

    func testLiveReadsRelationsForKanji() async throws {
        let client = DictionaryClient.liveValue
        let allKanji = try await client.allKanji()
        // 大 (big) is common and has antonyms (e.g. 小さい) in JMdict.
        let dai = try XCTUnwrap(allKanji.first { $0.literal == "大" })
        let relations = try await client.relations(dai.id, 20)
        XCTAssertFalse(relations.isEmpty)
        XCTAssertTrue(relations.allSatisfy { $0.type == "antonym" || $0.type == "related" })
        XCTAssertTrue(relations.allSatisfy { !$0.surface.isEmpty })
    }
}
