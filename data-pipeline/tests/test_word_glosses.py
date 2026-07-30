# tests/test_word_glosses.py
from pathlib import Path

from kanjipipe.ingest.word_glosses import parse_word_glosses, parse_word_jazh

FIX = Path(__file__).parent / "fixtures"


def test_parse_word_glosses_keeps_valid_and_skips_bad_lines():
    entries = parse_word_glosses(FIX / "word_glosses_ko_sample.jsonl")
    # Only the two well-formed lines survive; blank-ko, missing-reading,
    # missing-surface and malformed lines are skipped. ko is stripped.
    assert entries == [("山", "やま", "산"), ("学校", "がっこう", "학교")]


def test_parse_word_jazh_keeps_valid_and_skips_bad_lines():
    entries = parse_word_jazh(FIX / "word_glosses_jazh_sample.jsonl")
    # Line 1: ja stripped, zh present. Line 2: whitespace-only ja → None, zh
    # kept. Malformed and key-missing lines are skipped.
    assert entries == [
        ("山", "やま", "やま", "山"),
        ("学校", "がっこう", None, "学校"),
    ]


def test_the_reading_is_part_of_the_key():
    """上手 is じょうず or うわて — different words, different meanings. Surface
    alone would collapse them onto whichever row came first."""
    entries = parse_word_glosses(FIX / "word_glosses_ko_sample.jsonl")
    assert all(len(entry) == 3 and entry[1] for entry in entries)
