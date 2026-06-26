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
                    SELECT id, literal, stroke_count, grade, jlpt_level
                    FROM kanji
                    ORDER BY id
                    """)
                return try kanjiRows.map { row in
                    let id: Int = row["id"]
                    let grade: Int? = row["grade"]
                    let jlpt: String? = row["jlpt_level"]

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
                        onReadings: onReadings,
                        kunReadings: kunReadings
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
                    db, sql: "SELECT lang, text FROM gloss WHERE kanji_id = ?",
                    arguments: [kanjiID]
                ) {
                    let lang: String = row["lang"]
                    result[lang] = row["text"]
                }
                return result
            }
        },
        words: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [WordEntry] in
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
                    return WordEntry(
                        id: id, surface: row["surface"],
                        reading: row["reading_kana"], meaningEn: meaning)
                }
            }
        },
        sentences: { kanjiID, limit in
            let queue = try openBundledDatabase()
            return try await queue.read { db -> [ExampleSentence] in
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
        }
    )

    /// Opens the placeholder dictionary DB bundled with this module, read-only.
    private static func openBundledDatabase() throws -> DatabaseQueue {
        guard let url = Bundle.module.url(forResource: "kanji", withExtension: "sqlite") else {
            throw DictionaryError.databaseUnavailable
        }
        var config = Configuration()
        config.readonly = true
        return try DatabaseQueue(path: url.path, configuration: config)
    }
}
