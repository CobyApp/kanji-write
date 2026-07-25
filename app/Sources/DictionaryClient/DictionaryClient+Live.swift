import ComposableArchitecture
import Foundation
import GRDB
import SharedModels

extension DictionaryClient: DependencyKey {
    public static let liveValue = DictionaryClient(
        allKanji: {
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [Kanji] in
                let kanjiRows = try Row.fetchAll(db, sql: """
                    SELECT id, literal, stroke_count, grade, jlpt_level, kanken_level, radical
                    FROM kanji
                    ORDER BY id
                    """)
                return try kanjiRows.map { row in
                    let id: Int = row["id"]
                    let grade: Int? = row["grade"]
                    let jlpt: String? = row["jlpt_level"]
                    let kanken: String? = row["kanken_level"]
                    let radical: Int? = row["radical"]

                    // NOTE: N+1 by design for the 2-row scaffold DB; replace with a single
                    // grouped query (or JOIN) when loading the full kanji set.
                    let readingRows = try Row.fetchAll(db, sql: """
                        SELECT lang_axis, value FROM reading
                        WHERE kanji_id = ? AND lang_axis IN ('on', 'kun')
                        """, arguments: [id])

                    var onReadings: [String] = []
                    var kunReadings: [String] = []
                    for r in readingRows {
                        let axis: String = r["lang_axis"]
                        let value: String = r["value"]
                        if axis == "on" { onReadings.append(value) }
                        else { kunReadings.append(value) }
                    }

                    return Kanji(
                        id: id,
                        literal: row["literal"],
                        strokeCount: row["stroke_count"],
                        grade: grade,
                        jlptLevel: jlpt,
                        kankenLevel: kanken,
                        onReadings: onReadings,
                        kunReadings: kunReadings,
                        radical: radical
                    )
                }
            }
        },
        strokeOrder: { kanjiID in
            let queue = try openBundledDatabase()
            return try await queue.read { db in
                try String.fetchAll(db, sql: """
                    SELECT path_d FROM stroke_order
                    WHERE kanji_id = ? ORDER BY ordinal
                    """, arguments: [kanjiID])
            }
        },
        glosses: { kanjiID in
            let queue = try openBundledDatabase()
            return try await queue.read { db in
                var result: [String: String] = [:]
                for row in try Row.fetchAll(
                    db, sql: "SELECT lang, GROUP_CONCAT(text, '; ') AS text FROM gloss WHERE kanji_id = ? GROUP BY lang",
                    arguments: [kanjiID]
                ) {
                    let lang: String = row["lang"]
                    result[lang] = row["text"]
                }
                return result
            }
        },
        allGlosses: {
            let queue = try openBundledDatabase()
            return try await queue.read { db in
                var result: [Int: [String: String]] = [:]
                for row in try Row.fetchAll(
                    db, sql: "SELECT kanji_id, lang, GROUP_CONCAT(text, '; ') AS text FROM gloss GROUP BY kanji_id, lang"
                ) {
                    let id: Int = row["kanji_id"]
                    let lang: String = row["lang"]
                    result[id, default: [:]][lang] = row["text"]
                }
                return result
            }
        },
        words: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [WordEntry] in
                // NOTE: N+1 by design; limit is small (≤12 words / ≤3 sentences) on a
                // local read-only DB. Replace with a JOIN + aggregation if limits grow.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT w.id, w.surface, w.reading_kana FROM word w
                    JOIN word_kanji wk ON wk.word_id = w.id
                    WHERE wk.kanji_id = ?
                    ORDER BY w.is_common DESC, w.id
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    let meaning = try String.fetchOne(
                        db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = 'en' LIMIT 1",
                        arguments: [id])
                    let meaningKo = try String.fetchOne(
                        db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = 'ko' LIMIT 1",
                        arguments: [id])
                    let meaningJa = try String.fetchOne(
                        db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = 'ja' LIMIT 1",
                        arguments: [id])
                    let meaningZh = try String.fetchOne(
                        db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = 'zh' LIMIT 1",
                        arguments: [id])
                    return WordEntry(
                        id: id, surface: row["surface"],
                        reading: row["reading_kana"], meaningEn: meaning, meaningKo: meaningKo,
                        meaningJa: meaningJa, meaningZh: meaningZh)
                }
            }
        },
        verbs: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [WordEntry] in
                // Verbs: surface ends in kana okurigana, reading ends in a う-row
                // mora. Common first, then shorter surfaces (the core verb).
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT w.id, w.surface, w.reading_kana FROM word w
                    JOIN word_kanji wk ON wk.word_id = w.id
                    WHERE wk.kanji_id = ?
                      AND w.reading_kana GLOB '*[うくぐすつぬぶむる]'
                      AND w.surface GLOB '*[ぁ-ん]'
                    ORDER BY w.is_common DESC, LENGTH(w.surface), w.id
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    func gloss(_ lang: String) throws -> String? {
                        try String.fetchOne(
                            db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = ? LIMIT 1",
                            arguments: [id, lang])
                    }
                    return WordEntry(
                        id: id, surface: row["surface"], reading: row["reading_kana"],
                        meaningEn: try gloss("en"), meaningKo: try gloss("ko"),
                        meaningJa: try gloss("ja"), meaningZh: try gloss("zh"))
                }
            }
        },
        sentences: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [ExampleSentence] in
                // NOTE: N+1 by design; limit is small (≤12 words / ≤3 sentences) on a
                // local read-only DB. Replace with a JOIN + aggregation if limits grow.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT s.id, s.text_ja FROM sentence s
                    JOIN sentence_kanji sk ON sk.sentence_id = s.id
                    WHERE sk.kanji_id = ?
                    ORDER BY s.id
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    var translations: [String: String] = [:]
                    for tr in try Row.fetchAll(
                        db, sql: "SELECT lang, text FROM sentence_translation WHERE sentence_id = ?",
                        arguments: [id]
                    ) {
                        let lang: String = tr["lang"]
                        translations[lang] = tr["text"]
                    }
                    return ExampleSentence(
                        id: id, textJa: row["text_ja"], translations: translations)
                }
            }
        },
        relations: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [RelationEntry] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT r.type AS type, wb.surface AS surface
                    FROM word_kanji wk
                    JOIN relation r ON r.word_id_a = wk.word_id
                    JOIN word wb ON wb.id = r.word_id_b
                    WHERE wk.kanji_id = ?
                    ORDER BY r.type, wb.surface
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return rows.map { row in
                    RelationEntry(surface: row["surface"], type: row["type"])
                }
            }
        },
        antonyms: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [AntonymPair] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT wa.surface AS prompt, wa.reading_kana AS reading,
                                    wb.surface AS answer
                    FROM word_kanji wk
                    JOIN relation r ON r.word_id_a = wk.word_id AND r.type = 'antonym'
                    JOIN word wa ON wa.id = r.word_id_a
                    JOIN word wb ON wb.id = r.word_id_b
                    WHERE wk.kanji_id = ?
                    ORDER BY wa.surface
                    LIMIT ?
                    """, arguments: [kanjiID, limit])
                return rows.map { row in
                    AntonymPair(promptSurface: row["prompt"], promptReading: row["reading"],
                                answerSurface: row["answer"])
                }
            }
        },
        word: { wordID in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> WordEntry? in
                guard let row = try Row.fetchOne(
                    db, sql: "SELECT id, surface, reading_kana FROM word WHERE id = ?",
                    arguments: [wordID]) else { return nil }
                let id: Int = row["id"]
                func gloss(_ lang: String) throws -> String? {
                    try String.fetchOne(
                        db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = ? LIMIT 1",
                        arguments: [id, lang])
                }
                return WordEntry(
                    id: id, surface: row["surface"], reading: row["reading_kana"],
                    meaningEn: try gloss("en"), meaningKo: try gloss("ko"),
                    meaningJa: try gloss("ja"), meaningZh: try gloss("zh"))
            }
        },
        sentencesForWord: { wordID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [ExampleSentence] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT s.id, s.text_ja FROM sentence s
                    JOIN sentence_word sw ON sw.sentence_id = s.id
                    WHERE sw.word_id = ?
                    ORDER BY LENGTH(s.text_ja), s.id
                    LIMIT ?
                    """, arguments: [wordID, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    var translations: [String: String] = [:]
                    for tr in try Row.fetchAll(
                        db, sql: "SELECT lang, text FROM sentence_translation WHERE sentence_id = ?",
                        arguments: [id]
                    ) {
                        let lang: String = tr["lang"]
                        translations[lang] = tr["text"]
                    }
                    return ExampleSentence(
                        id: id, textJa: row["text_ja"], translations: translations)
                }
            }
        },
        kanjiForWord: { wordID in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [Kanji] in
                let surface = try String.fetchOne(
                    db, sql: "SELECT surface FROM word WHERE id = ?", arguments: [wordID]) ?? ""
                let rows = try Row.fetchAll(db, sql: """
                    SELECT k.id, k.literal, k.stroke_count, k.grade, k.jlpt_level
                    FROM kanji k JOIN word_kanji wk ON wk.kanji_id = k.id
                    WHERE wk.word_id = ?
                    """, arguments: [wordID])
                let kanji = try rows.map { row -> Kanji in
                    let id: Int = row["id"]
                    let readingRows = try Row.fetchAll(db, sql: """
                        SELECT lang_axis, value FROM reading
                        WHERE kanji_id = ? AND lang_axis IN ('on', 'kun')
                        """, arguments: [id])
                    var onReadings: [String] = []
                    var kunReadings: [String] = []
                    for r in readingRows {
                        let axis: String = r["lang_axis"]
                        let value: String = r["value"]
                        if axis == "on" { onReadings.append(value) } else { kunReadings.append(value) }
                    }
                    return Kanji(
                        id: id, literal: row["literal"], strokeCount: row["stroke_count"],
                        grade: row["grade"], jlptLevel: row["jlpt_level"],
                        onReadings: onReadings, kunReadings: kunReadings)
                }
                // Order by first appearance in the surface (山 before 学 in "登山学").
                func position(_ literal: String) -> Int {
                    guard let ch = literal.first,
                          let idx = surface.firstIndex(of: ch) else { return Int.max }
                    return surface.distance(from: surface.startIndex, to: idx)
                }
                return kanji.sorted { position($0.literal) < position($1.literal) }
            }
        },
        quizWords: { level, limit in
            let queue = try openBundledDatabase()
            // Pick the level column from the requested level's format: JLPT levels
            // are "N1"…"N5", 漢検 levels are "10級"…"1級" / "準2級". The column name
            // is a controlled constant (not user input), so interpolation is safe.
            let column = level.hasPrefix("N") ? "jlpt_level" : "kanken_level"
            return try await queue.read { db -> [WordEntry] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT w.id, w.surface, w.reading_kana FROM word w
                    JOIN word_kanji wk ON wk.word_id = w.id
                    JOIN kanji k ON k.id = wk.kanji_id
                    WHERE k.\(column) = ?
                    ORDER BY w.is_common DESC, w.id
                    LIMIT ?
                    """, arguments: [level, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    func gloss(_ lang: String) throws -> String? {
                        try String.fetchOne(
                            db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = ? LIMIT 1",
                            arguments: [id, lang])
                    }
                    return WordEntry(
                        id: id, surface: row["surface"], reading: row["reading_kana"],
                        meaningEn: try gloss("en"), meaningKo: try gloss("ko"),
                        meaningJa: try gloss("ja"), meaningZh: try gloss("zh"))
                }
            }
        },
        searchWords: { query, limit in
            let queue = try openBundledDatabase()
            let q = "%\(query)%"
            return try await queue.read { db -> [WordEntry] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT DISTINCT w.id, w.surface, w.reading_kana, w.is_common FROM word w
                    LEFT JOIN word_gloss g ON g.word_id = w.id
                    WHERE w.surface LIKE ? OR w.reading_kana LIKE ? OR g.text LIKE ?
                    ORDER BY w.is_common DESC, LENGTH(w.surface), w.id
                    LIMIT ?
                    """, arguments: [q, q, q, limit])
                return try rows.map { row in
                    let id: Int = row["id"]
                    func gloss(_ lang: String) throws -> String? {
                        try String.fetchOne(
                            db, sql: "SELECT text FROM word_gloss WHERE word_id = ? AND lang = ? LIMIT 1",
                            arguments: [id, lang])
                    }
                    return WordEntry(
                        id: id, surface: row["surface"], reading: row["reading_kana"],
                        meaningEn: try gloss("en"), meaningKo: try gloss("ko"),
                        meaningJa: try gloss("ja"), meaningZh: try gloss("zh"))
                }
            }
        },
        jlptQuestions: { kanjiIDs, perKanji in
            guard !kanjiIDs.isEmpty else { return [] }
            let queue = try openBundledDatabase()
            let placeholders = kanjiIDs.map { _ in "?" }.joined(separator: ",")
            return try await queue.read { db -> [JLPTQuestion] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, kanji_id, level, kind, prompt, options, answer, explanations, focus
                    FROM jlpt_question
                    WHERE kanji_id IN (\(placeholders))
                    ORDER BY kanji_id, id
                    """, arguments: StatementArguments(kanjiIDs))
                // Reconstruct options (stored as a JSON array of strings) and cap
                // the number of questions kept per kanji.
                var perKanjiCount: [Int: Int] = [:]
                var out: [JLPTQuestion] = []
                for row in rows {
                    let kid: Int = row["kanji_id"]
                    let kept = perKanjiCount[kid, default: 0]
                    guard kept < perKanji else { continue }
                    let optionsJSON: String = row["options"]
                    guard let data = optionsJSON.data(using: .utf8),
                          let options = try? JSONDecoder().decode([String].self, from: data),
                          options.count >= 2 else { continue }
                    perKanjiCount[kid] = kept + 1
                    // Explanations are a JSON object (lang → 해설).
                    var explanations: [String: String] = [:]
                    if let ex: String = row["explanations"], let d = ex.data(using: .utf8),
                       let map = try? JSONDecoder().decode([String: String].self, from: d) {
                        explanations = map
                    }
                    out.append(JLPTQuestion(
                        id: row["id"], kanjiID: kid, level: row["level"], kind: row["kind"],
                        prompt: row["prompt"], options: options, answer: row["answer"],
                        explanations: explanations, focus: row["focus"]))
                }
                return out
            }
        },
        examQuestions: { level, kind, limit in
            let queue = try openBundledDatabase()
            // "N5" → jlpt_level; "10級" → kanken_level. Column name is a controlled
            // constant (not user input), so interpolation is safe.
            let column = level.hasPrefix("N") ? "jlpt_level" : "kanken_level"
            return try await queue.read { db -> [JLPTQuestion] in
                // Questions for kanji at the level, of the requested kind.
                // RANDOM() so each practice run draws a fresh set.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT q.id, q.kanji_id, q.level, q.kind, q.prompt, q.options,
                           q.answer, q.explanations, q.focus
                    FROM jlpt_question q
                    JOIN kanji k ON k.id = q.kanji_id
                    WHERE k.\(column) = ? AND q.kind = ?
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [level, kind, limit])
                var out: [JLPTQuestion] = []
                for row in rows {
                    let optionsJSON: String = row["options"]
                    guard let data = optionsJSON.data(using: .utf8),
                          let options = try? JSONDecoder().decode([String].self, from: data),
                          options.count >= 2 else { continue }
                    var explanations: [String: String] = [:]
                    if let ex: String = row["explanations"], let d = ex.data(using: .utf8),
                       let map = try? JSONDecoder().decode([String: String].self, from: d) {
                        explanations = map
                    }
                    out.append(JLPTQuestion(
                        id: row["id"], kanjiID: row["kanji_id"], level: row["level"],
                        kind: row["kind"], prompt: row["prompt"], options: options,
                        answer: row["answer"], explanations: explanations, focus: row["focus"]))
                }
                return out
            }
        },
        examRadicalItems: { level, limit in
            let queue = try openBundledDatabase()
            let column = level.hasPrefix("N") ? "jlpt_level" : "kanken_level"
            return try await queue.read { db -> [RadicalItem] in
                // `radical` is a KANGXI index (Int 1…214); map it to its 部首 glyph
                // for display. Kanji whose radical index has no glyph are skipped.
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, literal, radical FROM kanji
                    WHERE \(column) = ? AND radical IS NOT NULL AND radical > 0
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [level, limit])
                return rows.compactMap { row -> RadicalItem? in
                    let index: Int = row["radical"]
                    guard let glyph = kangxiRadical(index) else { return nil }
                    return RadicalItem(kanjiID: row["id"], literal: row["literal"], radical: glyph)
                }
            }
        },
        examStrokeItems: { level, limit in
            let queue = try openBundledDatabase()
            let column = level.hasPrefix("N") ? "jlpt_level" : "kanken_level"
            return try await queue.read { db -> [StrokeItem] in
                let rows = try Row.fetchAll(db, sql: """
                    SELECT id, literal, stroke_count FROM kanji
                    WHERE \(column) = ? AND stroke_count > 0
                    ORDER BY RANDOM()
                    LIMIT ?
                    """, arguments: [level, limit])
                return rows.map { StrokeItem(
                    kanjiID: $0["id"], literal: $0["literal"], strokeCount: $0["stroke_count"]) }
            }
        }
    )

    /// The bundled dictionary DB, opened once and shared. A `DatabaseQueue` is
    /// thread-safe and long-lived, so every endpoint reuses this single
    /// read-only connection instead of reopening the file per call.
    private static let bundledQueue: Result<DatabaseQueue, Error> =
        Result { try makeBundledDatabase() }

    private static func openBundledDatabase() throws -> DatabaseQueue {
        try bundledQueue.get()
    }

    private static func makeBundledDatabase() throws -> DatabaseQueue {
        guard let url = Bundle.module.url(forResource: "kanji", withExtension: "sqlite") else {
            throw DictionaryError.databaseUnavailable
        }
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: url.path, configuration: config)
    }
}
