#!/usr/bin/env python3
"""Flag multiple-choice items where a distractor is *also* a correct answer.

The structural checker (check_question_batch.py) cannot see this: four distinct
options and an in-range answer say nothing about whether a second option is
defensible. This checks the cases the dictionary can decide:

* 書き取り / 表記 (orthography): the prompt spells a word in kana (the focus);
  a distractor that JMdict also spells that way is a second right answer —
  「いっちょう」 offered as both 一丁 and 一朝.
* 読み (reading): a distractor that JMdict lists as a reading of the focus word
  is a second right answer — 「今日」 offered as both きょう and こんにち.
* 同音・同訓異字 (doonkun): the blank sits in a word whose reading is in the
  explanation; a distractor that completes a real word with that reading is a
  second right answer.

Usage: check_ambiguity.py <batch.jsonl> [--db out/kanji.sqlite]
       check_ambiguity.py --db <db>          # scan the whole bank in the DB
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

UNDERLINE = re.compile(r"</?u>")
BLANK = "□"


def kata_to_hira(text: str) -> str:
    return "".join(
        chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def load_lexicon(con: sqlite3.Connection):
    by_reading: dict[str, set[str]] = defaultdict(set)
    by_surface: dict[str, set[str]] = defaultdict(set)
    for surface, reading in con.execute("SELECT surface, reading_kana FROM word"):
        r = kata_to_hira(reading)
        by_reading[r].add(surface)
        by_surface[surface].add(r)
    return by_reading, by_surface


def problems_for(q: dict, by_reading, by_surface) -> list[str]:
    kind = q.get("kind")
    options = [str(o) for o in q.get("options") or []]
    answer = q.get("answer")
    if not isinstance(answer, int) or not 0 <= answer < len(options):
        return []
    focus = q.get("focus") or ""
    clean = UNDERLINE.sub("", q.get("prompt") or "")
    out: list[str] = []
    if kind == "orthography" and focus:
        reading = kata_to_hira(focus)
        spellings = by_reading.get(reading, set())
        correct = options[answer]
        # Options are either whole words or the single kanji that fills the
        # word; normalise both to a whole-word spelling where possible.
        for i, opt in enumerate(options):
            if i == answer:
                continue
            if opt in spellings:
                out.append(f"WARN distractor {opt!r} is also spelled {reading} "
                           "— the sentence must rule it out")
            elif len(opt) == 1 and len(correct) == 1:
                # single-kanji options: rebuild the word from the correct
                # spelling if it is in the lexicon.
                for word in spellings:
                    if correct in word and word.replace(correct, opt, 1) in spellings:
                        out.append(f"distractor {opt!r} also makes "
                                   f"{word.replace(correct, opt, 1)} ({reading})")
                        break
    elif kind == "reading" and focus:
        readings = by_surface.get(focus, set())
        for i, opt in enumerate(options):
            if i != answer and kata_to_hira(opt) in readings:
                out.append(f"WARN distractor {opt!r} is also a reading of {focus} "
                           "— the sentence must rule it out")
    elif kind == "doonkun" and BLANK in clean:
        correct = options[answer]
        # every token containing the blank, e.g. 一□ in 「いっちょう 一□」
        for token in re.findall(r"[^\s、。「」（）()]*" + BLANK + r"[^\s、。「」（）()]*", clean):
            filled = token.replace(BLANK, correct)
            readings = by_surface.get(filled, set())
            for i, opt in enumerate(options):
                if i == answer:
                    continue
                alt = token.replace(BLANK, opt)
                if readings & by_surface.get(alt, set()):
                    out.append(f"distractor {opt!r} also makes {alt} "
                               f"(same reading as {filled})")
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("batch", nargs="?")
    parser.add_argument("--db", default="out/kanji.sqlite")
    args = parser.parse_args()
    con = sqlite3.connect(args.db)
    by_reading, by_surface = load_lexicon(con)

    if args.batch:
        text = Path(args.batch).read_text(encoding="utf-8")
        batch = (json.loads(text) if text.lstrip().startswith("[")
                 else [json.loads(l) for l in text.splitlines() if l.strip()])
        rows = [(i, q) for i, q in enumerate(batch)]
    else:
        rows = []
        for qid, literal, level, kind, prompt, options, answer, focus in con.execute(
            "SELECT q.id, k.literal, q.level, q.kind, q.prompt, q.options, "
            "q.answer, q.focus FROM jlpt_question q JOIN kanji k ON k.id = q.kanji_id"
        ):
            rows.append((qid, {"literal": literal, "level": level, "kind": kind,
                               "prompt": prompt, "options": json.loads(options),
                               "answer": answer, "focus": focus}))
    found = warned = 0
    for key, q in rows:
        for p in problems_for(q, by_reading, by_surface):
            if p.startswith("WARN"):
                warned += 1
            else:
                found += 1
            if found + warned <= 200:
                print(f"[{key}:{q.get('kind')}:{q.get('level')}:{q.get('literal')}] {p}")
    print(f"{'FAIL' if found else 'OK'} — {found} ambiguous item(s), "
          f"{warned} context warning(s) in {len(rows)}")
    return 1 if found else 0


if __name__ == "__main__":
    raise SystemExit(main())
