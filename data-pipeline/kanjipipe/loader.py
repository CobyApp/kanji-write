# kanjipipe/loader.py
from __future__ import annotations

import sqlite3

from kanjipipe.models import JlptQuestion, Kanji, LlmGloss, Relation, Sentence, Word


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


def load_sentence_words(conn: sqlite3.Connection, per_word_cap: int = 3) -> None:
    """Link each stored sentence to the words it contains.

    No JA tokenizer is available, so this works purely from stored rows: a word
    is a candidate for a sentence when it shares ≥1 kanji with the sentence
    text, and is linked when its `surface` occurs verbatim in the text. Shortest
    sentences first, capped per word so a common word doesn't collect thousands.
    Idempotent: safe to run on an existing DB (INSERT OR IGNORE + UNIQUE).
    """
    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    words_by_kanji: dict[int, list[tuple[int, str]]] = {}
    for word_id, kanji_id, surface in conn.execute(
        "SELECT wk.word_id, wk.kanji_id, w.surface "
        "FROM word_kanji wk JOIN word w ON w.id = wk.word_id"
    ):
        words_by_kanji.setdefault(kanji_id, []).append((word_id, surface))

    word_counts: dict[int, int] = {}
    for sentence_id, text in conn.execute(
        "SELECT id, text_ja FROM sentence ORDER BY length(text_ja), id"
    ):
        seen_kanji = {
            kanji_id_by_literal[c] for c in text if c in kanji_id_by_literal
        }
        linked: set[int] = set()
        for kanji_id in seen_kanji:
            for word_id, surface in words_by_kanji.get(kanji_id, ()):
                if word_id in linked or word_counts.get(word_id, 0) >= per_word_cap:
                    continue
                if surface in text:
                    conn.execute(
                        "INSERT OR IGNORE INTO sentence_word (sentence_id, word_id) "
                        "VALUES (?, ?)",
                        (sentence_id, word_id),
                    )
                    linked.add(word_id)
                    word_counts[word_id] = word_counts.get(word_id, 0) + 1
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


def load_word_ko_glosses(
    conn: sqlite3.Connection, entries: list[tuple[int, str]]
) -> None:
    for word_id, ko in entries:
        conn.execute(
            "INSERT INTO word_gloss (word_id, lang, text) VALUES (?, 'ko', ?)",
            (word_id, ko),
        )
    conn.commit()


def load_word_jazh_glosses(
    conn: sqlite3.Connection,
    entries: list[tuple[int, str | None, str | None]],
) -> None:
    for word_id, ja, zh in entries:
        if ja:
            conn.execute(
                "INSERT INTO word_gloss (word_id, lang, text) VALUES (?, 'ja', ?)",
                (word_id, ja),
            )
        if zh:
            conn.execute(
                "INSERT INTO word_gloss (word_id, lang, text) VALUES (?, 'zh', ?)",
                (word_id, zh),
            )
    conn.commit()


def load_sentence_glosses(
    conn: sqlite3.Connection,
    entries: list[tuple[str, str | None, str | None]],
) -> None:
    """Attach LLM ko/zh translations to existing sentences, matched by the
    Japanese text. Skips a (sentence, lang) pair that already has a translation
    (e.g. one Tatoeba supplied) so this never duplicates or overwrites."""
    ids_by_text: dict[str, list[int]] = {}
    for sentence_id, text in conn.execute("SELECT id, text_ja FROM sentence"):
        ids_by_text.setdefault(text, []).append(sentence_id)
    existing: set[tuple[int, str]] = {
        (sentence_id, lang)
        for sentence_id, lang in conn.execute(
            "SELECT sentence_id, lang FROM sentence_translation")
    }
    for ja, ko, zh in entries:
        for sentence_id in ids_by_text.get(ja, ()):
            for lang, text in (("ko", ko), ("zh", zh)):
                if text and (sentence_id, lang) not in existing:
                    conn.execute(
                        "INSERT INTO sentence_translation (sentence_id, lang, text) "
                        "VALUES (?, ?, ?)",
                        (sentence_id, lang, text),
                    )
                    existing.add((sentence_id, lang))
    conn.commit()


def load_jlpt_questions(conn: sqlite3.Connection, questions: list["JlptQuestion"]) -> None:
    import json as _json

    kanji_id_by_literal = {
        literal: kanji_id
        for kanji_id, literal in conn.execute("SELECT id, literal FROM kanji")
    }
    for q in questions:
        kanji_id = kanji_id_by_literal.get(q.literal)
        if kanji_id is None:
            continue
        conn.execute(
            "INSERT OR IGNORE INTO jlpt_question "
            "(kanji_id, level, kind, prompt, options, answer, explanations, focus) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (kanji_id, q.level, q.kind, q.prompt,
             _json.dumps(q.options, ensure_ascii=False), q.answer,
             _json.dumps(q.explanations, ensure_ascii=False), q.focus),
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
