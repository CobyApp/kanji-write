#!/usr/bin/env python3
"""Report which kanji still lack a gloss in one of the app's languages.

The app offers ko/ja/zh/en. English comes from kanjidic2 for every kanji, but
ko/ja/zh are curated in sources/llm_glosses.jsonl, and the advanced levels were
only ever given Korean. This prints the outstanding work and can emit the next
batch to translate, so a run is verifiable instead of guessed at.

    python scripts/gloss_gaps.py                  # summary
    python scripts/gloss_gaps.py --emit ja --limit 200 > batch.json
"""
from __future__ import annotations

import argparse
import json
import sqlite3
from collections import Counter
from pathlib import Path

LANGS = ("ko", "ja", "zh")
GLOSSES = Path("sources/llm_glosses.jsonl")


def load_curated() -> dict[str, dict]:
    curated: dict[str, dict] = {}
    if GLOSSES.exists():
        for line in GLOSSES.read_text(encoding="utf-8").splitlines():
            if line.strip():
                entry = json.loads(line)
                curated[entry["literal"]] = entry
    return curated


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--emit", choices=LANGS,
                        help="print a JSON batch of kanji missing this language")
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument("--level", help="restrict to one 級")
    args = parser.parse_args()

    con = sqlite3.connect(args.db)
    rows = list(con.execute("""
        SELECT k.literal, km.level_label,
               (SELECT text FROM gloss WHERE kanji_id = k.id AND lang='en' LIMIT 1),
               (SELECT group_concat(value, '、') FROM reading
                 WHERE kanji_id = k.id AND lang_axis='on'),
               (SELECT group_concat(value, '、') FROM reading
                 WHERE kanji_id = k.id AND lang_axis='kun')
        FROM kanji k JOIN kanken_membership km ON km.kanji_id = k.id
        ORDER BY k.id"""))
    con.close()

    curated = load_curated()
    missing: dict[str, list[tuple]] = {lang: [] for lang in LANGS}
    per_level: dict[str, Counter] = {lang: Counter() for lang in LANGS}
    for literal, level, en, on, kun in rows:
        entry = curated.get(literal, {})
        for lang in LANGS:
            if not entry.get(lang):
                missing[lang].append((literal, level, en, on, kun))
                per_level[lang][level] += 1

    if args.emit:
        batch = [
            {"literal": literal, "level": level, "en": en,
             "on": on or "", "kun": kun or ""}
            for literal, level, en, on, kun in missing[args.emit]
            if args.level is None or level == args.level
        ][:args.limit]
        print(json.dumps(batch, ensure_ascii=False, indent=1))
        return 0

    total = len(rows)
    print(f"kanji: {total}")
    for lang in LANGS:
        have = total - len(missing[lang])
        print(f"\n{lang}: {have} / {total}   missing {len(missing[lang])}")
        for level, count in sorted(per_level[lang].items(), key=lambda kv: -kv[1]):
            print(f"    {level}: {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
