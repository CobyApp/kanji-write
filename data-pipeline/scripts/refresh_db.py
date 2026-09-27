#!/usr/bin/env python3
"""Refresh the repository-owned content of an already-built kanji.sqlite.

A from-scratch build needs KANJIDIC2, JMdict and Tatoeba at the exact bytes
fetch_sources.sh pins, and those publishers only serve a mutable "latest"
snapshot — once they move on, the pinned build cannot be reproduced, and a
rebuild against the new snapshot shifts word ids out from under the gloss
files. Everything this project authors itself does not depend on those
snapshots, so it can be reloaded into the shipped database in place:

* the question banks (every *_questions.jsonl, same order as build_db),
* the 四字熟語 and 対義語・類義語 tables,
* the JLPT vocabulary levels on `word`.

Then it runs the same content gates build_db does for those tables.

Usage:
    python scripts/refresh_db.py [--db ../app/Sources/DictionaryClient/Resources/kanji.sqlite]
"""
from __future__ import annotations

import argparse
import shutil
import sqlite3
import tempfile
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from kanjipipe.build_db import RESOURCE_DIR  # noqa: E402
from kanjipipe.ingest.jlpt_questions import parse_jlpt_questions  # noqa: E402
from kanjipipe.ingest.jlpt_vocab import parse_jlpt_vocab  # noqa: E402
from kanjipipe.ingest.kanjivg_parts import parse_kanjivg_parts  # noqa: E402
from kanjipipe.similar import load_similar  # noqa: E402
from kanjipipe.loader import (  # noqa: E402
    load_jlpt_questions, load_kanji_parts, load_taigirui, load_word_jlpt_levels,
    load_yojijukugo)
from kanjipipe.validate import question_defects, starved_sections  # noqa: E402

QUESTION_FILES = (  # build_db's load order; INSERT OR IGNORE keeps the first
    "sources/jlpt_questions.jsonl",
    "sources/kanken_advanced_questions.jsonl",
    "sources/kanken_doonkun_questions.jsonl",
    "sources/kanken_shikibetsu_questions.jsonl",
    "sources/kanken_derived_questions.jsonl",
    "sources/kanken_authored_questions.jsonl",
    "sources/kanken_rare_kun_questions.jsonl",
)


def ensure_kanji_part_columns(conn: sqlite3.Connection) -> None:
    columns = {row[1] for row in conn.execute("PRAGMA table_info(kanji)")}
    for name in ("radical_form", "parts"):
        if name not in columns:
            conn.execute(f"ALTER TABLE kanji ADD COLUMN {name} TEXT")


def ensure_word_jlpt_column(conn: sqlite3.Connection) -> None:
    columns = {row[1] for row in conn.execute("PRAGMA table_info(word)")}
    if "jlpt_level" not in columns:
        conn.execute("ALTER TABLE word ADD COLUMN jlpt_level TEXT")
    conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_word_jlpt_level ON word(jlpt_level)")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(RESOURCE_DIR / "kanji.sqlite"))
    parser.add_argument("--jlpt-vocab", default=str(ROOT / "sources/jlpt_vocab"))
    # KanjiVG is pinned to a release, so its parts can be refreshed in place.
    parser.add_argument("--kanjivg", default=str(ROOT / "sources/kanjivg.xml"))
    args = parser.parse_args()

    # Work on a copy so a failed gate leaves the shipped database untouched.
    work = Path(tempfile.mkdtemp()) / "kanji.sqlite"
    shutil.copyfile(args.db, work)
    conn = sqlite3.connect(work)
    try:
        ensure_word_jlpt_column(conn)
        ensure_kanji_part_columns(conn)
        if Path(args.kanjivg).exists():
            with_parts = load_kanji_parts(conn, parse_kanjivg_parts(args.kanjivg))
            print(f"kanji with a radical form: {with_parts}")
        print(f"look-alike pairs: {load_similar(conn)}")
        tagged = load_word_jlpt_levels(conn, parse_jlpt_vocab(args.jlpt_vocab))

        conn.execute("DELETE FROM jlpt_question")
        for rel in QUESTION_FILES:
            path = ROOT / rel
            if path.exists():
                load_jlpt_questions(conn, parse_jlpt_questions(path))

        conn.execute("DELETE FROM yojijukugo")
        load_yojijukugo(conn, RESOURCE_DIR / "yojijukugo.source.json")
        conn.execute("DELETE FROM taigirui")
        load_taigirui(conn, RESOURCE_DIR / "taigirui.source.json")
        conn.commit()

        questions = conn.execute("SELECT COUNT(*) FROM jlpt_question").fetchone()[0]
        yoji = conn.execute("SELECT COUNT(*) FROM yojijukugo").fetchone()[0]
        pairs = conn.execute("SELECT COUNT(*) FROM taigirui").fetchone()[0]
        print(f"words tagged with a JLPT level: {tagged}")
        print(f"questions: {questions}  四字熟語: {yoji}  対義・類義: {pairs}")

        failed = False
        starved = starved_sections(conn)
        if starved:
            failed = True
            print("starved sections:")
            for line in starved:
                print("  " + line)
        defects = question_defects(conn)
        if defects:
            failed = True
            for name, cases in defects.items():
                print(f"{name}: {len(cases)}")
                for case in cases[:5]:
                    print("  " + case)
        if failed:
            print(f"not written; the refreshed copy is at {work}")
            return 1
        conn.execute("VACUUM")
    finally:
        conn.close()
    shutil.move(work, args.db)
    print(f"OK — wrote {args.db}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
