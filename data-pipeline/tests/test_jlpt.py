# tests/test_jlpt.py
from pathlib import Path

from kanjipipe.ingest.jlpt import merge_jlpt
from kanjipipe.models import Kanji

FIXTURE = Path(__file__).parent / "fixtures" / "jlpt_sample.json"


def _kanji(literal):
    return Kanji(literal=literal, codepoint=0, stroke_count=1,
                 grade=1, freq_rank=None, radical=None)


def test_sets_jlpt_level_from_mapping():
    kanji = [_kanji("山"), _kanji("学")]
    merge_jlpt(kanji, FIXTURE)
    assert {k.literal: k.jlpt_level for k in kanji} == {"山": "N5", "学": "N5"}


def test_unmapped_kanji_stays_none():
    kanji = [_kanji("情")]  # not in the fixture
    merge_jlpt(kanji, FIXTURE)
    assert kanji[0].jlpt_level is None
