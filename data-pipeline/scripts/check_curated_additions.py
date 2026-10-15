#!/usr/bin/env python3
"""Validate authored 四字熟語 / 対義語・類義語 additions before they ship.

Additions are exam content, so they must be real and level-appropriate, not
invented. This checks the mechanical guarantees; a human still spot-reads for
whether the idiom/pairing is genuine.

yoji additions (JSON list of {yoji, reading, meaningJa, meaningKo, meaningZh,
meaningEn, level}):
  * yoji is exactly four kanji;
  * reading is hiragana only;
  * every kanji is in the app at the item's 級 or easier (nothing above level);
  * all four meanings are present and non-empty;
  * not already in the shipped source, no dupes within the batch.

taigirui additions ({word, wordReading, answer, answerReading, relation, level}):
  * relation is 対義 or 類義;
  * word and answer are real headwords in JMdict (the lexicon), with the given
    reading attested;
  * every kanji in both is at the item's 級 or easier;
  * not already shipped, no dupes within the batch.

    python scripts/check_curated_additions.py --kind yoji FILE
    python scripts/check_curated_additions.py --kind taigirui FILE
"""
from __future__ import annotations

import argparse
import json
import sqlite3
import sys
from pathlib import Path

ORDER = ["10級", "9級", "8級", "7級", "6級", "5級", "4級", "3級",
         "準2級", "2級", "準1級", "1級"]
RANK = {level: i for i, level in enumerate(ORDER)}
RESOURCES = Path(__file__).resolve().parents[2] / "app/Sources/DictionaryClient/Resources"


def is_kanji(ch: str) -> bool:
    return "一" <= ch <= "鿿" or "豈" <= ch <= "﫿"


def is_hiragana(text: str) -> bool:
    return bool(text) and all("぀" <= c <= "ゟ" or c == "ー" for c in text)


def kanji_rank(db: str) -> dict[str, int]:
    con = sqlite3.connect(db)
    rank: dict[str, int] = {}
    for literal, level in con.execute(
            "SELECT k.literal, km.level_label FROM kanken_membership km "
            "JOIN kanji k ON k.id = km.kanji_id"):
        r = RANK.get(level)
        if r is not None:
            rank[literal] = min(r, rank.get(literal, 99))
    con.close()
    return rank


def level_ok(word: str, level: str, rank: dict[str, int]) -> list[str]:
    target = RANK.get(level)
    if target is None:
        return [f"unknown level {level!r}"]
    above = [c for c in word if is_kanji(c) and rank.get(c, 99) > target]
    return [f"kanji above {level}: {''.join(above)}"] if above else []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+")
    parser.add_argument("--kind", choices=["yoji", "taigirui"], required=True)
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--lexicon", default="/tmp/jmlex.json")
    args = parser.parse_args()

    rank = kanji_rank(args.db)
    lexicon = {}
    if Path(args.lexicon).exists():
        lexicon = json.loads(Path(args.lexicon).read_text("utf-8"))

    if args.kind == "yoji":
        shipped = {e["yoji"] for e in json.loads(
            (RESOURCES / "yojijukugo.source.json").read_text("utf-8"))}
    else:
        shipped = {(e["word"], e["answer"]) for e in json.loads(
            (RESOURCES / "taigirui.source.json").read_text("utf-8"))}

    seen: set = set()
    bad = total = 0
    for path in args.files:
        for n, line in enumerate(Path(path).read_text("utf-8").splitlines(), 1):
            line = line.strip().rstrip(",")
            if not line or line in "[]":
                continue
            total += 1
            try:
                e = json.loads(line)
            except json.JSONDecodeError as err:
                print(f"{path}:{n}: bad JSON: {err}"); bad += 1; continue
            issues: list[str] = []
            if args.kind == "yoji":
                yoji = e.get("yoji", "")
                if len(yoji) != 4 or not all(is_kanji(c) for c in yoji):
                    issues.append("yoji must be exactly four kanji")
                if not is_hiragana(e.get("reading", "")):
                    issues.append("reading must be hiragana")
                for lang in ("meaningJa", "meaningKo", "meaningZh", "meaningEn"):
                    if not (e.get(lang) or "").strip():
                        issues.append(f"missing {lang}")
                issues += level_ok(yoji, e.get("level", ""), rank)
                if yoji in shipped or yoji in seen:
                    issues.append("duplicate")
                seen.add(yoji)
                label = yoji
            else:
                word, answer = e.get("word", ""), e.get("answer", "")
                if e.get("relation") not in ("対義", "類義"):
                    issues.append("relation must be 対義 or 類義")
                for surface, reading in ((word, e.get("wordReading", "")),
                                         (answer, e.get("answerReading", ""))):
                    if lexicon and reading not in lexicon.get(surface, []):
                        issues.append(f"{surface}/{reading} not attested in JMdict")
                    issues += level_ok(surface, e.get("level", ""), rank)
                if (word, answer) in shipped or (word, answer) in seen:
                    issues.append("duplicate")
                seen.add((word, answer))
                label = f"{word}/{answer}"
            if issues:
                bad += 1
                print(f"{path}:{n} [{label}]: " + "; ".join(issues))
    if bad:
        print(f"FAIL — {bad} of {total} additions need fixing")
        return 1
    print(f"OK — {total} additions, all valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
