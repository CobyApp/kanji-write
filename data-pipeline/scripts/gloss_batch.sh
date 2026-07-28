#!/bin/bash
# Emit the next batch of kanji needing a ja/zh gloss, compactly enough to author
# from: literal, English gloss, and the readings that disambiguate it.
cd "$(dirname "$0")/.."
LIMIT="${1:-200}"
.venv/bin/python scripts/gloss_gaps.py --emit ja --limit "$LIMIT" \
  | .venv/bin/python -c '
import json,sys
for e in json.load(sys.stdin):
    hint = e["kun"] or e["on"]
    print(f'"'"'{e["literal"]}\t{e["en"]}\t{hint}'"'"')'
