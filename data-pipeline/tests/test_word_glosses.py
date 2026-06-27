# tests/test_word_glosses.py
from pathlib import Path

from kanjipipe.ingest.word_glosses import parse_word_glosses

FIX = Path(__file__).parent / "fixtures"


def test_parse_word_glosses_keeps_valid_and_skips_bad_lines():
    entries = parse_word_glosses(FIX / "word_glosses_ko_sample.jsonl")
    # Only the two well-formed lines survive; blank/whitespace-ko/non-int-id/
    # malformed/missing-id lines are skipped. ko is stripped.
    assert entries == [(1, "산"), (2, "학교")]
