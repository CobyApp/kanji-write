# kanjipipe/loader.py
from __future__ import annotations

import json
import re
import sqlite3
import unicodedata
from pathlib import Path

from kanjipipe.ingest.kanken import memberships_for
from kanjipipe.models import (
    JlptQuestion,
    Kanji,
    KankenAllocation,
    LlmGloss,
    Relation,
    Sentence,
    Word,
)

KANKEN_LEVEL_ORDER = (
    "10級",
    "9級",
    "8級",
    "7級",
    "6級",
    "5級",
    "4級",
    "3級",
    "準2級",
    "2級",
    "準1級",
    "1級",
)
KANKEN_LEVEL_RANK = {
    level: rank for rank, level in enumerate(KANKEN_LEVEL_ORDER)
}


def load_kanji(conn: sqlite3.Connection, kanji: list[Kanji]) -> None:
    for k in kanji:
        cur = conn.execute(
            "INSERT INTO kanji "
            "(literal, codepoint, stroke_count, grade, jlpt_level, kanken_level, "
            "freq_rank, radical) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (k.literal, k.codepoint, k.stroke_count, k.grade,
             k.jlpt_level, k.kanken_level, k.freq_rank, k.radical),
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


def load_kanken_memberships(
    conn: sqlite3.Connection,
    allocations: list[KankenAllocation],
) -> None:
    kanji_by_literal = {
        literal: (kanji_id, kanken_level)
        for kanji_id, literal, kanken_level in conn.execute(
            "SELECT id, literal, kanken_level FROM kanji"
        )
    }
    missing_literals = {
        allocation.literal
        for allocation in allocations
        if allocation.literal is not None
        and allocation.literal not in kanji_by_literal
    }
    if missing_literals:
        missing = ", ".join(sorted(missing_literals))
        raise ValueError(f"Kanken allocation not present in selected inventory: {missing}")

    # A 級 lists the kanji introduced at it, and nothing carried over — that is
    # how every level from 10級 to 準2級 already behaved. Writing one membership
    # row per allocation broke it for 1級 alone, which then also carried the 397
    # kanji the source marks "1/準1級" plus six jōyō characters that have a
    # second, unrelated 1級 allocation (芸 is the 7級 character and a separate
    # 1級 one sharing its glyph). So resolve the introduction level first, then
    # write exactly one membership per kanji.
    introduction_by_kanji_id: dict[int, str] = {}
    classification_by_kanji_id: dict[int, str] = {}
    for allocation in allocations:
        if allocation.literal is None:
            continue
        kanji_id, existing_level = kanji_by_literal[allocation.literal]
        memberships_for(allocation.source_level)  # rejects unknown level labels
        introduction_level = (
            "準1級" if allocation.source_level == "1/準1級"
            else allocation.source_level
        )
        candidates = [
            level
            for level in (
                introduction_by_kanji_id.get(kanji_id),
                existing_level,
                introduction_level,
            )
            if level in KANKEN_LEVEL_RANK
        ]
        resolved = min(candidates, key=KANKEN_LEVEL_RANK.__getitem__)
        if introduction_by_kanji_id.get(kanji_id) != resolved:
            classification_by_kanji_id[kanji_id] = allocation.source_level
        introduction_by_kanji_id[kanji_id] = resolved

    for kanji_id, introduction_level in introduction_by_kanji_id.items():
        conn.execute(
            "UPDATE kanji SET kanken_level = ? WHERE id = ?",
            (introduction_level, kanji_id),
        )
        conn.execute(
            "INSERT OR IGNORE INTO kanken_membership "
            "(kanji_id, level_label, source_classification) VALUES (?, ?, ?)",
            (kanji_id, introduction_level,
             classification_by_kanji_id.get(kanji_id, introduction_level)),
        )
    conn.commit()


def load_yojijukugo(
    conn: sqlite3.Connection,
    path: str | Path,
) -> None:
    entries = json.loads(Path(path).read_text(encoding="utf-8"))
    conn.executemany(
        "INSERT INTO yojijukugo "
        "(yoji, reading, meaning_ja, meaning_ko, meaning_zh, meaning_en, kanken_level) "
        "VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (
                entry["yoji"],
                entry["reading"],
                entry.get("meaningJa"),
                entry.get("meaningKo"),
                entry.get("meaningZh"),
                entry.get("meaningEn"),
                entry["level"],
            )
            for entry in entries
        ],
    )
    conn.commit()


def load_taigirui(
    conn: sqlite3.Connection,
    path: str | Path,
) -> None:
    entries = json.loads(Path(path).read_text(encoding="utf-8"))
    conn.executemany(
        "INSERT INTO taigirui "
        "(word, word_reading, answer, answer_reading, relation, kanken_level) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        [
            (
                entry["word"],
                entry["wordReading"],
                entry["answer"],
                entry["answerReading"],
                entry["relation"],
                entry["level"],
            )
            for entry in entries
        ],
    )
    conn.commit()


def _canonical_strokes(
    codepoint: int,
    stroke_count: int | None,
    strokes_by_codepoint: dict[int, list[str]],
) -> list[str]:
    """Stroke paths for a CJK Compatibility Ideograph, via its unified form.

    Compatibility ideographs (U+F900–FAFF) are canonically equivalent to a
    unified character that KanjiVG does cover, so the unified glyph's strokes can
    stand in — but only sometimes. Many of these exist precisely because the
    printed form differs (隆 U+F9DC is 17 strokes against the unified 11), and
    borrowing there would teach the wrong stroke order. Require the stroke counts
    to agree before substituting; otherwise leave the kanji without stroke data.
    """
    canonical = unicodedata.normalize("NFC", chr(codepoint))
    if len(canonical) != 1 or ord(canonical) == codepoint:
        return []
    paths = strokes_by_codepoint.get(ord(canonical), [])
    if not paths or stroke_count is None or len(paths) != stroke_count:
        return []
    return paths


def load_stroke_order(
    conn: sqlite3.Connection,
    strokes_by_codepoint: dict[int, list[str]],
) -> None:
    rows = conn.execute("SELECT id, codepoint, stroke_count FROM kanji").fetchall()
    for kanji_id, codepoint, stroke_count in rows:
        paths = strokes_by_codepoint.get(codepoint, [])
        if not paths:
            paths = _canonical_strokes(codepoint, stroke_count, strokes_by_codepoint)
        for ordinal, path_d in enumerate(paths, start=1):
            conn.execute(
                "INSERT INTO stroke_order (kanji_id, ordinal, path_d) "
                "VALUES (?, ?, ?)",
                (kanji_id, ordinal, path_d),
            )
    conn.execute(
        "UPDATE kanji SET has_verified_stroke_order = EXISTS ("
        "SELECT 1 FROM stroke_order s WHERE s.kanji_id = kanji.id)"
    )
    conn.commit()


def load_words(
    conn: sqlite3.Connection,
    words: list["Word"],
    advanced_literals: frozenset[str] | set[str] | None = None,
) -> None:
    """Link words to the kanji they are written with.

    Uncommon words only enter the corpus to give 準1級/1級 kanji something to
    practise on, so they are linked to those kanji alone. Linking them to the
    everyday kanji they also contain would bury a 10級 word list under obscure
    vocabulary.
    """
    advanced = frozenset(advanced_literals or ())
    # word.id is an autoincrement rowid, and word_glosses_ko.jsonl /
    # word_glosses_jazh.jsonl address words by exactly that id. Interleaving the
    # uncommon words into JMdict order shifts every id after the first one and
    # repoints all those glosses at the wrong entries — 学校 came out meaning
    # "정면 폭". Load the common words first, in their original order, so their
    # ids match what the gloss files were written against; uncommon vocabulary
    # is appended after the last of them.
    words = ([w for w in words if w.is_common]
             + [w for w in words if not w.is_common])
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
            if not word.is_common and char not in advanced:
                continue
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


def _word_ids_by_surface_reading(
    conn: sqlite3.Connection,
) -> dict[tuple[str, str], list[int]]:
    ids: dict[tuple[str, str], list[int]] = {}
    for word_id, surface, reading in conn.execute(
        "SELECT id, surface, reading_kana FROM word"
    ):
        ids.setdefault((surface, reading), []).append(word_id)
    return ids


def load_word_ko_glosses(
    conn: sqlite3.Connection, entries: list[tuple[str, str, str]]
) -> int:
    """Attach Korean word glosses, matched on surface + kana reading.

    Returns how many entries named a word this build does not have. Ids used to
    be the key and they are autoincrement rowids: any change to the vocabulary
    renumbers them and every later gloss silently lands on the wrong word.
    """
    ids = _word_ids_by_surface_reading(conn)
    unmatched = 0
    for surface, reading, ko in entries:
        word_ids = ids.get((surface, reading))
        if not word_ids:
            unmatched += 1
            continue
        for word_id in word_ids:
            conn.execute(
                "INSERT INTO word_gloss (word_id, lang, text) VALUES (?, 'ko', ?)",
                (word_id, ko),
            )
    conn.commit()
    return unmatched


def load_word_jazh_glosses(
    conn: sqlite3.Connection,
    entries: list[tuple[str, str, str | None, str | None]],
) -> int:
    """As `load_word_ko_glosses`, for the ja/zh file."""
    ids = _word_ids_by_surface_reading(conn)
    unmatched = 0
    for surface, reading, ja, zh in entries:
        word_ids = ids.get((surface, reading))
        if not word_ids:
            unmatched += 1
            continue
        for word_id in word_ids:
            for lang, text in (("ja", ja), ("zh", zh)):
                if text:
                    conn.execute(
                        "INSERT INTO word_gloss (word_id, lang, text) "
                        "VALUES (?, ?, ?)",
                        (word_id, lang, text),
                    )
    conn.commit()
    return unmatched


def load_sentence_glosses(
    conn: sqlite3.Connection,
    entries: list[tuple[str, str | None, str | None, str | None]],
) -> None:
    """Attach LLM ko/zh/en translations to existing sentences, matched by the
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
    for ja, ko, zh, en in entries:
        for sentence_id in ids_by_text.get(ja, ()):
            for lang, text in (("ko", ko), ("zh", zh), ("en", en)):
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


def load_kanji_variants(
    conn: sqlite3.Connection,
    assets: list["GlyphAsset"],
    allocations: list["KankenAllocation"],
    glyph_dir: str | Path,
) -> int:
    """Attach verified variant glyphs to the characters they are variants of.

    The 漢検 list prints some entries only as a picture. 117 of those turned out
    to be head characters and now ship as text; the rest are 旧字 — the old form
    of a character the app already has — and there is no codepoint to show them
    with, only a glyph. Each one becomes a `glyph_asset` row carrying the outline
    and a `kanji_variant` row pointing at its canonical kanji.

    Returns how many variants were attached. Entries whose canonical character is
    not in the inventory are skipped rather than dropped silently by a foreign
    key.
    """
    glyph_dir = Path(glyph_dir)
    kanji_by_literal = dict(conn.execute("SELECT literal, id FROM kanji"))
    by_ce = {a.ce_id: a for a in allocations}
    attached = 0
    for asset in assets:
        allocation = by_ce.get(asset.ce_id)
        canonical_id = kanji_by_literal.get(asset.canonical_literal)
        if allocation is None or canonical_id is None:
            continue
        svg = glyph_dir / asset.local_svg_name
        path_d, view_box = _svg_outline(svg)
        if not path_d:
            continue
        cursor = conn.execute(
            "INSERT OR IGNORE INTO glyph_asset "
            "(provider, glyph_name, revision, sha256, source_url, license_url, "
            " local_svg_name, path_d, view_box) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (asset.provider, asset.glyph_name, asset.revision, asset.sha256,
             asset.source_url, asset.license_url, asset.local_svg_name,
             path_d, view_box),
        )
        asset_id = cursor.lastrowid
        if not asset_id:
            asset_id = conn.execute(
                "SELECT id FROM glyph_asset WHERE sha256 = ?", (asset.sha256,)
            ).fetchone()[0]
        conn.execute(
            "INSERT OR IGNORE INTO kanji_variant "
            "(canonical_kanji_id, glyph_asset_id, source_ct_id, source_ce_id, "
            " variant_kind, literal, codepoint) "
            "VALUES (?, ?, ?, ?, ?, NULL, NULL)",
            (canonical_id, asset_id, allocation.ct_id, asset.ce_id,
             allocation.variant_kind),
        )
        attached += 1
    conn.commit()
    return attached


def _svg_outline(path: Path) -> tuple[str, int]:
    """The `d` string and box size of a single-path SVG, or ("", 0).

    GlyphWiki serves one filled path on a square viewBox, which is why the whole
    glyph fits in a column instead of needing the file shipped.
    """
    if not path.exists():
        return "", 0
    text = path.read_text(encoding="utf-8")
    paths = re.findall(r'<path[^>]*\bd="([^"]+)"', text)
    if len(paths) != 1:
        return "", 0
    box = re.search(r'viewBox="0 0 (\d+) (\d+)"', text)
    if not box or box.group(1) != box.group(2):
        return "", 0
    return paths[0], int(box.group(1))


def load_word_jlpt_levels(
    conn: sqlite3.Connection,
    levels: dict[tuple[str, str], str],
) -> int:
    """Tag words with the JLPT level of the vocabulary list they appear on.

    Matches on (surface, reading) first. A list entry whose reading differs
    only in how JMdict chose to spell it still counts when the surface names a
    single word — two words sharing a surface stay untagged rather than guessed.
    Returns the number of words tagged.
    """
    conn.execute("UPDATE word SET jlpt_level = NULL")
    ids_by_pair: dict[tuple[str, str], list[int]] = {}
    ids_by_surface: dict[str, list[int]] = {}
    for word_id, surface, reading in conn.execute(
            "SELECT id, surface, reading_kana FROM word"):
        ids_by_pair.setdefault((surface, reading), []).append(word_id)
        ids_by_surface.setdefault(surface, []).append(word_id)
    tagged: dict[int, str] = {}
    for (surface, reading), level in levels.items():
        ids = ids_by_pair.get((surface, reading))
        if ids is None:
            candidates = ids_by_surface.get(surface, [])
            ids = candidates if len(candidates) == 1 else []
        for word_id in ids:
            tagged.setdefault(word_id, level)
    conn.executemany("UPDATE word SET jlpt_level = ? WHERE id = ?",
                     [(level, word_id) for word_id, level in tagged.items()])
    conn.commit()
    return len(tagged)
