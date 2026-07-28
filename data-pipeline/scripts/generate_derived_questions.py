#!/usr/bin/env python3
"""Generate the exam sections that follow from the data we already ship.

Three 大問 that were 준비 중 only because nobody had written the generator:

* 三字熟語 (7級) — a three-kanji compound with one character blanked.
* 反対のことば / 対義語 (10級〜7級) — drawn from JMdict's `ant` cross-references,
  so the pairs are attested rather than guessed at.
* 共通の漢字 (準1級) — the 漢字識別 shape at the advanced level: two words share
  one missing character.

Each rejects a distractor that would also produce a real word, which is the
only thing that makes a single answer defensible.
"""
from __future__ import annotations

import argparse
import json
import random
import sqlite3
from collections import defaultdict
from pathlib import Path

SEED = 20260728
BLANK = "□"
SANJI_LEVELS = ("7級",)
HANTAI_LEVELS = {"10級": "hantai", "9級": "hantai", "8級": "taigi", "7級": "taigi"}
KYOTSU_LEVELS = ("準1級",)


def explanations(ko: str, ja: str, zh: str, en: str) -> dict[str, str]:
    return {"ko": ko, "ja": ja, "zh": zh, "en": en}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--out", default="sources/kanken_derived_questions.jsonl")
    args = parser.parse_args()

    con = sqlite3.connect(args.db)
    level_of = dict(con.execute(
        "SELECT k.literal, km.level_label FROM kanji k "
        "JOIN kanken_membership km ON km.kanji_id = k.id"))
    words = list(con.execute(
        "SELECT surface, reading_kana FROM word WHERE is_common = 1"))
    all_surfaces = {s for s, _ in con.execute("SELECT surface, reading_kana FROM word")}
    ko_of = dict(con.execute(
        "SELECT k.literal, g.text FROM kanji k JOIN gloss g ON g.kanji_id = k.id "
        "WHERE g.lang = 'ko'"))
    antonyms = list(con.execute("""
        SELECT a.surface, a.reading_kana, b.surface, b.reading_kana
        FROM relation r JOIN word a ON a.id = r.word_id_a JOIN word b ON b.id = r.word_id_b
        WHERE r.type = 'antonym' AND a.is_common = 1 AND b.is_common = 1"""))
    con.close()

    reading_of = dict(words)
    rng = random.Random(SEED)
    out: list[dict] = []
    stats: dict[str, int] = defaultdict(int)

    # ── 三字熟語 ────────────────────────────────────────────────────────────
    three = [(s, r) for s, r in words
             if len(s) == 3 and all("一" <= c <= "龠" for c in s)]
    by_kanji: dict[str, list[tuple[str, str, int]]] = defaultdict(list)
    for surface, reading in three:
        for index, ch in enumerate(surface):
            by_kanji[ch].append((surface, reading, index))
    for literal in sorted(by_kanji):
        if level_of.get(literal) not in SANJI_LEVELS:
            continue
        made = 0
        for surface, reading, index in by_kanji[literal]:
            if made >= 2:
                break
            frame = surface[:index] + BLANK + surface[index + 1:]
            if literal in frame:
                continue                       # the answer is still on screen
            pool = [c for c, lv in level_of.items()
                    if c != literal and lv in SANJI_LEVELS
                    and frame.replace(BLANK, c) not in all_surfaces]
            if len(pool) < 3:
                continue
            rng.shuffle(pool)
            options = pool[:3] + [literal]
            rng.shuffle(options)
            out.append({
                "literal": literal, "level": level_of[literal], "kind": "sanji",
                "prompt": f"{reading}　—　<u>{frame}</u>",
                "options": options, "answer": options.index(literal), "focus": frame,
                "explanations": explanations(
                    f"{reading}는 「{surface}」로 씁니다. 빈칸의 한자는 {literal}"
                    f"({ko_of.get(literal, '')})입니다.",
                    f"{reading} は「{surface}」と書きます。空欄に入る漢字は {literal} です。",
                    f"{reading} 写作「{surface}」。填入空格的汉字是 {literal}。",
                    f"{reading} is written 「{surface}」. The kanji for the blank is {literal}."),
            })
            made += 1
        stats["sanji"] += made

    # ── 反対のことば / 対義語 ───────────────────────────────────────────────
    seen_pairs: set[tuple[str, str]] = set()
    for word, word_reading, answer, answer_reading in antonyms:
        if (word, answer) in seen_pairs or (answer, word) in seen_pairs:
            continue
        # The question belongs to the easiest level that can read the prompt.
        levels = {level_of.get(c) for c in word + answer}
        if None in levels:
            continue
        target = next((c for c in answer if level_of.get(c) in HANTAI_LEVELS), None)
        if target is None:
            continue
        level = level_of[target]
        pool = [s for s, _ in words
                if s != answer and s != word and len(s) == len(answer)
                and all(level_of.get(c) in HANTAI_LEVELS for c in s)]
        if len(pool) < 3:
            continue
        rng.shuffle(pool)
        options = pool[:3] + [answer]
        rng.shuffle(options)
        seen_pairs.add((word, answer))
        kind = HANTAI_LEVELS[level]
        out.append({
            "literal": target, "level": level, "kind": kind,
            "prompt": f"<u>{word}</u>（{word_reading}）",
            "options": options, "answer": options.index(answer), "focus": word,
            "explanations": explanations(
                f"「{word}」의 반대말은 「{answer}」({answer_reading})입니다.",
                f"「{word}」の対義語は「{answer}」（{answer_reading}）です。",
                f"「{word}」的反义词是「{answer}」（{answer_reading}）。",
                f"The opposite of 「{word}」 is 「{answer}」 ({answer_reading})."),
        })
        stats[kind] += 1

    # ── 共通の漢字 (準1級) ──────────────────────────────────────────────────
    pairs: dict[str, list[tuple[str, int]]] = defaultdict(list)
    for surface, _ in words:
        if len(surface) == 2 and all("一" <= c <= "龠" for c in surface):
            for index, ch in enumerate(surface):
                pairs[ch].append((surface, index))
    for literal in sorted(pairs):
        if level_of.get(literal) not in KYOTSU_LEVELS:
            continue
        entries = pairs[literal]
        if len(entries) < 2:
            continue
        rng.shuffle(entries)
        (s1, i1), (s2, i2) = entries[0], entries[1]
        f1 = s1[:i1] + BLANK + s1[i1 + 1:]
        f2 = s2[:i2] + BLANK + s2[i2 + 1:]
        if f1 == f2 or literal in f1 or literal in f2:
            continue
        pool = [c for c, lv in level_of.items()
                if c != literal and lv in KYOTSU_LEVELS
                and not (f1.replace(BLANK, c) in all_surfaces
                         and f2.replace(BLANK, c) in all_surfaces)]
        if len(pool) < 3:
            continue
        rng.shuffle(pool)
        options = pool[:3] + [literal]
        rng.shuffle(options)
        prompt = f"{f1}　{f2}"
        out.append({
            "literal": literal, "level": level_of[literal], "kind": "kyotsu",
            "prompt": f"<u>{prompt}</u>",
            "options": options, "answer": options.index(literal), "focus": prompt,
            "explanations": explanations(
                f"두 낱말을 모두 이루는 한자는 {literal}입니다. {s1}・{s2}.",
                f"両方の語を作る漢字は {literal} です。{s1}・{s2}。",
                f"能填入两个词的汉字是 {literal}。{s1}・{s2}。",
                f"The kanji completing both is {literal}. {s1}, {s2}."),
        })
        stats["kyotsu"] += 1

    Path(args.out).write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")
    print(f"wrote {len(out)} derived questions → {args.out}")
    for kind, n in sorted(stats.items()):
        print(f"  {kind}: {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
