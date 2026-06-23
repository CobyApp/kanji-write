# tests/test_validate.py
import pytest

from kanjipipe.db import init_db
from kanjipipe.loader import load_kanji
from kanjipipe.models import Gloss, Kanji, Reading
from kanjipipe.validate import assert_core_gates, coverage_report


def _good():
    return Kanji(literal="山", codepoint=0x5C71, stroke_count=3, grade=1,
                 freq_rank=360, radical=46, jlpt_level="N5",
                 readings=[Reading("on", "サン")],
                 glosses=[Gloss("en", "mountain")])


def test_coverage_report_counts_gaps():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    report = coverage_report(conn)
    assert report["total"] == 1
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0
    assert report["missing_grade"] == 0


def test_assert_core_gates_passes_on_complete_data():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    assert assert_core_gates(conn)["total"] == 1


def test_assert_core_gates_fails_when_english_missing():
    conn = init_db(":memory:")
    no_gloss = _good()
    no_gloss.glosses = []
    load_kanji(conn, [no_gloss])
    with pytest.raises(ValueError, match="missing EN meaning"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_on_empty_db():
    conn = init_db(":memory:")
    with pytest.raises(ValueError, match="no kanji loaded"):
        assert_core_gates(conn)
