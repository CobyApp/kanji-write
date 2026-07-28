#!/usr/bin/env python3
"""Validate one authored gloss batch on its own, without touching shared state.

Agents run this on their own output before handing it back, so a bad batch is
caught by the author rather than at merge time.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from merge_glosses import script_problem  # noqa: E402


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: check_batch.py <chunk.json> <output.json>", file=sys.stderr)
        return 2
    chunk = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))

    wanted = {e["literal"]: e for e in chunk}
    got = {e.get("literal"): e for e in out}
    problems: list[str] = []

    missing = [lit for lit in wanted if lit not in got]
    if missing:
        problems.append(f"{len(missing)} kanji not covered: {''.join(missing[:20])}")
    extra = [lit for lit in got if lit not in wanted]
    if extra:
        problems.append(f"{len(extra)} kanji not in the chunk: {''.join(extra[:20])}")

    for literal, entry in got.items():
        if literal not in wanted:
            continue
        need = ["ja", "zh"] + (["ko"] if wanted[literal].get("needs_ko") else [])
        for lang in need:
            value = (entry.get(lang) or "").strip()
            if not value:
                problems.append(f"{literal}: missing {lang}")
                continue
            trouble = script_problem(lang, value)
            if trouble:
                problems.append(f"{literal} {lang}: {trouble} — {value!r}")

    if problems:
        print(f"FAIL ({len(problems)} problems)")
        for p in problems[:40]:
            print("  " + p)
        return 1
    print(f"OK — {len(got)} kanji, all required languages present and clean")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
