#!/usr/bin/env python3
"""Validate an authored question batch against the shipped inventory.

Authored questions go through the same gate as generated ones at build time, but
that is too late to be useful to whoever wrote them. This runs the same checks
standalone: the target kanji must exist at the level claimed, four distinct
options, an in-range answer, all four languages, and the asymmetric rule — a
読み question must show its kanji, a fill-in-the-blank must not show its answer.
"""
from __future__ import annotations

import json
import re
import sqlite3
import sys
from pathlib import Path

UNDERLINE = re.compile(r"</?u>")
WRITE_KINDS = {"orthography", "context", "doonkun", "shikibetsu", "goji",
               "kousei", "tsukuri", "goselect", "kotowaza", "jukujikun",
               "hyogai", "sanji", "hantai", "taigi"}


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check_question_batch.py <batch.jsonl-or-json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")
    batch = (json.loads(text) if text.lstrip().startswith("[")
             else [json.loads(l) for l in text.splitlines() if l.strip()])

    con = sqlite3.connect("out/kanji.sqlite")
    # A kanji can sit in both 準1級 and 1級, so keep every level it has.
    levels_of: dict[str, set[str]] = {}
    for literal, level in con.execute(
            "SELECT k.literal, km.level_label FROM kanji k "
            "JOIN kanken_membership km ON km.kanji_id = k.id"):
        levels_of.setdefault(literal, set()).add(level)
    level_of = {literal: min(levels) for literal, levels in levels_of.items()}
    # JLPT 大問 (語形成, 用法, 言い換え類義) are keyed by N-level, and the app
    # looks them up with `jlpt_level = ?`, not by 級.
    jlpt_of = dict(con.execute(
        "SELECT literal, jlpt_level FROM kanji WHERE jlpt_level IS NOT NULL"))
    con.close()

    problems: list[str] = []
    for i, q in enumerate(batch):
        literal, level = q.get("literal"), q.get("level")
        clean = UNDERLINE.sub("", q.get("prompt") or "")
        tag = f"[{i}:{q.get('kind')}:{literal}]"

        if literal not in level_of:
            problems.append(f"{tag} literal is not a kanji we ship")
            continue
        if str(level).startswith("N"):
            actual = jlpt_of.get(literal)
            if actual != level:
                problems.append(
                    f"{tag} claims {level} but {literal} is "
                    f"{actual or 'not in any JLPT level'}")
        elif level not in levels_of[literal]:
            problems.append(
                f"{tag} claims {level} but {literal} is introduced at {level_of[literal]}")
        options = q.get("options") or []
        # 熟語の構成 prints its five ア〜オ categories as the options.
        want = 5 if q.get("kind") == "kousei" else 4
        if len(options) != want or len(set(options)) != want:
            problems.append(f"{tag} needs {want} distinct options, got {options}")
        answer = q.get("answer")
        if not isinstance(answer, bool) and isinstance(answer, int) and 0 <= answer < len(options):
            correct = options[answer]
            if q.get("kind") in WRITE_KINDS and str(correct) in clean:
                problems.append(f"{tag} prompt shows its answer {correct!r}")
        else:
            problems.append(f"{tag} answer index out of range")
        if not clean.strip():
            problems.append(f"{tag} empty prompt")
        focus = q.get("focus")
        if focus and focus not in clean:
            problems.append(f"{tag} focus {focus!r} is not in the prompt")
        ex = q.get("explanations") or {}
        for lang in ("ko", "ja", "zh", "en"):
            if not (ex.get(lang) or "").strip():
                problems.append(f"{tag} missing {lang} explanation")
        for lang in ("ja", "zh", "en"):
            if re.search(r"[\uac00-\ud7a3]", ex.get(lang) or ""):
                problems.append(f"{tag} Korean text in the {lang} explanation")

    if problems:
        print(f"FAIL ({len(problems)} problems)")
        for p in problems[:40]:
            print("  " + p)
        return 1
    print(f"OK — {len(batch)} questions, all valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
