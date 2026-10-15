#!/usr/bin/env python3
"""Validate enriched ja/ko/zh word glosses before they replace the terse ones.

Each output line: {"id", "ja", "ko", "zh"}. Checks that every target id is
covered exactly once, all three languages are non-empty and in the right script,
and no raw English leaked in. Meaning accuracy is spot-read by a human.

    python scripts/check_gloss_enrichment.py FILE... --targets targets.jsonl
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HANGUL = re.compile(r"[가-힣]")
KANA = re.compile(r"[぀-ヿ]")
HAN = re.compile(r"[一-鿿]")
LATIN_WORD = re.compile(r"[A-Za-z]{3,}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--targets", required=True)
    ap.add_argument("--require-all", action="store_true",
                    help="also require every target id to be present (final merge check)")
    args = ap.parse_args()

    target_ids = {json.loads(l)["id"] for l in Path(args.targets).read_text("utf-8").splitlines() if l.strip()}
    seen: set[int] = set()
    bad = total = 0
    for path in args.files:
        for n, line in enumerate(Path(path).read_text("utf-8").splitlines(), 1):
            if not line.strip():
                continue
            total += 1
            try:
                e = json.loads(line)
            except json.JSONDecodeError as err:
                print(f"{path}:{n}: bad JSON: {err}"); bad += 1; continue
            issues = []
            wid = e.get("id")
            if wid not in target_ids:
                issues.append(f"id {wid} not a target")
            if wid in seen:
                issues.append("duplicate id")
            seen.add(wid)
            ja, ko, zh = (e.get("ja") or ""), (e.get("ko") or ""), (e.get("zh") or "")
            if not (KANA.search(ja) or HAN.search(ja)):
                issues.append("ja empty/!Japanese")
            if not HANGUL.search(ko):
                issues.append("ko empty/!Korean")
            if KANA.search(ko):
                issues.append("kana in ko")
            if not HAN.search(zh):
                issues.append("zh empty/!Chinese")
            if KANA.search(zh) or HANGUL.search(zh):
                issues.append("kana/hangul in zh")
            for lang, text in (("ja", ja), ("ko", ko), ("zh", zh)):
                if LATIN_WORD.search(text):
                    issues.append(f"English left in {lang}")
            if issues:
                bad += 1
                print(f"{path}:{n} [{wid}]: " + "; ".join(issues))
    if args.require_all:
        missing = target_ids - seen
        if missing:
            print(f"missing {len(missing)} target ids (e.g. {sorted(missing)[:5]})")
            bad += len(missing)
    if bad:
        print(f"FAIL — {bad} issues across {total} glosses")
        return 1
    print(f"OK — {total} glosses, all valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
