import SharedModels
import XCTest

@testable import DictionaryClient

final class DictionaryClientTests: XCTestCase {
    func testMembershipTablePreservesMissingMembershipAsEmpty() {
        XCTAssertEqual(
            DictionaryClient.resolvedKankenMemberships(
                kanjiID: 1,
                kankenLevel: "準1級",
                membershipsByID: [:],
                membershipTableExists: true
            ),
            []
        )
    }

    func testLegacyDatabaseFallsBackToIntroductionLevel() {
        XCTAssertEqual(
            DictionaryClient.resolvedKankenMemberships(
                kanjiID: 1,
                kankenLevel: "準1級",
                membershipsByID: [:],
                membershipTableExists: false
            ),
            ["準1級"]
        )
    }

    func testLevelPredicatesUseMembershipForKankenAndEqualityForJLPT() {
        XCTAssertEqual(DictionaryClient.kanjiLevelPredicate("N5"), "k.jlpt_level = ?")

        let kankenPredicate = DictionaryClient.kanjiLevelPredicate("準1級")
        XCTAssertTrue(kankenPredicate.contains("FROM kanken_membership km"))
        XCTAssertTrue(kankenPredicate.contains("km.level_label = ?"))
        XCTAssertFalse(kankenPredicate.contains("k.kanken_level"))
    }

    func testLiveReadsBundledKanji() async throws {
        let client = DictionaryClient.liveValue
        let kanji = try await client.allKanji()

        XCTAssertGreaterThan(kanji.count, 2136)

        let yama = try XCTUnwrap(kanji.first { $0.literal == "山" })
        XCTAssertEqual(yama.strokeCount, 3)
        XCTAssertEqual(yama.jlptLevel, "N5")
        XCTAssertTrue(yama.hasVerifiedStrokeOrder)
        XCTAssertTrue(yama.onReadings.contains("サン"))
        XCTAssertTrue(yama.kunReadings.contains("やま"))
        // Radical plumbing: DB radical index → KANGXI glyph.
        XCTAssertEqual(yama.radical, 46)
        XCTAssertEqual(yama.radicalGlyph, "山")
    }

    func testLiveLoadsKankenMemberships() async throws {
        let kanji = try await DictionaryClient.liveValue.allKanji()
        let legacyCounts = [
            "10級": 80, "9級": 160, "8級": 200, "7級": 202, "6級": 193,
            "5級": 191, "4級": 313, "3級": 284, "準2級": 328, "2級": 185,
        ]

        for (level, expectedCount) in legacyCounts {
            XCTAssertEqual(
                kanji.filter { $0.belongs(to: level, exam: .kanken) }.count,
                expectedCount,
                level
            )
        }

        let pre1IDs = Set(
            kanji.filter { $0.belongs(to: "準1級", exam: .kanken) }.map(\.id)
        )
        let level1IDs = Set(
            kanji.filter { $0.belongs(to: "1級", exam: .kanken) }.map(\.id)
        )
        XCTAssertFalse(pre1IDs.isEmpty)
        XCTAssertFalse(level1IDs.isEmpty)
        XCTAssertFalse(pre1IDs.intersection(level1IDs).isEmpty)
    }

    func testLiveLoadsWritingCapabilityIndependentlyOfStrokeCount() async throws {
        let kanji = try await DictionaryClient.liveValue.allKanji()
        let advanced = kanji.filter {
            $0.belongs(to: "準1級", exam: .kanken)
                || $0.belongs(to: "1級", exam: .kanken)
        }

        XCTAssertTrue(advanced.contains { !$0.hasVerifiedStrokeOrder && $0.strokeCount > 0 })
    }

    func testLiveAdvancedKankenItemQueriesStayWithinMembershipScope() async throws {
        let client = DictionaryClient.liveValue
        let kanji = try await client.allKanji()

        for level in ["準1級", "1級"] {
            let memberIDs = Set(
                kanji.filter { $0.belongs(to: level, exam: .kanken) }.map(\.id)
            )
            let radicals = try await client.examRadicalItems(level, 10_000)
            let strokes = try await client.examStrokeItems(level, 10_000)
            let onKun = try await client.examOnKun(level, 10_000)
            let words = try await client.quizWords(level, 20)
            let okurigana = try await client.examOkurigana(level, 20)

            XCTAssertFalse(radicals.isEmpty, level)
            XCTAssertFalse(strokes.isEmpty, level)
            XCTAssertFalse(onKun.isEmpty, level)
            XCTAssertTrue(radicals.allSatisfy { memberIDs.contains($0.kanjiID) }, level)
            XCTAssertTrue(strokes.allSatisfy { memberIDs.contains($0.kanjiID) }, level)
            XCTAssertTrue(onKun.allSatisfy { memberIDs.contains($0.kanjiID) }, level)
            try await assertWords(words, containAnyKanjiIn: memberIDs, client: client, level: level)
            try await assertWords(okurigana, containAnyKanjiIn: memberIDs, client: client, level: level)

            // Both advanced scopes are backed by the generated bank now.
            for kind in ["reading", "orthography"] {
                let questions = try await client.examQuestions(level, kind, 10_000)
                XCTAssertFalse(questions.isEmpty, "\(level) \(kind)")
                XCTAssertTrue(questions.allSatisfy { memberIDs.contains($0.kanjiID) },
                              "\(level) \(kind)")
            }
        }
    }

    func testLiveJLPTItemQueriesStayWithinExactLevelScope() async throws {
        let client = DictionaryClient.liveValue
        let kanji = try await client.allKanji()
        let level = "N5"
        let memberIDs = Set(kanji.filter { $0.jlptLevel == level }.map(\.id))
        let radicals = try await client.examRadicalItems(level, 10_000)
        let strokes = try await client.examStrokeItems(level, 10_000)
        let onKun = try await client.examOnKun(level, 10_000)
        let questions = try await client.examQuestions(level, "reading", 10_000)

        XCTAssertFalse(radicals.isEmpty)
        XCTAssertFalse(strokes.isEmpty)
        XCTAssertFalse(onKun.isEmpty)
        XCTAssertFalse(questions.isEmpty)
        XCTAssertTrue(radicals.allSatisfy { memberIDs.contains($0.kanjiID) })
        XCTAssertTrue(strokes.allSatisfy { memberIDs.contains($0.kanjiID) })
        XCTAssertTrue(onKun.allSatisfy { memberIDs.contains($0.kanjiID) })
        XCTAssertTrue(questions.allSatisfy { memberIDs.contains($0.kanjiID) })
        try await assertWords(
            try await client.quizWords(level, 20),
            containAnyKanjiIn: memberIDs,
            client: client,
            level: level
        )
        try await assertWords(
            try await client.examOkurigana(level, 20),
            containAnyKanjiIn: memberIDs,
            client: client,
            level: level
        )
    }

    func testLiveReadsJLPTQuestionsForKanji() async throws {
        let client = DictionaryClient.liveValue
        let all = try await client.allKanji()
        let yama = try XCTUnwrap(all.first { $0.literal == "山" })

        // The offline JLPT question bank covers every N5–N1 kanji; each question
        // has 4 options and an in-range answer index.
        let questions = try await client.jlptQuestions([yama.id], 2)
        XCTAssertFalse(questions.isEmpty)
        XCTAssertLessThanOrEqual(questions.count, 2)      // per-kanji cap honored
        for q in questions {
            XCTAssertEqual(q.kanjiID, yama.id)
            XCTAssertEqual(q.options.count, 4)
            XCTAssertTrue(q.options.indices.contains(q.answer))
            XCTAssertFalse(q.prompt.isEmpty)
        }
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
        // The bundled DB now also carries ja/zh word glosses (4-language parity).
        XCTAssertTrue(words.contains { $0.meaningJa != nil })
        XCTAssertTrue(words.contains { $0.meaningZh != nil })

        let sentences = try await client.sentences(yama.id, 3)
        XCTAssertFalse(sentences.isEmpty)
        XCTAssertTrue(sentences[0].textJa.contains("山"))
        XCTAssertFalse(sentences[0].translations.isEmpty)
    }

    func testLiveReadsWordDetailAndBackLinks() async throws {
        let client = DictionaryClient.liveValue
        let allKanji = try await client.allKanji()
        let yama = try XCTUnwrap(allKanji.first { $0.literal == "山" })

        // Pick a real multi-kanji word containing 山 from the bundled DB.
        let words = try await client.words(yama.id, 50)
        let multi = try XCTUnwrap(words.first { $0.surface.count >= 2 })

        // word(id) round-trips surface/reading + at least one native meaning.
        let fetchedWord = try await client.word(multi.id)
        let fetched = try XCTUnwrap(fetchedWord)
        XCTAssertEqual(fetched.surface, multi.surface)
        XCTAssertFalse(fetched.reading.isEmpty)
        XCTAssertNotNil(fetched.meaningKo ?? fetched.meaningEn)

        // kanjiForWord returns the word's jōyō kanji, ordered by surface position.
        let kanji = try await client.kanjiForWord(multi.id)
        XCTAssertFalse(kanji.isEmpty)
        XCTAssertTrue(kanji.allSatisfy { multi.surface.contains($0.literal) })
        let positions = kanji.map { multi.surface.distance(
            from: multi.surface.startIndex,
            to: multi.surface.firstIndex(of: Character($0.literal))!) }
        XCTAssertEqual(positions, positions.sorted())

        // sentencesForWord: every returned sentence contains the surface.
        let sentences = try await client.sentencesForWord(multi.id, 3)
        XCTAssertTrue(sentences.allSatisfy { $0.textJa.contains(multi.surface) })
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

    private func assertWords(
        _ words: [WordEntry],
        containAnyKanjiIn memberIDs: Set<Int>,
        client: DictionaryClient,
        level: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        XCTAssertFalse(words.isEmpty, level, file: file, line: line)
        for word in words {
            let wordKanjiIDs = Set(try await client.kanjiForWord(word.id).map(\.id))
            XCTAssertFalse(
                wordKanjiIDs.isDisjoint(with: memberIDs),
                "\(level): \(word.surface)",
                file: file,
                line: line
            )
        }
    }
}
