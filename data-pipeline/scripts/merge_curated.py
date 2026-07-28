#!/usr/bin/env python3
"""Merge authored 四字熟語 / 対義語 batches into the curated source files.

Workers validate their own batch independently, so nothing stops two of them
producing the same idiom. Deduplication has to happen here, at the join.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

RES = Path(__file__).resolve().parents[2] / "app/Sources/DictionaryClient/Resources"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("yoji", "taigirui"))
    parser.add_argument("batches", nargs="+")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()

    target = RES / (f"{'yojijukugo' if args.kind == 'yoji' else 'taigirui'}.source.json")
    existing = json.loads(target.read_text(encoding="utf-8"))
    key = ((lambda e: e["yoji"]) if args.kind == "yoji"
           else (lambda e: (e["word"], e["answer"])))
    seen = {key(e) for e in existing}

    added, dupes = [], 0
    for path in args.batches:
        for entry in json.loads(Path(path).read_text(encoding="utf-8")):
            if key(entry) in seen:
                dupes += 1
                continue
            seen.add(key(entry))
            added.append(entry)

    print(f"existing {len(existing)}  new {len(added)}  duplicates dropped {dupes}")
    if args.write:
        target.write_text(
            json.dumps(existing + added, ensure_ascii=False, indent=1) + "\n",
            encoding="utf-8")
        print(f"wrote {len(existing) + len(added)} entries → {target.name}")
    else:
        print("dry run — pass --write to apply")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
