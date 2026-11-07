#!/usr/bin/env python3
"""Validate ja/zh gloss corrections before they overwrite the corrupt ones.

Each output line: {"id", "ja", "zh"}. Checks that every id is a known target,
appears once, ja is Japanese (kana/kanji), zh is Chinese (Han, no kana/hangul),
and no stray English leaked in (a short allow-list covers real acronyms). The
meaning itself is spot-read by a human.

    python scripts/check_gloss_fix.py FILE... --targets targets.jsonl
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
# Acronyms / units / scientific-name tokens that legitimately appear.
ALLOW = re.compile(
    r"^(DNA|RNA|PIN|ISO|JIS|OCR|ADHD|COVID|PVC|GNP|GDP|LDL|HDL|NaOH|MSG|LAN|"
    r"JICA|TA|QBIN|PC|TV|AI|IT|CD|DVD|USB|LED|UV|pH|km|cm|mm|kHz|MHz|GHz|NaCl|"
    r"CO|Firefox|Windows|Cannabis|Quercus|Primula|Viola|Lemna|Angelica|Vespa|"
    r"Hirudo|Saccostrea|Lethrinus|Turbinellus|Tricholoma|Trachycephalus|"
    r"Carpesium|Velinus|Desmarestia|Chelonomorpha|sativa|acuta|japona|gibba|"
    r"nipponia|kegaki|eizanensis|cuneifolia|haematopterus|resinifictrix|"
    r"ursina|floccosus|fulvocastaneum|divaricatum|nodipes|tabacoides|velutina|"
    r"spp|var|sp)$"
)


def latin_leak(text: str) -> bool:
    return any(not ALLOW.match(tok) for tok in LATIN_WORD.findall(text))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--targets", required=True)
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
            ja, zh = (e.get("ja") or ""), (e.get("zh") or "")
            if not (KANA.search(ja) or HAN.search(ja)):
                issues.append("ja empty/!Japanese")
            if HANGUL.search(ja):
                issues.append("hangul in ja")
            if not HAN.search(zh):
                issues.append("zh empty/!Chinese")
            if KANA.search(zh) or HANGUL.search(zh):
                issues.append("kana/hangul in zh")
            if latin_leak(ja):
                issues.append("English left in ja")
            if latin_leak(zh):
                issues.append("English left in zh")
            if issues:
                bad += 1
                print(f"{path}:{n} [{wid}]: " + "; ".join(issues))
    if bad:
        print(f"FAIL — {bad} issues across {total} corrections")
        return 1
    print(f"OK — {total} corrections, all valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
