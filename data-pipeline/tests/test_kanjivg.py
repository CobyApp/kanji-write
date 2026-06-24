# tests/test_kanjivg.py
from pathlib import Path

from kanjipipe.ingest.kanjivg import parse_kanjivg

FIXTURE = Path(__file__).parent / "fixtures" / "kanjivg_sample.xml"


def test_maps_codepoints_to_ordered_strokes():
    strokes = parse_kanjivg(FIXTURE)
    assert set(strokes) == {0x5C71, 0x5B66}
    assert len(strokes[0x5C71]) == 3
    assert len(strokes[0x5B66]) == 8


def test_preserves_document_order_as_stroke_order():
    strokes = parse_kanjivg(FIXTURE)
    assert strokes[0x5C71] == ["M21,30 L21,70", "M50,20 L50,80", "M79,30 L79,70"]


def test_kanji_without_paths_yields_empty_list(tmp_path):
    p = tmp_path / "k.xml"
    p.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<kanjivg><kanji id="kvg:kanji_05c71"><g></g></kanji></kanjivg>',
        encoding="utf-8")
    assert parse_kanjivg(p) == {0x5C71: []}
