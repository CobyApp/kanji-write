#!/usr/bin/env python3
"""Generate the 準1級/1級 exam bank from a built kanji.sqlite.

Run after a build, then rebuild so the questions are ingested:

    python -m kanjipipe.build_db --out out/kanji.sqlite
    python scripts/generate_advanced_questions.py
    python -m kanjipipe.build_db --out out/kanji.sqlite

The two-pass shape is deliberate: the generator needs the vocabulary and
readings the build produces, and the build needs the questions the generator
produces. The intermediate JSONL is committed, so a plain build stays
reproducible without re-running this.
"""
from __future__ import annotations

import argparse
import json
import random
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from kanjipipe.questions import (  # noqa: E402
    WordRow,
    build_orthography_question,
    build_reading_question,
)

ADVANCED = ("準1級", "1級")
# Enough for a full 大問 without letting one prolific kanji dominate the draw.
PER_KANJI_PER_KIND = 3
SEED = 20260728


def load(db: Path):
    con = sqlite3.connect(db)
    kanji = {
        literal: level
        for literal, level in con.execute(
            "SELECT literal, kanken_level FROM kanji WHERE kanken_level IN (?, ?)",
            ADVANCED)
    }
    words_by_literal: dict[str, list[WordRow]] = defaultdict(list)
    readings_by_surface: dict[str, set[str]] = defaultdict(set)
    for surface, reading, en, ko, literal in con.execute("""
        SELECT w.surface, w.reading_kana,
               (SELECT text FROM word_gloss WHERE word_id = w.id AND lang='en' LIMIT 1),
               (SELECT text FROM word_gloss WHERE word_id = w.id AND lang='ko' LIMIT 1),
               k.literal
        FROM word w
        JOIN word_kanji wk ON wk.word_id = w.id
        JOIN kanji k ON k.id = wk.kanji_id
        WHERE k.kanken_level IN (?, ?)
        ORDER BY w.is_common DESC, LENGTH(w.surface), w.id
        """, ADVANCED):
        words_by_literal[literal].append(WordRow(surface, reading, en, ko))
    # Every reading any surface is known to take — a homograph's other reading
    # must never be offered as a wrong answer.
    for surface, reading in con.execute("SELECT surface, reading_kana FROM word"):
        readings_by_surface[surface].add(reading)
    all_surfaces = set(readings_by_surface)
    # 部首 and stroke count are what make a wrong kanji look right, so group
    # the candidate pool by radical.
    by_radical: dict[int, list[str]] = defaultdict(list)
    for literal, radical in con.execute(
            "SELECT literal, radical FROM kanji WHERE radical IS NOT NULL"):
        by_radical[radical].append(literal)
    radical_of = dict(con.execute(
        "SELECT literal, radical FROM kanji WHERE radical IS NOT NULL"))
    con.close()
    return kanji, words_by_literal, readings_by_surface, all_surfaces, by_radical, radical_of


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--out", default="sources/kanken_advanced_questions.jsonl")
    args = parser.parse_args()

    (kanji, words_by_literal, readings_by_surface,
     all_surfaces, by_radical, radical_of) = load(Path(args.db))

    rng = random.Random(SEED)
    # Plausible wrong readings, keyed by (kanji in the surface, reading length).
    # Length alone is not enough: a two-kanji 音読み compound next to a kun
    # reading verb of the same mora count is eliminable on shape, without
    # knowing the kanji at all. Matching the character count keeps the register
    # — on-reading compounds compete with on-reading compounds.
    def _shape(surface: str, reading: str) -> tuple[int, int]:
        return sum(ch > "㄀" for ch in surface), len(reading)

    reading_pool = sorted({r for rs in readings_by_surface.values() for r in rs})
    by_shape: dict[tuple[int, int], list[str]] = defaultdict(list)
    for surface, readings in readings_by_surface.items():
        for reading in readings:
            by_shape[_shape(surface, reading)].append(reading)

    out: list[dict] = []
    # 顰蹙 is vocabulary for both 顰 and 蹙, so without this the same 読み
    # question is emitted twice and can surface twice in one 大問.
    seen_surfaces: set[str] = set()
    stats = defaultdict(int)
    for literal, level in sorted(kanji.items()):
        words = words_by_literal.get(literal, [])
        if not words:
            stats["kanji_without_words"] += 1
            continue
        made_reading = made_ortho = 0
        for word in words:
            neighbours = by_shape.get(_shape(word.surface, word.reading), [])
            if len(neighbours) < 8:  # too rare a shape to draw from safely
                neighbours = neighbours + reading_pool[:200]
            if made_reading < PER_KANJI_PER_KIND and word.surface not in seen_surfaces:
                q = build_reading_question(
                    word, literal=literal, level=level,
                    other_readings=rng.sample(neighbours, min(40, len(neighbours))),
                    forbidden=readings_by_surface.get(word.surface, set()),
                    rng=rng)
                if q is not None:
                    out.append(q)
                    seen_surfaces.add(word.surface)
                    made_reading += 1
            if made_ortho < PER_KANJI_PER_KIND:
                radical = radical_of.get(literal)
                candidates = [c for c in by_radical.get(radical, []) if c != literal]
                rng.shuffle(candidates)
                q = build_orthography_question(
                    word, literal=literal, level=level,
                    candidates=candidates[:30],
                    real_surfaces=all_surfaces, rng=rng)
                if q is not None:
                    out.append(q)
                    made_ortho += 1
            if made_reading >= PER_KANJI_PER_KIND and made_ortho >= PER_KANJI_PER_KIND:
                break
        stats["reading"] += made_reading
        stats["orthography"] += made_ortho
        if made_reading == 0 and made_ortho == 0:
            stats["kanji_with_words_but_no_question"] += 1

    out_path = Path(args.out)
    out_path.write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")

    covered = len({q["literal"] for q in out})
    print(f"wrote {len(out)} questions → {out_path}")
    print(f"  reading={stats['reading']} orthography={stats['orthography']}")
    print(f"  advanced kanji covered: {covered}/{len(kanji)}")
    print(f"  no vocabulary at all: {stats['kanji_without_words']}")
    print(f"  had vocabulary but nothing safe: "
          f"{stats['kanji_with_words_but_no_question']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
