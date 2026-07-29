#!/usr/bin/env python3
"""Report — and emit batches for — the content the app cannot show in every language.

The app offers ko/ja/zh/en. Kanji glosses and question explanations are complete
in all four; three other kinds of content are not, and each is missing something
different:

* word glosses — English comes from JMdict for all 42,966 words, but ko/ja/zh
  were only ever written for the 25,484 common ones. The rest are the uncommon
  words that advanced kanji needed, and they are what a 準1級/1級 kanji page
  shows, so a Korean reader gets English there.
* sentence translations — Japanese is the sentence itself, so only ko/zh/en can
  be missing. Tatoeba supplies them unevenly.
* 四字熟語 meanings — the table shipped with ja and ko columns only.

    python scripts/l10n_gaps.py                        # summary
    python scripts/l10n_gaps.py --emit words --limit 300 --offset 0
    python scripts/l10n_gaps.py --emit sentences --lang ko --limit 300
    python scripts/l10n_gaps.py --emit yoji --limit 100
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys

KINDS = ("words", "sentences", "yoji")


def summary(conn: sqlite3.Connection) -> None:
    q = conn.execute
    total_w = q("SELECT COUNT(*) FROM word").fetchone()[0]
    print(f"words {total_w}")
    for lang in ("ko", "ja", "zh", "en"):
        n = q("SELECT COUNT(*) FROM word w WHERE NOT EXISTS "
              "(SELECT 1 FROM word_gloss g WHERE g.word_id = w.id AND g.lang = ?)",
              (lang,)).fetchone()[0]
        print(f"  missing {lang}: {n}")
    total_s = q("SELECT COUNT(*) FROM sentence").fetchone()[0]
    print(f"sentences {total_s}")
    for lang in ("ko", "zh", "en"):
        n = q("SELECT COUNT(*) FROM sentence s WHERE NOT EXISTS "
              "(SELECT 1 FROM sentence_translation t "
              "WHERE t.sentence_id = s.id AND t.lang = ?)", (lang,)).fetchone()[0]
        print(f"  missing {lang}: {n}")
    total_y = q("SELECT COUNT(*) FROM yojijukugo").fetchone()[0]
    print(f"四字熟語 {total_y}")
    for col in ("meaning_ja", "meaning_ko", "meaning_zh", "meaning_en"):
        n = q(f"SELECT COUNT(*) FROM yojijukugo "
              f"WHERE {col} IS NULL OR {col} = ''").fetchone()[0]
        print(f"  missing {col[8:]}: {n}")


def emit_words(conn: sqlite3.Connection, limit: int, offset: int) -> list[dict]:
    # Ordered by id so a batch is reproducible and two runs never overlap. The
    # English gloss plus the kanji that pulled the word in are the whole context
    # a translator needs.
    rows = conn.execute("""
        SELECT w.id, w.surface, w.reading_kana,
               (SELECT text FROM word_gloss g
                WHERE g.word_id = w.id AND g.lang = 'en' LIMIT 1) AS en
        FROM word w
        WHERE NOT EXISTS (SELECT 1 FROM word_gloss g
                          WHERE g.word_id = w.id AND g.lang = 'ko')
        ORDER BY w.id
        LIMIT ? OFFSET ?
        """, (limit, offset)).fetchall()
    return [{"id": r[0], "surface": r[1], "reading": r[2], "en": r[3]} for r in rows]


def emit_sentences(conn: sqlite3.Connection, lang: str, limit: int,
                   offset: int) -> list[dict]:
    rows = conn.execute("""
        SELECT s.id, s.text_ja,
               (SELECT text FROM sentence_translation t
                WHERE t.sentence_id = s.id AND t.lang = 'en' LIMIT 1) AS en
        FROM sentence s
        WHERE NOT EXISTS (SELECT 1 FROM sentence_translation t
                          WHERE t.sentence_id = s.id AND t.lang = ?)
        ORDER BY s.id
        LIMIT ? OFFSET ?
        """, (lang, limit, offset)).fetchall()
    return [{"id": r[0], "ja": r[1], "en": r[2]} for r in rows]


def emit_yoji(conn: sqlite3.Connection, limit: int, offset: int) -> list[dict]:
    rows = conn.execute("""
        SELECT yoji, reading, meaning_ja, meaning_ko FROM yojijukugo
        WHERE meaning_zh IS NULL OR meaning_zh = ''
           OR meaning_en IS NULL OR meaning_en = ''
        ORDER BY id LIMIT ? OFFSET ?
        """, (limit, offset)).fetchall()
    return [{"yoji": r[0], "reading": r[1], "ja": r[2], "ko": r[3]} for r in rows]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--emit", choices=KINDS)
    parser.add_argument("--lang", default="ko", choices=("ko", "zh", "en"))
    parser.add_argument("--limit", type=int, default=300)
    parser.add_argument("--offset", type=int, default=0)
    args = parser.parse_args()

    conn = sqlite3.connect(args.db)
    if not args.emit:
        summary(conn)
        return 0
    if args.emit == "words":
        batch = emit_words(conn, args.limit, args.offset)
    elif args.emit == "sentences":
        batch = emit_sentences(conn, args.lang, args.limit, args.offset)
    else:
        batch = emit_yoji(conn, args.limit, args.offset)
    json.dump(batch, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
