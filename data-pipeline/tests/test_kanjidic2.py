import pytest
from pathlib import Path

from kanjipipe.ingest.kanjidic2 import parse_kanjidic2

FIXTURE = Path(__file__).parent / "fixtures" / "kanjidic2_sample.xml"


def test_parses_all_characters():
    kanji = parse_kanjidic2(FIXTURE)
    assert [k.literal for k in kanji] == ["山", "学", "龠"]


def test_extracts_core_fields():
    yama = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "山")
    assert yama.codepoint == 0x5C71
    assert yama.stroke_count == 3
    assert yama.grade == 1
    assert yama.freq_rank == 360
    assert yama.radical == 46


def test_maps_reading_axes():
    yama = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "山")
    pairs = {(r.lang_axis, r.value) for r in yama.readings}
    assert ("on", "サン") in pairs
    assert ("kun", "やま") in pairs
    assert ("pinyin", "shan1") in pairs
    assert ("eum", "산") in pairs
    # korean_r (romanized) and nanori are ignored
    assert all(r.lang_axis != "korean_r" for r in yama.readings)
    # nanori (outside rmgroup) must not become a reading
    assert all(r.value != "やの" for r in yama.readings)


def test_extracts_only_english_meanings_as_glosses():
    gaku = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "学")
    en = [g.text for g in gaku.glosses if g.lang == "en"]
    assert en == ["study", "learning"]
    yama = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "山")
    # French meaning must NOT become a gloss in this pipeline
    assert all(g.text != "montagne" for g in yama.glosses)


def test_missing_freq_becomes_none():
    flute = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "龠")
    assert flute.grade == 9
    assert flute.freq_rank is None


def _write(tmp_path, body):
    p = tmp_path / "k.xml"
    p.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<kanjidic2>\n' + body + '\n</kanjidic2>',
        encoding="utf-8")
    return p


def test_raises_when_misc_missing(tmp_path):
    xml = _write(tmp_path, '<character><literal>X</literal>'
                 '<codepoint><cp_value cp_type="ucs">5c71</cp_value></codepoint></character>')
    with pytest.raises(ValueError, match="misc"):
        parse_kanjidic2(xml)


def test_raises_when_stroke_count_missing(tmp_path):
    xml = _write(tmp_path, '<character><literal>X</literal>'
                 '<codepoint><cp_value cp_type="ucs">5c71</cp_value></codepoint>'
                 '<misc><grade>1</grade></misc></character>')
    with pytest.raises(ValueError, match="stroke_count"):
        parse_kanjidic2(xml)


def test_skips_readings_and_meanings_without_text(tmp_path):
    xml = _write(tmp_path, '<character><literal>X</literal>'
                 '<codepoint><cp_value cp_type="ucs">5c71</cp_value></codepoint>'
                 '<misc><grade>1</grade><stroke_count>3</stroke_count></misc>'
                 '<reading_meaning><rmgroup>'
                 '<reading r_type="ja_on"/>'
                 '<reading r_type="ja_kun">やま</reading>'
                 '<meaning/>'
                 '<meaning>mountain</meaning>'
                 '</rmgroup></reading_meaning></character>')
    k = parse_kanjidic2(xml)[0]
    assert [(r.lang_axis, r.value) for r in k.readings] == [("kun", "やま")]
    assert [g.text for g in k.glosses] == ["mountain"]
