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
JUKUJIKUN_LEVELS = ("1級",)
TSUKURI_LEVELS = ("6級",)
HANTAI_LEVELS = {"10級": "hantai", "9級": "hantai", "8級": "taigi", "7級": "taigi"}
KYOTSU_LEVELS = ("準1級",)
# 語形成 is a JLPT 大問, so it is keyed by JLPT level, not by 級. Only affixes
# that are themselves N2 can carry an N2 question — which is exactly the set the
# real paper draws on.
PREFIXES = ("再", "副", "各", "準", "総", "諸", "超")
SUFFIXES = ("量", "額")
# Distractors have to sit in the same slot as the answer. Only 量 and 額 are N2
# suffixes, so they cannot supply three of their own — offering prefixes instead
# made 降水□ answerable from position alone. These are drawn on for the wrong
# answers only; the answer itself is still an N2 affix.
SUFFIX_DISTRACTORS = ("的", "性", "化", "者", "家", "力", "感", "観", "費",
                      "料", "数", "用", "式", "風", "量", "額")


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
    con_readings = list(con.execute(
        "SELECT k.literal, r.value, r.lang_axis FROM kanji k "
        "JOIN reading r ON r.kanji_id = k.id WHERE r.lang_axis IN ('on','kun')"))
    jlpt_of = dict(con.execute(
        "SELECT literal, jlpt_level FROM kanji WHERE jlpt_level IS NOT NULL"))
    ja_glosses = dict(con.execute(
        "SELECT w.surface, g.text FROM word w JOIN word_gloss g ON g.word_id = w.id "
        "WHERE g.lang = 'ja' AND w.is_common = 1"))
    taigirui_rows = list(con.execute(
        "SELECT word, word_reading, answer, answer_reading, relation FROM taigirui"))
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

    # ── 熟字訓・当て字 (1級) ────────────────────────────────────────────────
    # A 熟字訓 is a compound read as a whole rather than kanji by kanji, so the
    # test is exactly "the reading you cannot work out from the parts". Which
    # means it can be found rather than listed: keep the words whose reading
    # cannot be cut so each piece starts like a reading of its own kanji.
    kana_readings = defaultdict(set)
    for literal, value, axis in con_readings:
        hira = "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in value)
        kana_readings[literal].add(hira.split(".")[0])

    def decomposable(surface: str, reading: str) -> bool:
        def walk(index: int, pos: int) -> bool:
            if index == len(surface):
                return pos == len(reading)
            for r in kana_readings.get(surface[index], ()):
                if not r:
                    continue
                for cut in range(max(1, len(r) - 1), len(r) + 1):
                    piece = reading[pos:pos + cut]
                    if not piece:
                        continue
                    # Allow rendaku and a clipped final mora, which is what
                    # 学校 → がっこう does to がく + こう.
                    if abs(ord(piece[0]) - ord(r[0])) <= 2 and walk(index + 1, pos + cut):
                        return True
            return False
        return walk(0, 0)

    jukujikun: list[tuple[str, str, str]] = []
    for surface, reading in words:
        if not 2 <= len(surface) <= 3 or not all("一" <= c <= "龠" for c in surface):
            continue
        if not all(c in kana_readings for c in surface):
            continue
        target = next((c for c in surface if level_of.get(c) in JUKUJIKUN_LEVELS), None)
        if target is None or decomposable(surface, reading):
            continue
        jukujikun.append((surface, reading, target))

    pool = [r for _, r, _ in jukujikun]
    for surface, reading, target in jukujikun:
        same_length = [r for r in pool if r != reading and len(r) == len(reading)]
        if len(same_length) < 3:
            continue
        rng.shuffle(same_length)
        options = same_length[:3] + [reading]
        rng.shuffle(options)
        out.append({
            "literal": target, "level": level_of[target], "kind": "jukujikun",
            "prompt": f"<u>{surface}</u>", "options": options,
            "answer": options.index(reading), "focus": surface,
            "explanations": explanations(
                f"「{surface}」는 글자마다 읽지 않고 전체를 {reading}로 읽는 숙자훈입니다.",
                f"「{surface}」は字ごとに読まず、全体で {reading} と読む熟字訓です。",
                f"「{surface}」不逐字读，整体读作 {reading}，属熟字训。",
                f"「{surface}」is read {reading} as a whole, not kanji by kanji."),
        })
        stats["jukujikun"] += 1

    # ── 熟語作り (6級) ──────────────────────────────────────────────────────
    # Given a meaning, build the compound. The meanings are the Japanese word
    # glosses we already ship, so the question is real vocabulary rather than a
    # definition someone wrote for the occasion.
    made_tsukuri: set[str] = set()
    compounds = [(s, g) for s, g in ja_glosses.items()
                 if len(s) == 2 and all("一" <= c <= "龠" for c in s) and g]
    surfaces_only = [s for s, _ in compounds]
    for surface, gloss in compounds:
        target = next((c for c in surface if level_of.get(c) in TSUKURI_LEVELS), None)
        if target is None or surface in made_tsukuri:
            continue
        # A JMdict Japanese gloss often restates the headword ("悪質" defined
        # with 悪質 in it), which hands over the answer.
        if surface in gloss:
            continue
        if stats["tsukuri"] >= 400:
            break
        others = [s for s in surfaces_only if s != surface and not set(s) & set(surface)]
        if len(others) < 3:
            continue
        rng.shuffle(others)
        distractors = [o for o in others if o not in gloss][:3]
        if len(distractors) < 3:
            continue
        options = distractors + [surface]
        rng.shuffle(options)
        made_tsukuri.add(surface)
        out.append({
            "literal": target, "level": level_of[target], "kind": "tsukuri",
            "prompt": f"<u>{gloss}</u>", "options": options,
            "answer": options.index(surface), "focus": gloss,
            "explanations": explanations(
                f"이 뜻에 맞는 숙어는 「{surface}」입니다.",
                f"この意味に合う熟語は「{surface}」です。",
                f"符合这个意思的熟语是「{surface}」。",
                f"The compound with this meaning is 「{surface}」."),
        })
        stats["tsukuri"] += 1

    # ── 語形成 (N2) ─────────────────────────────────────────────────────────
    # Blank the affix and offer four; a candidate is rejected when substituting
    # it also spells a real word, so the answer is the only one that fits.
    made_gokeisei = 0
    for surface, _reading in words:
        if made_gokeisei >= 200:
            break
        if not 3 <= len(surface) <= 4 or not all("一" <= c <= "龠" for c in surface):
            continue
        head, tail = surface[0], surface[-1]
        if head in PREFIXES:
            affix, frame, pool = head, BLANK + surface[1:], PREFIXES
        elif tail in SUFFIXES:
            affix, frame, pool = tail, surface[:-1] + BLANK, SUFFIX_DISTRACTORS
        else:
            continue
        if jlpt_of.get(affix) != "N2" or affix in frame:
            continue
        safe = [c for c in pool
                if c != affix and frame.replace(BLANK, c) not in all_surfaces]
        if len(safe) < 3:
            continue
        rng.shuffle(safe)
        options = safe[:3] + [affix]
        rng.shuffle(options)
        out.append({
            "literal": affix, "level": "N2", "kind": "gokeisei",
            "prompt": f"<u>{frame}</u>", "options": options,
            "answer": options.index(affix), "focus": frame,
            "explanations": explanations(
                f"「{surface}」가 되도록 빈칸에 들어갈 글자는 {affix}입니다.",
                f"「{surface}」となるよう空欄に入る字は {affix} です。",
                f"要构成「{surface}」，填入空格的字是 {affix}。",
                f"The character that forms 「{surface}」 is {affix}."),
        })
        made_gokeisei += 1
    stats["gokeisei"] = made_gokeisei

    # ── 言い換え類義 (JLPT) ─────────────────────────────────────────────────
    # The 類義 half of the 対義語・類義語 dataset is exactly this question: a word,
    # and which of four means the same. It is keyed by 級 there, so the JLPT
    # level comes from the hardest kanji the pair uses — that is the level at
    # which a learner could be expected to read it.
    JLPT_ORDER = ("N5", "N4", "N3", "N2", "N1")
    rank = {level: index for index, level in enumerate(JLPT_ORDER)}
    synonym_pool = [answer for _, _, answer, _, relation in taigirui_rows
                    if relation == "類義"]
    for word, word_reading, answer, answer_reading, relation in taigirui_rows:
        if relation != "類義":
            continue
        chars = set(word) | set(answer)
        if any(c not in jlpt_of for c in chars):
            continue
        level = max((jlpt_of[c] for c in chars), key=lambda l: rank[l])
        target = next((c for c in answer if jlpt_of.get(c) == level), None)
        if target is None:
            continue
        others = [w for w in synonym_pool if w != answer and w != word]
        if len(others) < 3:
            continue
        rng.shuffle(others)
        options = others[:3] + [answer]
        rng.shuffle(options)
        out.append({
            "literal": target, "level": level, "kind": "iikae",
            "prompt": f"<u>{word}</u>（{word_reading}）",
            "options": options, "answer": options.index(answer), "focus": word,
            "explanations": explanations(
                f"「{word}」와 뜻이 가장 가까운 말은 「{answer}」({answer_reading})입니다.",
                f"「{word}」に最も意味が近い語は「{answer}」（{answer_reading}）です。",
                f"与「{word}」意思最接近的词是「{answer}」（{answer_reading}）。",
                f"The closest in meaning to 「{word}」 is 「{answer}」 ({answer_reading})."),
        })
        stats["iikae"] += 1

    # ── 熟語の読み・一字訓読み (準1級) ───────────────────────────────────────
    # The paper gives a compound, then the same kanji alone with its okurigana,
    # and asks for the 訓読み of the single character. The compound is context,
    # not the question — which is what keeps this distinct from 読み (compound
    # readings) and from 音読み・訓読み (a bare kanji with no context at all).
    kun_forms: dict[str, list[str]] = defaultdict(list)
    for literal, value, axis in con_readings:
        if axis != "kun" or "." not in value:
            continue
        # 「托する」「撰する」 are サ変 verbs: the stem is the 音読み, so asking for
        # it as a 訓読み is simply wrong. And a leading or trailing "-" marks a
        # prefix/suffix form in kanjidic2, not a reading that stands alone.
        if value.endswith(".する") or "-" in value:
            continue
        kun_forms[literal].append(value)
    compounds_by_kanji: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for surface, reading in words:
        if len(surface) == 2 and all("一" <= c <= "龠" for c in surface):
            for ch in set(surface):
                compounds_by_kanji[ch].append((surface, reading))

    all_kun = sorted({v.split(".")[0] for vs in kun_forms.values() for v in vs})
    for literal in sorted(kun_forms):
        if level_of.get(literal) != "準1級":
            continue
        pairs = compounds_by_kanji.get(literal)
        if not pairs:
            continue
        form = kun_forms[literal][0]
        okurigana = form.replace(".", "")
        answer = form.split(".")[0]
        compound, compound_reading = pairs[0]
        same_length = [k for k in all_kun if k != answer and len(k) == len(answer)]
        if len(same_length) < 3:
            continue
        rng.shuffle(same_length)
        options = same_length[:3] + [answer]
        rng.shuffle(options)
        out.append({
            "literal": literal, "level": "準1級", "kind": "jukugo_kun",
            "prompt": f"{compound}（{compound_reading}）　—　<u>{okurigana}</u>",
            "options": options, "answer": options.index(answer), "focus": okurigana,
            "explanations": explanations(
                f"「{okurigana}」의 훈독은 「{answer}」입니다. 숙어 「{compound}」"
                f"({compound_reading})와 같은 한자입니다.",
                f"「{okurigana}」の訓読みは「{answer}」です。熟語「{compound}」"
                f"（{compound_reading}）と同じ漢字です。",
                f"「{okurigana}」的训读是「{answer}」，与熟语「{compound}」"
                f"（{compound_reading}）用同一个汉字。",
                f"「{okurigana}」is read {answer}. Same kanji as in 「{compound}」."),
        })
        stats["jukugo_kun"] += 1

    Path(args.out).write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")
    print(f"wrote {len(out)} derived questions → {args.out}")
    for kind, n in sorted(stats.items()):
        print(f"  {kind}: {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
