# tests/test_filters.py
from pathlib import Path

from kanjipipe.filters import filter_joyo
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2

FIXTURE = Path(__file__).parent / "fixtures" / "kanjidic2_sample.xml"


def test_keeps_grade_1_to_6_and_8_drops_others():
    kept = filter_joyo(parse_kanjidic2(FIXTURE))
    literals = {k.literal for k in kept}
    assert literals == {"山", "学"}      # grade 1 kept
    assert "龠" not in literals          # grade 9 (名用) dropped
