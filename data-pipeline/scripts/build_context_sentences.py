#!/usr/bin/env python3
"""Real example sentences for the words the generated banks ask about.

漢検 and JLPT never ask a word on its own: 読み underlines it in a sentence,
書き取り and 同音・同訓異字 print it in katakana inside one. The generated banks
(準1級/1級 読み・書き取り, 同音・同訓異字) were built from dictionary words, so
this script finds each word a sentence in Tatoeba, with its Korean, Chinese
and English translations where Tatoeba has them.

A sentence is only used when it is certain to use *this* word with *this*
reading:

* the word has one reading in JMdict (生物 せいぶつ/なまもの never qualifies);
* it occurs once, with no kanji or 々 on either side, so it is not part of a
  longer compound (用意 inside 用意周到);
* for 10級〜2級 items every kanji in the sentence is at or below the item's 級,
  as on the real paper — a 7級 learner is not shown 3級 kanji.

    python scripts/build_context_sentences.py   # → sources/context_sentences_tatoeba.jsonl
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

KANKEN_ORDER = ["10級", "9級", "8級", "7級", "6級", "5級", "4級", "3級",
                "準2級", "2級", "準1級", "1級"]
RANK = {level: i for i, level in enumerate(KANKEN_ORDER)}
BANKS = ("sources/kanken_advanced_questions.jsonl", "sources/kanken_doonkun_questions.jsonl")
TRANSLATION_LANGS = {"eng": "en", "kor": "ko", "cmn": "zh"}
MIN_LEN, MAX_LEN = 8, 40

csv.field_size_limit(sys.maxsize)


def is_kanji(ch: str) -> bool:
    return "一" <= ch <= "鿿" or "㐀" <= ch <= "䶿" or ch == "々" \
        or "豈" <= ch <= "﫿"


def item_word(q: dict) -> tuple[str, str] | None:
    """(surface, reading) of the word a generated item asks about."""
    prompt = q["prompt"]
    m = re.search(r"<u>(.*?)</u>", prompt)
    if q["kind"] == "reading":
        surface = q.get("focus") or (m.group(1) if m else "")
        return (surface, q["options"][q["answer"]]) if surface else None
    # 書き取り / 同音: "てきよう　—　<u>□用</u>"
    if "　—　" not in prompt or not m:
        return None
    reading = prompt.split("　—　")[0].strip()
    surface = m.group(1).replace("□", q["options"][q["answer"]])
    return surface, reading


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--lexicon", default="/tmp/jmlex.json")
    parser.add_argument("--sentences", default="sources/sentences.csv")
    parser.add_argument("--links", default="sources/links.csv")
    parser.add_argument("--out", default="sources/context_sentences_tatoeba.jsonl")
    args = parser.parse_args()

    lexicon: dict[str, list[str]] = json.loads(Path(args.lexicon).read_text("utf-8"))

    con = sqlite3.connect(args.db)
    kanji_rank: dict[str, int] = {}
    for literal, level in con.execute(
            "SELECT k.literal, km.level_label FROM kanken_membership km "
            "JOIN kanji k ON k.id = km.kanji_id"):
        r = RANK.get(level)
        if r is not None:
            kanji_rank[literal] = min(r, kanji_rank.get(literal, 99))
    con.close()

    # Every word the banks ask about, with the hardest 級 it is asked at.
    wanted: dict[tuple[str, str], int] = {}
    for path in BANKS:
        for line in open(path, encoding="utf-8"):
            q = json.loads(line)
            word = item_word(q)
            if not word:
                continue
            r = RANK.get(q["level"], 99)
            wanted[word] = min(r, wanted.get(word, 99))
    single = {w: r for w, r in wanted.items() if set(lexicon.get(w[0], [])) == {w[1]}}
    by_surface = {s: (s, rd) for s, rd in single}
    print(f"{len(wanted)} words; {len(single)} with a single reading", file=sys.stderr)

    # Candidate sentences, indexed by the words they contain.
    candidates: dict[str, list[tuple[int, str]]] = defaultdict(list)
    jpn_text: dict[int, str] = {}
    lengths = sorted({len(s) for s in by_surface})
    with open(args.sentences, encoding="utf-8", newline="") as fh:
        for row in csv.reader(fh, delimiter="\t", quoting=csv.QUOTE_NONE):
            if len(row) < 3 or row[1] != "jpn":
                continue
            text = row[2].strip()
            if not MIN_LEN <= len(text) <= MAX_LEN:
                continue
            sid = int(row[0])
            for n in lengths:
                for i in range(len(text) - n + 1):
                    s = text[i:i + n]
                    if s in by_surface and text.count(s) == 1:
                        before = text[i - 1] if i else ""
                        after = text[i + n] if i + n < len(text) else ""
                        if (before and is_kanji(before)) or (after and is_kanji(after)):
                            continue
                        candidates[s].append((sid, text))
                        jpn_text[sid] = text

    def level_ok(text: str, rank: int) -> bool:
        if rank >= RANK["準1級"]:
            return True
        return all(kanji_rank.get(ch, 99) <= rank for ch in text if is_kanji(ch))

    picks_by_word: dict[tuple[str, str], list[tuple[int, str]]] = {}
    for surface, word in by_surface.items():
        rank = single[word]
        good = [(sid, t) for sid, t in candidates.get(surface, []) if level_ok(t, rank)]
        if good:
            # shortest first; keep a few so translations can break ties
            picks_by_word[word] = sorted(good, key=lambda p: (len(p[1]), p[0]))[:5]
    chosen_ids = {sid for picks in picks_by_word.values() for sid, _ in picks}
    print(f"{len(picks_by_word)} words have a usable sentence", file=sys.stderr)

    # Translations: links jpn → other, then the other side's text.
    linked: dict[int, set[int]] = defaultdict(set)
    with open(args.links, encoding="utf-8") as fh:
        for line in fh:
            a, _, b = line.rstrip("\n").partition("\t")
            if not a.isdigit() or not b.isdigit():
                continue
            a, b = int(a), int(b)
            if a in chosen_ids:
                linked[a].add(b)
    targets = {b for bs in linked.values() for b in bs}
    translation: dict[int, tuple[str, str]] = {}
    with open(args.sentences, encoding="utf-8", newline="") as fh:
        for row in csv.reader(fh, delimiter="\t", quoting=csv.QUOTE_NONE):
            if len(row) >= 3 and row[1] in TRANSLATION_LANGS and row[0].isdigit():
                sid = int(row[0])
                if sid in targets:
                    translation[sid] = (TRANSLATION_LANGS[row[1]], row[2].strip())

    out = []
    for (surface, reading), picks in sorted(picks_by_word.items()):
        def trans(sid: int) -> dict[str, str]:
            t: dict[str, str] = {}
            for b in sorted(linked.get(sid, ())):
                if b in translation:
                    lang, text = translation[b]
                    t.setdefault(lang, text)
            return t
        # Prefer the short sentence with the most translations.
        best = max(picks, key=lambda p: (len(trans(p[0])), -len(p[1])))
        out.append({"word": surface, "reading": reading, "sentence": best[1],
                    "source": f"tatoeba:{best[0]}", "translations": trans(best[0])})
    Path(args.out).write_text(
        "".join(json.dumps(r, ensure_ascii=False) + "\n" for r in out), encoding="utf-8")
    counts = defaultdict(int)
    for r in out:
        for lang in r["translations"]:
            counts[lang] += 1
    print(f"wrote {len(out)} sentences → {args.out}; translations {dict(counts)}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
