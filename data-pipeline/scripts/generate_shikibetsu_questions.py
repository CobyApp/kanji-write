#!/usr/bin/env python3
"""Generate 漢字識別 questions (漢検 4級・3級).

The paper shows three two-kanji words that are each missing the SAME character
and asks which one fills all three. One word could be filled several ways; three
at once pin it — which is also the safety rule here: a distractor is rejected
unless it fails to complete at least one of the three, so the answer is the only
character that works for all of them.

Run after a build, then rebuild so the questions are ingested.
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

LEVELS = ("4級", "3級")
PER_KANJI = 2
SEED = 20260728
BLANK = "□"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--out", default="sources/kanken_shikibetsu_questions.jsonl")
    args = parser.parse_args()

    con = sqlite3.connect(args.db)
    level_of = dict(con.execute(
        "SELECT k.literal, km.level_label FROM kanji k "
        "JOIN kanken_membership km ON km.kanji_id = k.id"))
    rows = list(con.execute("""
        SELECT DISTINCT w.surface, w.reading_kana FROM word w
        WHERE w.is_common = 1 AND w.surface GLOB '[一-龠][一-龠]'"""))
    ko_of = dict(con.execute(
        "SELECT k.literal, g.text FROM kanji k JOIN gloss g ON g.kanji_id = k.id "
        "WHERE g.lang = 'ko'"))
    ja_of = dict(con.execute(
        "SELECT k.literal, g.text FROM kanji k JOIN gloss g ON g.kanji_id = k.id "
        "WHERE g.lang = 'ja'"))
    con.close()

    surfaces = {surface for surface, _ in rows}
    reading_of = dict(rows)
    # Every word each kanji appears in, remembering which slot it occupies.
    slots: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for surface in surfaces:
        for index, ch in enumerate(surface):
            slots[ch].append((surface, index))

    def blanked(surface: str, index: int) -> str:
        return surface[:index] + BLANK + surface[index + 1:]

    rng = random.Random(SEED)
    out: list[dict] = []
    stats = defaultdict(int)
    for literal, level in sorted(level_of.items()):
        if level not in LEVELS:
            continue
        words = sorted(slots.get(literal, []))
        if len(words) < 3:
            stats["fewer than three words"] += 1
            continue
        rng.shuffle(words)

        made = 0
        for start in range(0, len(words) - 2, 3):
            if made >= PER_KANJI:
                break
            trio = words[start:start + 3]
            frames = [blanked(s, i) for s, i in trio]
            if len({f for f in frames}) < 3:
                continue

            # A candidate is only safe if it fails at least one frame.
            candidates = []
            for other, other_level in level_of.items():
                if other == literal or other_level not in LEVELS:
                    continue
                if all(f.replace(BLANK, other) in surfaces for f in frames):
                    continue           # also completes all three — ambiguous
                candidates.append(other)
            if len(candidates) < 3:
                continue
            rng.shuffle(candidates)
            options = candidates[:3] + [literal]
            rng.shuffle(options)

            prompt = "　".join(frames)
            examples = "・".join(s for s, _ in trio)
            out.append({
                "literal": literal,
                "level": level,
                "kind": "shikibetsu",
                "prompt": f"<u>{prompt}</u>",
                "options": options,
                "answer": options.index(literal),
                "focus": prompt,
                "explanations": {
                    "ko": f"세 낱말 모두를 이루는 한자는 {literal}입니다"
                          f"({ko_of.get(literal, '')}). {examples}.",
                    "ja": f"三つの語すべてを作る漢字は {literal} です。{examples}。",
                    "zh": f"能填入三个词的汉字是 {literal}。{examples}。",
                    "en": f"The kanji that completes all three is {literal}. {examples}.",
                },
            })
            made += 1
        stats[level] += made
        if made == 0:
            stats["no safe trio"] += 1

    Path(args.out).write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")
    print(f"wrote {len(out)} 漢字識別 questions → {args.out}")
    for level in LEVELS:
        print(f"  {level}: {stats[level]}")
    print(f"  kanji in fewer than three words: {stats['fewer than three words']}")
    print(f"  kanji with no unambiguous trio: {stats['no safe trio']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
