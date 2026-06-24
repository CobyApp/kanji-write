# kanjipipe/loader.py
import sqlite3

from kanjipipe.models import Kanji, Word


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
