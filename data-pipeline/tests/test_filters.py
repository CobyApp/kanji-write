# tests/test_filters.py
from pathlib import Path

from kanjipipe.filters import apply_korean_readings, filter_joyo
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2
from kanjipipe.ingest.unihan import UnihanMetadata
from kanjipipe.models import Kanji, Reading

FIXTURE = Path(__file__).parent / "fixtures" / "kanjidic2_sample.xml"


def test_keeps_grade_1_to_6_and_8_drops_others():
    kept = filter_joyo(parse_kanjidic2(FIXTURE))
    literals = {k.literal for k in kept}
    assert literals == {"山", "学"}      # grade 1 kept
    assert "龠" not in literals          # grade 9 (名用) dropped


def test_korean_readings_prefer_unihan_over_kanjidic2():
    """kanjidic2's first korean_h is frequently not the primary reading.

    阿 came out 옥 and 丑 came out 추; the right answers are 아 and 축. Unihan's
    kHangul is ordered, so it wins wherever it has an entry, and kanjidic2 is
    kept only where Unihan says nothing.
    """
    a = Kanji(literal="阿", codepoint=ord("阿"), stroke_count=8, grade=None,
              freq_rank=None, radical=None,
              readings=[Reading("on", "ア"), Reading("eum", "옥")])
    b = Kanji(literal="丑", codepoint=ord("丑"), stroke_count=4, grade=None,
              freq_rank=None, radical=None, readings=[Reading("eum", "추")])
    # No Unihan entry: keep what kanjidic2 said rather than dropping it.
    c = Kanji(literal="々", codepoint=ord("々"), stroke_count=3, grade=None,
              freq_rank=None, radical=None, readings=[Reading("eum", "동")])

    apply_korean_readings([a, b, c], {
        "阿": _unihan("阿", korean_reading="아"),
        "丑": _unihan("丑", korean_reading="축"),
    })

    def eum(item):
        return [r.value for r in item.readings if r.lang_axis == "eum"]
    assert eum(a) == ["아"]
    assert eum(b) == ["축"]
    assert eum(c) == ["동"]
    # Japanese readings are untouched.
    assert [r.value for r in a.readings if r.lang_axis == "on"] == ["ア"]


def _unihan(literal: str, *, korean_reading: str) -> UnihanMetadata:
    return UnihanMetadata(literal=literal, stroke_count=None, radical=None,
                          on_readings=(), kun_readings=(), definition=None,
                          korean_reading=korean_reading)
