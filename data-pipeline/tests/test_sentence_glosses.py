# tests/test_sentence_glosses.py
from pathlib import Path

from kanjipipe.ingest.sentence_glosses import parse_sentence_glosses

FIX = Path(__file__).parent / "fixtures"


def test_parse_sentence_glosses_keeps_valid_and_skips_bad_lines():
    entries = parse_sentence_glosses(FIX / "sentence_glosses_sample.jsonl")
    # Line 1: both translations. Line 3: whitespace-only ko → None, zh kept.
    # Line 6: ko only. Skipped: no-ja, blank, malformed, and neither-ko-nor-zh.
    assert entries == [
        ("山に登る。", "산에 오른다.", "爬山。"),
        ("学校", None, "学校"),
        ("海", "바다", None),
    ]
