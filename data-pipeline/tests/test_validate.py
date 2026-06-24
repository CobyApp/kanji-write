# tests/test_validate.py
import pytest

from kanjipipe.db import init_db
from kanjipipe.loader import load_kanji, load_stroke_order, load_words
from kanjipipe.models import Gloss, Kanji, Reading, Word
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
    assert report["missing_stroke_order"] == 1  # _good() has no strokes seeded


def test_assert_core_gates_passes_on_complete_data():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert assert_core_gates(conn)["total"] == 1


def test_assert_core_gates_fails_when_english_missing():
    conn = init_db(":memory:")
    no_gloss = _good()
    no_gloss.glosses = []
    load_kanji(conn, [no_gloss])
    with pytest.raises(ValueError, match="missing EN meaning"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_when_reading_missing():
    conn = init_db(":memory:")
    no_reading = _good()
    no_reading.readings = []
    load_kanji(conn, [no_reading])
    with pytest.raises(ValueError, match="missing readings"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_when_grade_missing():
    conn = init_db(":memory:")
    no_grade = _good()
    no_grade.grade = None
    load_kanji(conn, [no_grade])
    with pytest.raises(ValueError, match="missing grade"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_on_empty_db():
    conn = init_db(":memory:")
    with pytest.raises(ValueError, match="no kanji loaded"):
        assert_core_gates(conn)


def test_assert_core_gates_fails_when_stroke_order_missing():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])          # has reading + EN gloss + grade, but no strokes
    with pytest.raises(ValueError, match="missing stroke order"):
        assert_core_gates(conn)


def test_assert_core_gates_passes_with_stroke_order():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])          # _good() is 山, codepoint 0x5C71
    load_stroke_order(conn, {0x5C71: ["d1"]})
    assert assert_core_gates(conn)["missing_stroke_order"] == 0


def test_coverage_report_counts_kanji_without_words():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])                 # 山, codepoint 0x5C71
    load_stroke_order(conn, {0x5C71: ["d1"]})
    # no words yet → 山 counts as missing words
    assert coverage_report(conn)["kanji_without_words"] == 1


def test_assert_core_gates_does_not_fail_on_missing_words():
    conn = init_db(":memory:")
    load_kanji(conn, [_good()])
    load_stroke_order(conn, {0x5C71: ["d1"]})
    # gate passes even though 山 has no words (vocabulary is supplementary)
    assert assert_core_gates(conn)["kanji_without_words"] == 1
