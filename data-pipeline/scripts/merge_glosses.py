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
import sys
from pathlib import Path

LANGS = ("ko", "ja", "zh")
GLOSSES = Path("sources/llm_glosses.jsonl")


def _has(text: str, lo: str, hi: str) -> bool:
    return any(lo <= ch <= hi for ch in text)


def script_problem(lang: str, text: str) -> str | None:
    """Catch a gloss written partly in the wrong script.

    Batch authoring slips in ways that read fine at a glance — a Cyrillic 'т'
    inside たちあおい, an English word left inside a Chinese sentence. Both
    happened; neither is visible without looking at the codepoints.
    """
    if _has(text, "Ѐ", "ӿ"):
        return "contains Cyrillic"
    if _has(text, "가", "힯") and lang != "ko":
        return "contains Hangul"
    if lang == "zh":
        if _has(text, "぀", "ゟ") or _has(text, "゠", "ヿ"):
            return "contains kana"
        if any("a" <= ch.lower() <= "z" for ch in text):
            return "contains Latin letters"
    if lang == "ko" and not _has(text, "가", "힯"):
        return "no Hangul"
    if lang == "ja" and not (
        _has(text, "぀", "ゟ") or _has(text, "゠", "ヿ")
    ):
        return "no kana"
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("batches", nargs="+")
    parser.add_argument("--write", action="store_true")
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
                    problems.append(
                        f"{path}: {literal} {lang} already {current!r}, batch says {value!r}")
                    continue
                if not current:
                    target[lang] = value
                    added[lang] += 1

    print(f"batch entries: {seen}")
    print("added: " + ", ".join(f"{lang}={added[lang]}" for lang in LANGS))
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
