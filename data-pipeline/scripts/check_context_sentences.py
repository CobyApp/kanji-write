#!/usr/bin/env python3
"""Check authored context sentences before they reach a question.

Each line: {"id", "word", "reading", "level", "sentence",
            "translations": {"ko", "zh", "en"}}

A sentence is rejected unless it:
* contains the word verbatim exactly once, with no kanji or 々 right before
  or after it (so the word is not swallowed by a longer compound);
* is one complete sentence of 10〜45 characters ending in 。, ！ or ？, with no
  markup and no reading printed beside the word;
* at 10級〜2級, uses no kanji above the item's 級 outside the word itself —
  as the real paper writes such words in kana;
* has Korean, Chinese and English translations in those scripts.

    python scripts/check_context_sentences.py FILE [--db out/kanji.sqlite]
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys

ORDER = ["10級", "9級", "8級", "7級", "6級", "5級", "4級", "3級", "準2級", "2級", "準1級", "1級"]
RANK = {level: i for i, level in enumerate(ORDER)}
HANGUL = re.compile(r"[가-힣]")
KANA = re.compile(r"[぀-ヿ]")
CJK = re.compile(r"[一-鿿]")


def is_kanji(ch: str) -> bool:
    return "一" <= ch <= "鿿" or "㐀" <= ch <= "䶿" or ch == "々" \
        or "豈" <= ch <= "﫿"


def problems(row: dict, rank_of: dict[str, int]) -> list[str]:
    out: list[str] = []
    word, sentence = row.get("word", ""), row.get("sentence", "")
    level = row.get("level", "")
    if not word or not sentence:
        return ["missing word or sentence"]
    if sentence.count(word) != 1:
        out.append(f"word appears {sentence.count(word)} times")
    else:
        i = sentence.index(word)
        before = sentence[i - 1] if i else ""
        after = sentence[i + len(word)] if i + len(word) < len(sentence) else ""
        if (before and is_kanji(before)) or (after and is_kanji(after)):
            out.append("kanji touches the word (part of a longer compound?)")
        rest = sentence[i + len(word):]
        if rest.startswith(("（", "(")):
            out.append("reading printed beside the word")
    if not 10 <= len(sentence) <= 45:
        out.append(f"length {len(sentence)} (want 10〜45)")
    if not sentence.endswith(("。", "！", "？")):
        out.append("does not end with 。")
    if sentence.count("。") > 1:
        out.append("more than one sentence")
    if re.search(r"[<>＜＞\[\]]|\s", sentence):
        out.append("markup or spaces in the sentence")
    if HANGUL.search(sentence) or re.search(r"[A-Za-z]", sentence):
        out.append("non-Japanese script in the sentence")
    r = RANK.get(level)
    if r is None:
        out.append(f"unknown level {level!r}")
    elif r < RANK["準1級"]:
        outside = sentence.replace(word, "")
        # 々 repeats the kanji before it; it is not a kanji of any 級.
        above = sorted({ch for ch in outside
                        if is_kanji(ch) and ch != "々" and rank_of.get(ch, 99) > r})
        if above:
            out.append("kanji above the level: " + "".join(above))
    t = row.get("translations") or {}
    if not HANGUL.search(t.get("ko", "")):
        out.append("Korean translation missing")
    if KANA.search(t.get("ko", "")):
        out.append("kana in the Korean translation")
    zh = t.get("zh", "")
    if not CJK.search(zh) or KANA.search(zh) or HANGUL.search(zh):
        out.append("Chinese translation missing or not Chinese")
    en = t.get("en", "")
    if not re.search(r"[A-Za-z]{2,}", en) or KANA.search(en) or HANGUL.search(en):
        out.append("English translation missing or not English")
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+")
    parser.add_argument("--db", default="out/kanji.sqlite")
    args = parser.parse_args()
    con = sqlite3.connect(args.db)
    rank_of: dict[str, int] = {}
    for literal, level in con.execute(
            "SELECT k.literal, km.level_label FROM kanken_membership km "
            "JOIN kanji k ON k.id = km.kanji_id"):
        r = RANK.get(level)
        if r is not None:
            rank_of[literal] = min(r, rank_of.get(literal, 99))
    bad = total = 0
    for path in args.files:
        for n, line in enumerate(open(path, encoding="utf-8"), 1):
            if not line.strip():
                continue
            total += 1
            try:
                row = json.loads(line)
            except json.JSONDecodeError as e:
                print(f"{path}:{n}: invalid JSON: {e}")
                bad += 1
                continue
            issues = problems(row, rank_of)
            if issues:
                bad += 1
                print(f"{path}:{n} [{row.get('id')}] {row.get('word')}: " + "; ".join(issues))
    if bad:
        print(f"FAIL — {bad} of {total} sentences need fixing")
        return 1
    print(f"OK — {total} sentences, all valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
