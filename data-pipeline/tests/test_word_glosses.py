# tests/test_word_glosses.py
from pathlib import Path

from kanjipipe.ingest.word_glosses import parse_word_glosses, parse_word_jazh

FIX = Path(__file__).parent / "fixtures"


def test_parse_word_glosses_keeps_valid_and_skips_bad_lines():
    entries = parse_word_glosses(FIX / "word_glosses_ko_sample.jsonl")
    # Only the two well-formed lines survive; blank/whitespace-ko/non-int-id/
    # malformed/missing-id lines are skipped. ko is stripped. The fixture records
    # no surface, so that slot comes back None and the loader skips its check.
    assert entries == [(1, "산", None), (2, "학교", None)]


def test_parse_word_jazh_keeps_valid_and_skips_bad_lines():
    entries = parse_word_jazh(FIX / "word_glosses_jazh_sample.jsonl")
    # Line 1: ja stripped, zh present. Line 2: whitespace-only ja → None, zh
    # present. Blank/malformed/missing-id and non-integer-id (string, bool)
    # lines are skipped.
    assert entries == [(1, "やま", "山", None), (2, None, "学校", None)]


def test_parse_word_glosses_carries_the_recorded_surface(tmp_path):
    """The surface is what lets the loader tell a shifted id from a good one."""
    path = tmp_path / "ko.jsonl"
    path.write_text('{"id": 7, "ko": "학교", "surface": "学校"}\n', encoding="utf-8")

    assert parse_word_glosses(path) == [(7, "학교", "学校")]
