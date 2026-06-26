# kanjipipe/loader.py
import sqlite3

from kanjipipe.models import Kanji, LlmGloss, Relation, Sentence, Word


def load_kanji(conn: sqlite3.Connection, kanji: list[Kanji]) -> None:
    for k in kanji:
        cur = conn.execute(
            "INSERT INTO kanji "
            "(literal, codepoint, stroke_count, grade, jlpt_level, freq_rank, radical) "
            "VALUES (?, ?, ?, ?, ?, ?, ?)",
            (k.literal, k.codepoint, k.stroke_count, k.grade,
             k.jlpt_level, k.freq_rank, k.radical),
        )
        kanji_id = cur.lastrowid
        for r in k.readings:
            conn.execute(
                "INSERT INTO reading (kanji_id, lang_axis, value, is_common) "
                "VALUES (?, ?, ?, ?)",
                (kanji_id, r.lang_axis, r.value, 1 if r.is_common else 0),
            )
        for g in k.glosses:
            conn.execute(
                "INSERT INTO gloss (kanji_id, lang, text) VALUES (?, ?, ?)",
                (kanji_id, g.lang, g.text),
            )
    conn.commit()


def load_stroke_order(
    conn: sqlite3.Connection,
    strokes_by_codepoint: dict[int, list[str]],
) -> None:
    rows = conn.execute("SELECT id, codepoint FROM kanji").fetchall()
    for kanji_id, codepoint in rows:
        for ordinal, path_d in enumerate(strokes_by_codepoint.get(codepoint, []), start=1):
            conn.execute(
                "INSERT INTO stroke_order (kanji_id, ordinal, path_d) "
                "VALUES (?, ?, ?)",
                (kanji_id, ordinal, path_d),
            )
    conn.commit()


def load_words(conn: sqlite3.Connection, words: list["Word"]) -> None:
    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    for word in words:
        cur = conn.execute(
            "INSERT INTO word (surface, reading_kana, is_common) VALUES (?, ?, ?)",
            (word.surface, word.reading_kana, 1 if word.is_common else 0),
        )
        word_id = cur.lastrowid
        for gloss in word.en_glosses:
            conn.execute(
                "INSERT INTO word_gloss (word_id, lang, text) VALUES (?, 'en', ?)",
                (word_id, gloss),
            )
        linked: set[int] = set()
        for char in word.surface:
            kanji_id = kanji_id_by_literal.get(char)
            if kanji_id is not None and kanji_id not in linked:
                conn.execute(
                    "INSERT INTO word_kanji (word_id, kanji_id) VALUES (?, ?)",
                    (word_id, kanji_id),
                )
                linked.add(kanji_id)
    conn.commit()


def load_sentences(
    conn: sqlite3.Connection,
    sentences: list["Sentence"],
    per_kanji_cap: int = 3,
) -> None:
    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    counts: dict[int, int] = {}
    for sentence in sorted(sentences, key=lambda s: len(s.ja_text)):
        needed: list[int] = []
        seen: set[int] = set()
        for char in sentence.ja_text:
            kanji_id = kanji_id_by_literal.get(char)
            if kanji_id is None or kanji_id in seen:
                continue
            seen.add(kanji_id)
            if counts.get(kanji_id, 0) < per_kanji_cap:
                needed.append(kanji_id)
        if not needed:
            continue
        cur = conn.execute(
            "INSERT INTO sentence (text_ja) VALUES (?)", (sentence.ja_text,))
        sentence_id = cur.lastrowid
        for lang, text in sentence.translations.items():
            conn.execute(
                "INSERT INTO sentence_translation (sentence_id, lang, text) "
                "VALUES (?, ?, ?)",
                (sentence_id, lang, text),
            )
        for kanji_id in needed:
            conn.execute(
                "INSERT INTO sentence_kanji (sentence_id, kanji_id) VALUES (?, ?)",
                (sentence_id, kanji_id),
            )
            counts[kanji_id] = counts.get(kanji_id, 0) + 1
    conn.commit()


def load_relations(conn: sqlite3.Connection, relations: list["Relation"]) -> None:
    word_id_by_surface: dict[str, int] = {}
    for word_id, surface in conn.execute("SELECT id, surface FROM word"):
        word_id_by_surface.setdefault(surface, word_id)  # first id wins on duplicates
    for relation in relations:
        a = word_id_by_surface.get(relation.source_surface)
        b = word_id_by_surface.get(relation.target_surface)
        if a is None or b is None or a == b:
            continue
        conn.execute(
            "INSERT OR IGNORE INTO relation (word_id_a, word_id_b, type) "
            "VALUES (?, ?, ?)",
            (a, b, relation.type),
        )
    conn.commit()


def load_llm_glosses(conn: sqlite3.Connection, entries: list["LlmGloss"]) -> None:
    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    for entry in entries:
        kanji_id = kanji_id_by_literal.get(entry.literal)
        if kanji_id is None:
            continue
        for lang, text in (("ko", entry.ko), ("ja", entry.ja), ("zh", entry.zh)):
            if text:
                conn.execute(
                    "INSERT INTO gloss (kanji_id, lang, text, source) "
                    "VALUES (?, ?, ?, 'llm')",
                    (kanji_id, lang, text),
                )
    conn.commit()
