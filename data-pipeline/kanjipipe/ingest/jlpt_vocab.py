# kanjipipe/ingest/jlpt_vocab.py
"""JLPT vocabulary lists (N5–N1) from jamsinclair/open-anki-jlpt-decks.

The Japan Foundation stopped publishing official lists in 2010; these are the
community lists derived from the tanos.co.uk decks, which is what every JLPT
vocabulary resource draws on. A word listed at more than one level belongs to
the easiest one — that is where a learner first meets it.
"""
from __future__ import annotations

import csv
from pathlib import Path

LEVELS = ("N5", "N4", "N3", "N2", "N1")  # easiest first


def parse_jlpt_vocab(directory: str | Path) -> dict[tuple[str, str], str]:
    """Return {(expression, reading): level} for every listed word."""
    mapping: dict[tuple[str, str], str] = {}
    for level in LEVELS:
        path = Path(directory) / f"{level.lower()}.csv"
        with open(path, encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle):
                expression = (row.get("expression") or "").strip()
                reading = (row.get("reading") or "").strip()
                if not expression or not reading:
                    continue
                # 一つ; ひとつ-style alternates: keep the first spelling only.
                expression = expression.split(";")[0].split("、")[0].strip()
                reading = reading.split(";")[0].split("、")[0].strip()
                mapping.setdefault((expression, reading), level)
    return mapping
