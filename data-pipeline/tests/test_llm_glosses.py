# tests/test_llm_glosses.py
from pathlib import Path

from kanjipipe.ingest.llm_glosses import parse_llm_glosses

FIXTURE = Path(__file__).parent / "fixtures" / "llm_glosses_sample.jsonl"


def test_parses_jsonl_entries_skipping_blank_lines():
    entries = parse_llm_glosses(FIXTURE)
    assert [e.literal for e in entries] == ["山", "学", "未"]  # blank line skipped


def test_extracts_all_three_languages():
    yama = next(e for e in parse_llm_glosses(FIXTURE) if e.literal == "山")
    assert yama.ko == "메 산"
    assert yama.ja == "やま。地面が高く盛り上がった所。"
    assert yama.zh == "山。"


def test_missing_field_becomes_none():
    mi = next(e for e in parse_llm_glosses(FIXTURE) if e.literal == "未")
    assert mi.ko == "아닐 미"
    assert mi.ja is None      # absent in the fixture line
    assert mi.zh == "未。"
