#!/usr/bin/env python3
"""Validate a proposed 四字熟語 or 対義語・類義語 batch before it is merged.

These are authored, not derived, so the risk is an invented idiom or a pairing
that is not actually opposite. What can be checked mechanically is checked:
every character must be a kanji we actually ship, the entry must belong at the
level it claims (it has to use at least one kanji introduced there), readings
must be kana of a plausible length, and nothing may duplicate the curated set.
"""
from __future__ import annotations

import json
import sqlite3
import sys
from pathlib import Path

DB = "out/kanji.sqlite"
RES = Path(__file__).resolve().parents[2] / "app/Sources/DictionaryClient/Resources"


def kana(text: str) -> bool:
    return bool(text) and all("ぁ" <= c <= "ゟ" or c == "ー" for c in text)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: check_curated_batch.py <yoji|taigirui> <batch.json>", file=sys.stderr)
        return 2
    kind, path = sys.argv[1], sys.argv[2]
    batch = json.loads(Path(path).read_text(encoding="utf-8"))

    con = sqlite3.connect(DB)
    level_of = dict(con.execute(
        "SELECT k.literal, km.level_label FROM kanji k "
        "JOIN kanken_membership km ON km.kanji_id = k.id"))
    con.close()
    inventory = set(level_of)

    existing_path = RES / (f"{'yojijukugo' if kind == 'yoji' else 'taigirui'}.source.json")
    existing = json.loads(existing_path.read_text(encoding="utf-8"))
    seen = {e["yoji"] if kind == "yoji" else (e["word"], e["answer"]) for e in existing}

    problems: list[str] = []
    for i, e in enumerate(batch):
        tag = f"[{i}]"
        level = e.get("level")
        if level not in ("準1級", "1級"):
            problems.append(f"{tag} level must be 準1級 or 1級, got {level!r}")
            continue

        if kind == "yoji":
            yoji, reading = e.get("yoji", ""), e.get("reading", "")
            tag = f"[{yoji}]"
            if len(yoji) != 4:
                problems.append(f"{tag} not four characters")
            if yoji in seen:
                problems.append(f"{tag} already in the curated set")
            seen.add(yoji)
            words = [yoji]
            if not kana(reading) or not 4 <= len(reading) <= 16:
                problems.append(f"{tag} reading {reading!r} is not plausible kana")
            for field in ("meaningJa", "meaningKo"):
                if not (e.get(field) or "").strip():
                    problems.append(f"{tag} missing {field}")
        else:
            word, answer = e.get("word", ""), e.get("answer", "")
            tag = f"[{word}→{answer}]"
            if (word, answer) in seen:
                problems.append(f"{tag} already in the curated set")
            seen.add((word, answer))
            words = [word, answer]
            if e.get("relation") not in ("対義", "類義"):
                problems.append(f"{tag} relation must be 対義 or 類義")
            for field in ("wordReading", "answerReading"):
                if not kana(e.get(field, "")):
                    problems.append(f"{tag} {field} is not kana")
            if not word or not answer or word == answer:
                problems.append(f"{tag} word and answer must differ and be present")

        chars = {c for w in words for c in w}
        unknown = sorted(chars - inventory)
        if unknown:
            problems.append(f"{tag} uses kanji we do not ship: {''.join(unknown)}")
            continue
        if not any(level_of[c] == level for c in chars):
            problems.append(f"{tag} no {level} kanji — it does not belong at this level")

    if problems:
        print(f"FAIL ({len(problems)} problems)")
        for p in problems[:40]:
            print("  " + p)
        return 1
    print(f"OK — {len(batch)} entries, all plausible and new")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
