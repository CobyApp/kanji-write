#!/usr/bin/env python3
"""読み / 書き取り for 準1級・1級 kanji that no dictionary word uses.

About 950 advanced kanji appear in no JMdict compound, so there is no attested
word to build a sentence question on — and inventing one would be a guess. What
these kanji do have is a KANJIDIC 訓読み, which is exactly what the 1級 paper's
一字訓読み asks for (鰯 → いわし, 俛せる → ふせる). So each gets:

* 読み: the kanji (with its okurigana) → pick its 訓読み.
* 書き取り: the 訓読み in katakana → pick the kanji.

Distractors are other advanced kanji's 訓読み / glyphs with the same okurigana
and a similar length, so the ending never gives the answer away. A distractor
is rejected when it shares any 訓読み with the answer (鰯 and 鰮 are both
いわし), since that would be a second right answer.

    python scripts/generate_rare_kun_questions.py  # → sources/kanken_rare_kun_questions.jsonl
"""
from __future__ import annotations

import argparse
import json
import random
import sqlite3
from collections import defaultdict
from pathlib import Path

SEED = 20260927
LEVELS = ("準1級", "1級")


def split_kun(value: str) -> tuple[str, str] | None:
    """'ふ.せる' → ('ふ', 'せる'); 'いわし' → ('いわし', ''). None for affixes."""
    if "-" in value or not value:
        return None
    stem, _, okuri = value.partition(".")
    if len(stem) + len(okuri) < 2:
        return None
    return stem, okuri


def to_katakana(text: str) -> str:
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--lexicon", default="/tmp/jmlex.json",
                        help="JSON {surface: [readings]} of JMdict; kanji used in any "
                             "2–4 character word are left to the word-based bank")
    parser.add_argument("--out", default="sources/kanken_rare_kun_questions.jsonl")
    args = parser.parse_args()

    in_words: set[str] = set()
    # Readings JMdict gives a kanji written alone (駮 → ふち): a distractor that
    # is one of these would be a second right answer.
    solo_readings: dict[str, set[str]] = defaultdict(set)
    if Path(args.lexicon).exists():
        surfaces = json.loads(Path(args.lexicon).read_text("utf-8"))
        for surface, readings in surfaces.items():
            if len(surface) == 1:
                solo_readings[surface].update(readings)
    else:  # read the headwords straight from the JMdict build input
        from lxml import etree
        surfaces = []
        for _, entry in etree.iterparse("sources/jmdict.xml", tag="entry", load_dtd=False,
                                        resolve_entities=False, huge_tree=True):
            surfaces.extend(k.text for k in entry.iter("keb") if k.text)
            entry.clear()
    for surface in surfaces:
        if 2 <= len(surface) <= 4:
            in_words.update(surface)

    con = sqlite3.connect(args.db)
    levels: dict[int, set[str]] = defaultdict(set)
    for kid, level in con.execute("SELECT kanji_id, level_label FROM kanken_membership"):
        levels[kid].add(level)
    # Coverage from every *other* bank. This script's own rows (a bare
    # underlined kanji, or the 次のカタカナを… stem) may already be in the
    # database from a previous run and must not count.
    covered: dict[int, set[str]] = defaultdict(set)
    literal_by_id = dict(con.execute("SELECT id, literal FROM kanji"))
    for kid, kind, prompt in con.execute(
            "SELECT kanji_id, kind, prompt FROM jlpt_question "
            "WHERE kind IN ('reading','orthography')"):
        literal = literal_by_id.get(kid, "")
        own = (prompt.startswith("次のカタカナを漢字に直せ。")
               or (prompt.startswith("<u>" + literal) and prompt.endswith("</u>")
                   and len(prompt) <= len(literal) + 12 and kind == "reading"
                   and all("\u3040" <= c <= "\u309f" for c in prompt[3 + len(literal):-4])))
        if not own:
            covered[kid].add(kind)
    kun_all: dict[int, list[str]] = defaultdict(list)
    for kid, value in con.execute(
            "SELECT kanji_id, value FROM reading WHERE lang_axis = 'kun' ORDER BY id"):
        kun_all[kid].append(value)
    glosses: dict[int, dict[str, str]] = defaultdict(dict)
    for kid, lang, text in con.execute("SELECT kanji_id, lang, text FROM gloss"):
        glosses[kid].setdefault(lang, text)
    literal_of = dict(con.execute("SELECT id, literal FROM kanji"))
    con.close()

    # Every advanced kanji's primary 訓読み, as the distractor pool.
    entries = []
    for kid, literal in literal_of.items():
        if not (levels[kid] & set(LEVELS)):
            continue
        parts = next((p for p in map(split_kun, kun_all[kid]) if p), None)
        if parts is None:
            continue
        readings = {v.replace(".", "") for v in kun_all[kid] if "-" not in v}
        readings |= solo_readings.get(literal, set())
        level = "準1級" if "準1級" in levels[kid] else "1級"
        entries.append({"id": kid, "literal": literal, "stem": parts[0],
                        "okuri": parts[1], "readings": readings, "level": level})
    by_okuri: dict[str, list[dict]] = defaultdict(list)
    for entry in entries:
        by_okuri[entry["okuri"]].append(entry)

    rng = random.Random(SEED)
    out: list[dict] = []
    for entry in entries:
        if entry["literal"] in in_words:
            continue
        need = {"reading", "orthography"} - covered[entry["id"]]
        if not need:
            continue
        answer_reading = entry["stem"] + entry["okuri"]
        pool = [e for e in by_okuri[entry["okuri"]]
                if e["id"] != entry["id"]
                and not (e["readings"] & entry["readings"])
                and abs(len(e["stem"]) - len(entry["stem"])) <= 1]
        if len(pool) < 3:
            continue
        rng.shuffle(pool)
        picks = []
        for e in pool:
            reading = e["stem"] + e["okuri"]
            if reading != answer_reading and all(reading != p["stem"] + p["okuri"] for p in picks):
                picks.append(e)
            if len(picks) == 3:
                break
        if len(picks) < 3:
            continue
        g = glosses[entry["id"]]
        meaning = {lang: (g.get(lang) or g.get("en") or "").rstrip("。.．")
                   for lang in ("ko", "ja", "zh", "en")}
        shown = entry["literal"] + entry["okuri"]

        def explain(kind: str) -> dict[str, str]:
            m = meaning
            return {
                "ko": f"「{shown}」의 훈독은 {answer_reading}입니다" + (f"({m['ko']})." if m["ko"] else "."),
                "ja": f"「{shown}」の訓読みは {answer_reading} です" + (f"（{m['ja']}）。" if m["ja"] else "。"),
                "zh": f"「{shown}」的训读是 {answer_reading}" + (f"（{m['zh']}）。" if m["zh"] else "。"),
                "en": f"The kun reading of 「{shown}」 is {answer_reading}" + (f" ({m['en']})." if m["en"] else "."),
            }

        if "reading" in need:
            options = [answer_reading] + [p["stem"] + p["okuri"] for p in picks]
            rng.shuffle(options)
            out.append({
                "literal": entry["literal"], "level": entry["level"], "kind": "reading",
                "prompt": f"<u>{shown}</u>", "focus": shown,
                "options": options, "answer": options.index(answer_reading),
                "explanations": explain("reading")})
        if "orthography" in need:
            options = [shown] + [p["literal"] + p["okuri"] for p in picks]
            rng.shuffle(options)
            kata = to_katakana(answer_reading)
            out.append({
                "literal": entry["literal"], "level": entry["level"], "kind": "orthography",
                "prompt": f"次のカタカナを漢字に直せ。{kata}", "focus": kata,
                "options": options, "answer": options.index(shown),
                "explanations": explain("orthography")})

    Path(args.out).write_text(
        "".join(json.dumps(q, ensure_ascii=False) + "\n" for q in out), encoding="utf-8")
    print(f"wrote {len(out)} questions for rare advanced kanji → {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
