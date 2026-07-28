#!/usr/bin/env python3
"""Merge authored question batches into one bank, evening out answer position.

Agents pick where the correct option sits, and they do not pick uniformly: one
batch put the answer in the fourth slot three times out of 32 and another never
did. That is exploitable — a learner who notices stops reading the options. So
options are reshuffled here with a fixed seed.

熟語の構成 is exempt: its four options are a fixed label list that the real paper
always prints in the same order, so shuffling them would be wrong rather than
fair.
"""
from __future__ import annotations

import argparse
import json
import random
from collections import Counter
from pathlib import Path

FIXED_ORDER_KINDS = {"kousei"}
SEED = 20260728


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("batches", nargs="+")
    parser.add_argument("--out", default="sources/kanken_authored_questions.jsonl")
    args = parser.parse_args()

    rng = random.Random(SEED)
    out: list[dict] = []
    by_kind: Counter[str] = Counter()
    for path in sorted(args.batches):
        for line in Path(path).read_text(encoding="utf-8").splitlines():
            if not line.strip():
                continue
            q = json.loads(line)
            if q.get("kind") not in FIXED_ORDER_KINDS:
                correct = q["options"][q["answer"]]
                options = list(q["options"])
                rng.shuffle(options)
                q["options"] = options
                q["answer"] = options.index(correct)
            out.append(q)
            by_kind[f"{q.get('kind')} {q.get('level')}"] += 1

    Path(args.out).write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")
    print(f"wrote {len(out)} authored questions → {args.out}")
    for key, n in sorted(by_kind.items()):
        print(f"  {key}: {n}")
    spread = Counter(q["answer"] for q in out if q.get("kind") not in FIXED_ORDER_KINDS)
    print(f"  answer position spread (shuffled kinds): {dict(sorted(spread.items()))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
