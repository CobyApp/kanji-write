"""Parse the LLM-generated JLPT question bank JSONL.

Each line: {literal, level, kind, prompt, options:[...], answer:int, explanation}.
Lines that are malformed or fail basic validity (need 4 options and an in-range
answer) are skipped rather than aborting the whole build.
"""
from __future__ import annotations

import json
from pathlib import Path

from kanjipipe.models import JlptQuestion


def parse_jlpt_questions(path: str | Path) -> list[JlptQuestion]:
    entries: list[JlptQuestion] = []
    with open(path, encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as error:
                print(f"jlpt_questions: skipping malformed line {line_number}: {error}")
                continue
            literal = obj.get("literal")
            prompt = obj.get("prompt")
            options = obj.get("options")
            answer = obj.get("answer")
            if not literal or not prompt or not isinstance(options, list):
                continue
            options = [o for o in options if isinstance(o, str) and o.strip()]
            if len(options) < 2 or not isinstance(answer, int) or not (0 <= answer < len(options)):
                continue
            # Explanations: a lang→text object. Accept a legacy single-string
            # `explanation` (treated as Korean) for backward compatibility.
            explanations = obj.get("explanations")
            if not isinstance(explanations, dict):
                legacy = obj.get("explanation")
                explanations = {"ko": legacy} if isinstance(legacy, str) and legacy.strip() else {}
            explanations = {k: v.strip() for k, v in explanations.items()
                            if isinstance(v, str) and v.strip()}
            focus = obj.get("focus")
            # A focus must be a real substring of the prompt to underline it.
            focus = focus if isinstance(focus, str) and focus and focus in prompt else None
            entries.append(JlptQuestion(
                literal=literal,
                level=str(obj.get("level") or ""),
                kind=str(obj.get("kind") or "context"),
                prompt=prompt,
                options=options,
                answer=answer,
                explanations=explanations,
                focus=focus,
            ))
    return entries
