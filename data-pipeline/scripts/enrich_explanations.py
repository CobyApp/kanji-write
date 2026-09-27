#!/usr/bin/env python3
"""Say what every wrong option is, in banks whose explanations skip some.

Most authored explanations explain the answer well but leave two or three
options unexplained — and "why not ウ?" is half of what a learner wants from a
解説. For each question whose options are kanji or words, this appends one
line naming each option the explanation does not already mention: a kanji
with its 훈음 / meaning (耀 빛날 요), a word with its meaning (監禁 감금).
Readings (kana options) and sentence options are left alone, and nothing is
appended twice: running it again changes nothing.

    python scripts/enrich_explanations.py sources/jlpt_questions.jsonl ...
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from kanjipipe.explain import LANGS, OTHER, Dictionary, _gloss_for_surface, _short, option_notes  # noqa: E402

# Kinds whose options are kanji or words; the rest are readings, sentences or
# fixed labels (熟語の構成's ア〜オ).
KINDS = {"orthography", "context", "iikae", "gokeisei", "sanji", "tsukuri", "kyotsu",
         "shikibetsu", "hantai", "taigi", "goselect", "doonkun"}


def gloss_words(d: Dictionary, words: list[str], text: str, lang: str) -> str:
    """漢字識別: 「添付・添乗・添削」 → 「添付(첨부)·添乗(…)·添削(첨삭)」, once."""
    joined = "・".join(words)
    if joined not in text:
        return text
    parts = []
    for w in words:
        meaning = next((_short(g.get(lang, ""), 14 if lang != "en" else 24)
                        for _, g in _gloss_for_surface(d, w) if g.get(lang)), "")
        parts.append(f"{w}({meaning})" if meaning and lang in ("ko", "en")
                     else f"{w}（{meaning}）" if meaning else w)
    sep = "·" if lang == "ko" else "、" if lang in ("ja", "zh") else ", "
    return text.replace(joined, sep.join(parts), 1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("files", nargs="+")
    parser.add_argument("--db", default="out/kanji.sqlite")
    args = parser.parse_args()
    d = Dictionary.load(args.db)
    for path in args.files:
        lines = open(path, encoding="utf-8").read().splitlines()
        out, touched = [], 0
        for line in lines:
            q = json.loads(line)
            ex = q.get("explanations") or {}
            if q["kind"] in KINDS and not any(OTHER[lang] in ex.get(lang, "") for lang in LANGS):
                answer = q["options"][q["answer"]]
                changed = False
                for lang in LANGS:
                    if lang not in ex:
                        continue
                    note = option_notes(d, q["options"], answer, ex[lang], lang)
                    if note:
                        ex[lang] = ex[lang].rstrip() + "\n" + note
                        changed = True
                if q["kind"] == "shikibetsu":
                    frame = re.sub(r"</?u>", "", q["prompt"]).split("　")
                    words = [f.replace("□", answer) for f in frame if "□" in f]
                    for lang in LANGS:
                        if lang in ex:
                            ex[lang] = gloss_words(d, words, ex[lang], lang)
                    changed = True
                if changed:
                    q["explanations"] = ex
                    touched += 1
            out.append(json.dumps(q, ensure_ascii=False))
        Path(path).write_text("\n".join(out) + "\n", encoding="utf-8")
        print(f"{path}: {touched} explanations gained an options line")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
