#!/usr/bin/env python3
"""Check every generated 準1級/1級 question against the vocabulary it came from.

The generator is mechanical, so its failure mode is not a typo but a whole class
of broken questions — a distractor that is secretly also correct, an answer
visible in the prompt. This re-derives each claim from the database rather than
trusting the generator, and exits non-zero on the first class of violation found.
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
from collections import defaultdict
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from kanjipipe.questions import kata_to_hira, load_jmdict_lexicon  # noqa: E402

UNDERLINE = re.compile(r"</?u>")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--questions", default="sources/kanken_advanced_questions.jsonl")
    parser.add_argument("--jmdict", default="sources/jmdict.xml",
                        help="JMdict XML for the full reading/spelling sets "
                             "('' to use the vocabulary table only)")
    args = parser.parse_args()

    con = sqlite3.connect(args.db)
    readings_by_surface: dict[str, set[str]] = defaultdict(set)
    for surface, reading in con.execute("SELECT surface, reading_kana FROM word"):
        readings_by_surface[surface].add(kata_to_hira(reading))
    # The vocabulary table keeps one reading per JMdict entry; the generator
    # answers with the standard one (肋骨 ろっこつ, where the row has
    # あばらぼね) and must avoid all of them, so check against every reading
    # and spelling JMdict has.
    if args.jmdict and Path(args.jmdict).exists():
        for surface, readings in load_jmdict_lexicon(args.jmdict).readings.items():
            readings_by_surface[surface] |= readings
    all_surfaces = set(readings_by_surface)
    advanced = {
        literal for (literal,) in con.execute(
            "SELECT literal FROM kanji WHERE kanken_level IN ('準1級','1級')")
    }
    con.close()

    problems: dict[str, list[str]] = defaultdict(list)
    total = 0
    for line in Path(args.questions).read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        total += 1
        q = json.loads(line)
        where = f"{q['kind']} 「{q['literal']}」 {q['prompt']}"
        options, answer = q["options"], q["answer"]
        clean = UNDERLINE.sub("", q["prompt"])

        if len(options) != 4:
            problems["not four options"].append(where)
        if len(set(options)) != len(options):
            problems["duplicate options"].append(where)
        if not 0 <= answer < len(options):
            problems["answer out of range"].append(where)
            continue
        correct = options[answer]
        if correct in clean:
            problems["answer visible in prompt"].append(where)
        if q["literal"] not in advanced:
            problems["not an advanced kanji"].append(where)
        if q["focus"] not in clean:
            problems["focus not in prompt"].append(where)
        for lang in ("ko", "ja", "zh", "en"):
            if not q["explanations"].get(lang, "").strip():
                problems[f"missing {lang} explanation"].append(where)

        if q["kind"] == "reading":
            surface = q["focus"]
            valid = readings_by_surface.get(surface, set())
            if kata_to_hira(correct) not in valid:
                problems["answer is not a reading of the word"].append(where)
            for option in options:
                if option != correct and kata_to_hira(option) in valid:
                    problems["distractor is also a valid reading"].append(where)
        elif q["kind"] == "orthography":
            blanked = q["focus"]
            if blanked.count("□") != 1:
                problems["blank is not a single slot"].append(where)
                continue
            for option in options:
                spelled = blanked.replace("□", option)
                exists = spelled in all_surfaces
                if option == correct and not exists:
                    problems["answer does not spell a real word"].append(where)
                if option != correct and exists:
                    problems["distractor also spells a real word"].append(where)
        else:
            problems["unknown kind"].append(where)

    print(f"checked {total} questions")
    if not problems:
        print("all invariants hold")
        return 0
    for name, cases in sorted(problems.items(), key=lambda kv: -len(kv[1])):
        print(f"\n{name}: {len(cases)}")
        for case in cases[:5]:
            print(f"    {case}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
