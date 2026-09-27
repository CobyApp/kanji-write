#!/usr/bin/env python3
"""Put the generated 漢検 questions into sentences, the way the paper asks them.

The generators build questions from dictionary words — 「てきよう — □用」, a
bare 「<u>鯡</u>」. The real paper never asks a word alone:

* 読み underlines the word in a sentence:     若手の中から人材を<u>擢用</u>する。
* 同音・同訓異字 / 書き取り print the tested kanji in katakana inside the word,
  inside a sentence:                           若手の中から人材を<u>テキ</u>用する。
* 一字訓 書き取り prints the whole word in katakana: 旧友と<u>アウ</u>約束をした。

This script rewrites the three generated banks (準1級/1級 読み・書き取り,
同音・同訓異字, and the rare-kanji 一字訓 bank) into that form, using the
reviewed sentences in ``sources/context_sentences.jsonl``, and rebuilds each
explanation (``kanjipipe.explain``): reading and meaning, the sentence's
translation, and what every wrong option is.

For 準1級/1級 it keeps one 読み and one 書き取り per kanji — sharing a word
when the kanji has one that serves both — rather than every dictionary word:
a real sitting asks 30 + 20 of them, and a sentence per question matters more
than a third or fourth word for the same kanji.

Run after the generators and before ``refresh_db.py``:

    python scripts/generate_advanced_questions.py
    python scripts/generate_homophone_questions.py
    python scripts/generate_rare_kun_questions.py
    python scripts/contextualize_questions.py
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from kanjipipe.explain import Dictionary, kanji_choice, reading_choice, to_katakana  # noqa: E402
from kanjipipe.furigana import slice_at, to_hiragana  # noqa: E402

ADVANCED = "sources/kanken_advanced_questions.jsonl"
DOONKUN = "sources/kanken_doonkun_questions.jsonl"
RARE = "sources/kanken_rare_kun_questions.jsonl"
FRAME = "　—　"

# Words not asked at all: discriminatory or sexual terms, slang, a shrine name
# that is political in itself, and an obsolete abbreviation. The dictionary
# has them; an exam-prep app has no reason to drill them.
BLOCKLIST = {"強姦", "勃起", "瞎", "穢多", "傴僂", "喑", "噓乙", "猛虎弁", "弁蓋部",
             "靖国神社", "予研"}
VERBAL_ENDINGS = set("うくぐすつぬぶむる")


def frame_word(q: dict) -> tuple[str, str, int] | None:
    """(surface, reading, blank index) of a 「よみ　—　<u>□字</u>」 item."""
    if FRAME not in q["prompt"]:
        return None
    reading, _, rest = q["prompt"].partition(FRAME)
    m = re.search(r"<u>(.*?)</u>", rest)
    if not m or "□" not in m.group(1):
        return None
    frame = m.group(1)
    return frame.replace("□", q["options"][q["answer"]]), reading.strip(), frame.index("□")


def fallback_meaning(q: dict) -> dict[str, str]:
    """The meaning the old generated explanation gave, per language."""
    ex = q.get("explanations") or {}
    pats = {"ko": r"뜻은 ‘(.*?)’", "ja": r"「[^」]*」は「?([^」。]*?)」?という意味", "zh": r"意思是(.*?)[。，]",
            "en": r"means ['‘\"]?(.*?)['’\"]?[.;]"}
    out = {}
    for lang, pat in pats.items():
        m = re.search(pat, ex.get(lang, ""))
        if m and m.group(1).strip():
            out[lang] = m.group(1).strip()
    return out


class Context:
    def __init__(self, db: str, sentences: str) -> None:
        self.d = Dictionary.load(db)
        con = sqlite3.connect(db)
        self.readings_of: dict[str, tuple[set[str], set[str]]] = defaultdict(lambda: (set(), set()))
        for literal, axis, value in con.execute(
                "SELECT k.literal, r.lang_axis, r.value FROM kanji k JOIN reading r ON r.kanji_id = k.id "
                "WHERE r.lang_axis IN ('on','kun')"):
            self.readings_of[literal][0 if axis == "on" else 1].add(value)
        self.common = {(s, r): c for s, r, c in con.execute(
            "SELECT surface, reading_kana, MAX(is_common) FROM word GROUP BY 1, 2")}
        con.close()
        self.sentences: dict[tuple[str, str], dict] = {}
        for line in open(sentences, encoding="utf-8"):
            if line.strip():
                row = json.loads(line)
                self.sentences[(row["word"], row["reading"])] = row

    def sounds(self, ch: str) -> set[str]:
        """Every reading of ``ch`` in hiragana, stems only (かがや.く → かがや)."""
        on, kun = self.readings_of.get(ch, (set(), set()))
        return {to_hiragana(r) for r in on} | {r.split(".")[0].strip("-") for r in kun}

    def split(self, surface: str, reading: str) -> list[tuple[str, str]] | None:
        parts = []
        for i, ch in enumerate(surface):
            forms = slice_at(surface, reading, i, self.readings_of)
            if forms is None:
                return None
            parts.append((ch, forms[0].slice))
        return parts


def repeats_okurigana(sentence: str, word: str, reading: str) -> bool:
    """True when the kana after ``word`` are part of its own ``reading``.

    Some dictionary 訓読み carry okurigana the headword does not show (揭 read
    かかげる, 竢 read まつ). In a sentence the writer then has to add it —
    揭げる, 竢つ — and the underlined kanji is no longer read ``reading``.
    """
    i = sentence.index(word) + len(word)
    after = sentence[i:i + 4]
    if not after or not ("ぁ" <= after[0] <= "ゖ"):
        return False
    if reading[-1] in VERBAL_ENDINGS and after.startswith(reading[-1]):
        return True
    for j in range(2, len(reading)):
        tail = reading[-j:]
        if after.startswith(tail[:-1]):
            return True
    return False


IMPOSSIBLE = re.compile(r"っ(?=[あいうえおなにぬねのまみむめもやゆよらりるれろわをんぁぃぅぇぉゃゅょっ]|$)")


def pronounceable(ctx: Context, surface: str, options: list[str], answer: str) -> list[str]:
    """Replace impossible wrong readings (いっもち, べっや): a small っ never
    comes before a vowel, な・ま・や・ら・わ行 or ん. The distractor builder
    kept the answer's 促音 while swapping the next kanji's reading; putting
    the first kanji's full reading back (いちもち) keeps the trap without
    printing something no word could sound like."""
    fixed = []
    for o in options:
        if o == answer or not IMPOSSIBLE.search(o):
            fixed.append(o)
            continue
        i = o.index("っ")
        head, tail = o[:i], o[i + 1:]
        full = sorted(r for r in ctx.sounds(surface[0])
                      if r.startswith(head) and len(r) == len(head) + 1 and r[-1] in "つちくき")
        candidate = next((head + r[-1] + tail for r in full
                          if head + r[-1] + tail not in options and head + r[-1] + tail != answer), None)
        fixed.append(candidate or o)
    return fixed


def leaks_answer(sentence: str, word: str, answer: str) -> bool:
    """The answer kanji appears elsewhere in the sentence — a giveaway."""
    return answer in sentence.replace(word, "", 1)


def sentence_with(sentence: str, word: str, shown: str) -> str:
    i = sentence.index(word)
    return sentence[:i] + shown + sentence[i + len(word):]


def writing_item(ctx: Context, q: dict, surface: str, reading: str, index: int,
                 row: dict, same_sound_all: bool) -> dict | None:
    forms = slice_at(surface, reading, index, ctx.readings_of)
    if forms is None:
        return whole_word_item(ctx, q, surface, reading, index, row)
    if surface in BLOCKLIST or leaks_answer(row["sentence"], surface, q["options"][q["answer"]]):
        return None
    slot = forms[0].slice
    kata = to_katakana(slot)
    shown = surface[:index] + f"<u>{kata}</u>" + surface[index + 1:]
    answer = q["options"][q["answer"]]
    others = [o for o in q["options"] if o != answer]
    if same_sound_all:
        same = set(others)
    else:
        unvoiced = slot.translate(str.maketrans("がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽ",
                                                "かきくけこさしすせそたちつてとはひふへほはひふへほ"))
        same = {o for o in others if ctx.sounds(o) & {slot, unvoiced}}
    new = dict(q)
    new["prompt"] = sentence_with(row["sentence"], surface, shown)
    new["focus"] = kata
    new["explanations"] = kanji_choice(
        ctx.d, word=surface, reading=reading, answer=answer, options=q["options"],
        same_sound=same, translations=row.get("translations"),
        meaning_fallback=fallback_meaning(q), slot_sound=kata)
    return new


def whole_word_item(ctx: Context, q: dict, surface: str, reading: str, index: int,
                    row: dict) -> dict | None:
    """書き取り with the whole word in katakana — the 準1級/1級 paper's own form.

    Used when the tested kanji's share of the reading cannot be pinned down
    (熟字訓-like words), so printing one kanji in katakana would be a guess.
    The options become whole words: the frame with each candidate filled in.
    """
    answer = q["options"][q["answer"]]
    if surface in BLOCKLIST or leaks_answer(row["sentence"], surface, answer):
        return None
    kata = to_katakana(reading)
    words = [surface[:index] + o + surface[index + 1:] for o in q["options"]]
    new = dict(q)
    new["prompt"] = sentence_with(row["sentence"], surface, f"<u>{kata}</u>")
    new["focus"] = kata
    new["options"] = words
    new["explanations"] = kanji_choice(
        ctx.d, word=surface, reading=reading, answer=answer, options=q["options"],
        same_sound=set(), translations=row.get("translations"),
        meaning_fallback=fallback_meaning(q))
    return new


def reading_item(ctx: Context, q: dict, surface: str, row: dict) -> dict | None:
    reading = q["options"][q["answer"]]
    new = dict(q)
    new["options"] = pronounceable(ctx, surface, q["options"], reading)
    if any(IMPOSSIBLE.search(o) for o in new["options"]):
        return None
    q = new
    new["prompt"] = sentence_with(row["sentence"], surface, f"<u>{surface}</u>")
    new["focus"] = surface
    new["explanations"] = reading_choice(
        ctx.d, word=surface, reading=reading, options=q["options"],
        split=ctx.split(surface, reading), translations=row.get("translations"),
        meaning_fallback=fallback_meaning(q))
    return new


def contextualize_advanced(ctx: Context, items: list[dict]) -> list[dict]:
    if not any(FRAME in q["prompt"] for q in items):
        return items                                   # already done
    by_kanji: dict[str, dict[str, dict[tuple[str, str], dict]]] = defaultdict(
        lambda: {"reading": {}, "orthography": {}})
    for q in items:
        if q["kind"] == "reading":
            word = (q.get("focus") or "", q["options"][q["answer"]])
        else:
            fw = frame_word(q)
            if not fw:
                continue
            word = (fw[0], fw[1])
        if word[0] and word in ctx.sentences and word[0] not in BLOCKLIST:
            by_kanji[q["literal"]][q["kind"]].setdefault(word, q)

    def score(w):
        return (ctx.common.get(w, 0), -len(w[0]), w)

    out: list[dict] = []
    for literal in sorted(by_kanji):
        d = by_kanji[literal]
        shared = [w for w in d["reading"] if w in d["orthography"]]
        picks = {"reading": max(shared, key=score), "orthography": max(shared, key=score)} if shared \
            else {k: max(d[k], key=score) for k in d if d[k]}
        for kind, first in picks.items():
            # the chosen word first, then the kanji's other words with a sentence
            for word in [first] + sorted((w for w in d[kind] if w != first), key=score, reverse=True):
                q, row = d[kind][word], ctx.sentences[word]
                if kind == "reading":
                    new = reading_item(ctx, q, word[0], row)
                else:
                    fw = frame_word(q)
                    new = writing_item(ctx, q, fw[0], fw[1], fw[2], row, same_sound_all=False)
                if new:
                    out.append(new)
                    break
    return out


def contextualize_doonkun(ctx: Context, items: list[dict]) -> list[dict]:
    if not any(FRAME in q["prompt"] for q in items):
        return items
    done: list[dict] = []
    left: list[dict] = []
    for q in items:
        fw = frame_word(q)
        row = ctx.sentences.get((fw[0], fw[1])) if fw else None
        new = writing_item(ctx, q, *fw, row, same_sound_all=True) if row else None
        (done if new else left).append(new or q)
    # A kanji whose words all lack a sentence keeps its old item rather than vanish.
    covered = {q["literal"] for q in done}
    kept = [q for q in left if q["literal"] not in covered
            and (frame_word(q) or ("",))[0] not in BLOCKLIST]
    return done + kept


def contextualize_rare(ctx: Context, items: list[dict]) -> list[dict]:
    out: list[dict] = []
    for q in items:
        if q["kind"] == "reading":
            m = re.fullmatch(r"<u>(.*?)</u>", q["prompt"])
            if not m:
                out.append(q)
                continue
            shown, reading = m.group(1), q["options"][q["answer"]]
        else:
            if not q["prompt"].startswith("次のカタカナを漢字に直せ。"):
                out.append(q)
                continue
            shown = q["options"][q["answer"]]
            reading = to_hiragana(q["focus"])
        meaning = {lang: re.sub(r"^.*?[（(]|[）)][。.]?$", "", q["explanations"].get(lang, ""))
                   for lang in ("ko", "ja", "zh", "en")
                   if re.search(r"[（(].*[）)][。.]?$", q["explanations"].get(lang, ""))}
        # No meaning means KANJIDIC's gloss is for another sense than this
        # reading — the reviewers found most of those readings doubtful.
        if not meaning or shown in BLOCKLIST:
            continue
        row = ctx.sentences.get((shown, reading))
        if not row:
            out.append(q)
            continue
        if repeats_okurigana(row["sentence"], shown, reading):
            continue
        new = dict(q)
        if q["kind"] == "reading":
            new["prompt"] = sentence_with(row["sentence"], shown, f"<u>{shown}</u>")
            new["focus"] = shown
            new["explanations"] = reading_choice(
                ctx.d, word=shown, reading=reading, options=q["options"], split=None,
                translations=row.get("translations"), meaning_fallback=meaning, kun_only=True)
        else:
            kata = to_katakana(reading)
            new["prompt"] = sentence_with(row["sentence"], shown, f"<u>{kata}</u>")
            new["focus"] = kata
            firsts = [o[0] for o in q["options"]]
            new["explanations"] = kanji_choice(
                ctx.d, word=shown, reading=reading, answer=shown[0], options=firsts,
                same_sound=set(), translations=row.get("translations"),
                meaning_fallback=meaning)
        out.append(new)
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--sentences", default="sources/context_sentences.jsonl")
    args = parser.parse_args()
    ctx = Context(args.db, args.sentences)
    for path, fn in ((ADVANCED, contextualize_advanced), (DOONKUN, contextualize_doonkun),
                     (RARE, contextualize_rare)):
        items = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
        out = fn(ctx, items)
        in_sentence = sum(1 for q in out if FRAME not in q["prompt"]
                          and not re.fullmatch(r"<u>[^<]*</u>", q["prompt"])
                          and not q["prompt"].startswith("次のカタカナ"))
        Path(path).write_text("".join(json.dumps(q, ensure_ascii=False) + "\n" for q in out),
                              encoding="utf-8")
        print(f"{path}: {len(items)} → {len(out)} ({in_sentence} in a sentence)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
