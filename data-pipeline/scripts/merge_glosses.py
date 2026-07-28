#!/usr/bin/env python3
"""Merge a translated gloss batch into sources/llm_glosses.jsonl.

Validates before writing, because a bad merge is invisible afterwards: a gloss
attached to the wrong literal reads perfectly well and is only caught by someone
who knows the kanji. Refuses to overwrite an existing gloss with a different
value — batches add languages, they do not silently rewrite curated ones.

    python scripts/merge_glosses.py batch1.json batch2.json --write
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

LANGS = ("ko", "ja", "zh")
GLOSSES = Path("sources/llm_glosses.jsonl")


def _has(text: str, lo: str, hi: str) -> bool:
    return any(lo <= ch <= hi for ch in text)


def script_problem(lang: str, text: str) -> str | None:
    """Catch a gloss written partly in the wrong script.

    Batch authoring slips in ways that read fine at a glance — a Cyrillic "т"
    inside たちあおい, an English word left mid-sentence in 「human心がむごく悪い」.
    Neither is visible without looking at the codepoints.

    The rules are deliberately narrow, because the 5,531 curated glosses already
    in the file show what legitimate output looks like: a Japanese gloss can be
    an all-kanji noun phrase (顔、表情), and Latin does appear in formulas and
    units (水 → H₂O, 斤 → 600g). So requiring kana, or banning Latin outright,
    would reject correct work. A run of three or more Latin letters is the thing
    that only happens when an English word was left behind.
    """
    if _has(text, "Ѐ", "ӿ"):
        return "contains Cyrillic"
    if _has(text, "가", "힯") and lang != "ko":
        return "contains Hangul"
    if lang == "ko" and not _has(text, "가", "힯"):
        return "no Hangul"
    if lang == "zh" and (_has(text, "぀", "ゟ") or _has(text, "゠", "ヿ")):
        return "contains kana"
    if re.search(r"[A-Za-z]{3}", text):
        return "contains an English word"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("batches", nargs="+")
    parser.add_argument("--write", action="store_true")
    parser.add_argument(
        "--keep-existing", action="store_true",
        help="a batch that re-states an existing gloss differently is not an "
             "error; keep the curated one and count the divergences")
    args = parser.parse_args()

    existing: dict[str, dict] = {}
    order: list[str] = []
    for line in GLOSSES.read_text(encoding="utf-8").splitlines():
        if line.strip():
            entry = json.loads(line)
            existing[entry["literal"]] = entry
            order.append(entry["literal"])

    problems: list[str] = []
    added = {lang: 0 for lang in LANGS}
    kept = 0
    seen = 0
    for path in args.batches:
        for entry in json.loads(Path(path).read_text(encoding="utf-8")):
            seen += 1
            literal = entry.get("literal")
            if not literal or len(literal) != 1:
                problems.append(f"{path}: bad literal {literal!r}")
                continue
            target = existing.get(literal)
            if target is None:
                target = {"literal": literal}
                existing[literal] = target
                order.append(literal)
            for lang in LANGS:
                value = (entry.get(lang) or "").strip()
                if not value:
                    continue
                trouble = script_problem(lang, value)
                if trouble:
                    problems.append(f"{path}: {literal} {lang} {trouble}: {value!r}")
                    continue
                current = target.get(lang)
                if current and current != value:
                    if args.keep_existing:
                        kept += 1
                    else:
                        problems.append(
                            f"{path}: {literal} {lang} already {current!r}, "
                            f"batch says {value!r}")
                    continue
                if not current:
                    target[lang] = value
                    added[lang] += 1

    print(f"batch entries: {seen}")
    print("added: " + ", ".join(f"{lang}={added[lang]}" for lang in LANGS))
    if kept:
        print(f"kept curated over {kept} differing restatements")
    if problems:
        print(f"\nPROBLEMS ({len(problems)}):", file=sys.stderr)
        for problem in problems[:20]:
            print("   " + problem, file=sys.stderr)
        return 1

    if args.write:
        GLOSSES.write_text(
            "\n".join(json.dumps(existing[lit], ensure_ascii=False) for lit in order) + "\n",
            encoding="utf-8")
        print(f"wrote {len(order)} entries → {GLOSSES}")
    else:
        print("dry run — pass --write to apply")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
