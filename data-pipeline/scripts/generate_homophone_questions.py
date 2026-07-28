#!/usr/bin/env python3
"""Generate the 同音・同訓異字 bank for every 漢検 level.

漢検 tests this from 8級 up: a word with one kanji blanked, and four kanji that
all share the reading, so the reading itself is no help and only the meaning
picks the answer. That is the same shape as 書き取り with a different candidate
pool, so it reuses the same builder and the same safety rule — a candidate is
rejected when substituting it spells a word that also exists.

Run after a build, then rebuild so the questions are ingested:

    python -m kanjipipe.build_db --out out/kanji.sqlite
    python scripts/generate_homophone_questions.py
    python -m kanjipipe.build_db --out out/kanji.sqlite
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

from kanjipipe.questions import WordRow, build_orthography_question  # noqa: E402

# The levels whose paper actually contains 同音異字 / 同音・同訓異字.
LEVELS = ("8級", "7級", "6級", "5級", "4級", "3級", "準2級", "2級")
# Easiest first. A distractor must be a kanji the learner could plausibly know,
# so it is drawn from this level or an easier one — offering a 5級 candidate the
# obscure 鐫 tests nothing, since it is eliminated on sight.
LEVEL_ORDER = ("10級", "9級", "8級", "7級", "6級", "5級", "4級", "3級",
               "準2級", "2級", "準1級", "1級")
RANK = {level: index for index, level in enumerate(LEVEL_ORDER)}
PER_KANJI = 2


def _to_hiragana(katakana: str) -> str:
    return "".join(
        chr(ord(ch) - 0x60) if "ァ" <= ch <= "ヶ" else ch for ch in katakana)
SEED = 20260728


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--out", default="sources/kanken_doonkun_questions.jsonl")
    args = parser.parse_args()

    con = sqlite3.connect(args.db)
    level_of = {
        literal: level for literal, level in con.execute(
            "SELECT k.literal, km.level_label FROM kanji k "
            "JOIN kanken_membership km ON km.kanji_id = k.id")
    }
    # Kanji grouped by 音読み, which is what makes a distractor a homophone.
    by_on: dict[str, list[str]] = defaultdict(list)
    on_of: dict[str, set[str]] = defaultdict(set)
    for literal, value in con.execute(
            "SELECT k.literal, r.value FROM kanji k JOIN reading r ON r.kanji_id = k.id "
            "WHERE r.lang_axis = 'on' AND r.is_common = 1"):
        by_on[value].append(literal)
        on_of[literal].add(value)

    words_by_literal: dict[str, list[WordRow]] = defaultdict(list)
    for surface, reading, en, ko, literal in con.execute("""
        SELECT w.surface, w.reading_kana,
               (SELECT text FROM word_gloss WHERE word_id = w.id AND lang='en' LIMIT 1),
               (SELECT text FROM word_gloss WHERE word_id = w.id AND lang='ko' LIMIT 1),
               k.literal
        FROM word w
        JOIN word_kanji wk ON wk.word_id = w.id
        JOIN kanji k ON k.id = wk.kanji_id
        WHERE w.is_common = 1
        ORDER BY LENGTH(w.surface), w.id
        """):
        words_by_literal[literal].append(WordRow(surface, reading, en, ko))
    all_surfaces = {row[0] for row in con.execute("SELECT surface FROM word")}
    con.close()

    rng = random.Random(SEED)
    out: list[dict] = []
    stats = defaultdict(int)
    for literal, level in sorted(level_of.items()):
        if level not in LEVELS:
            continue
        # Homophones: every other kanji sharing any of this one's on-readings.
        limit = RANK[level]
        homophones = sorted({
            other
            for reading in on_of.get(literal, ())
            for other in by_on.get(reading, ())
            if other != literal and RANK.get(level_of.get(other, ""), 99) <= limit
        })
        if len(homophones) < 3:
            stats["too few homophones"] += 1
            continue
        rng.shuffle(homophones)
        # The point of 同音異字 is that the reading does not disambiguate, so
        # the kanji has to actually be read with one of its 音 here. 悪戯 is
        # read いたずら as a whole (熟字訓) — no 音 is being contrasted, and
        # offering homophones of ギ tests nothing.
        on_kana = {_to_hiragana(value) for value in on_of.get(literal, ())}
        made = 0
        for word in words_by_literal.get(literal, []):
            if made >= PER_KANJI:
                break
            if not any(reading in word.reading for reading in on_kana):
                continue
            q = build_orthography_question(
                word, literal=literal, level=level, kind="doonkun",
                candidates=homophones[:30], real_surfaces=all_surfaces, rng=rng)
            if q is not None:
                out.append(q)
                made += 1
        stats[level] += made
        if made == 0:
            stats["no safe question"] += 1

    Path(args.out).write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")
    print(f"wrote {len(out)} 同音・同訓異字 questions → {args.out}")
    for level in LEVELS:
        print(f"  {level}: {stats[level]}")
    print(f"  kanji with fewer than 3 homophones: {stats['too few homophones']}")
    print(f"  kanji with no safe question: {stats['no safe question']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
