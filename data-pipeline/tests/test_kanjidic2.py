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


def test_extracts_only_english_meanings_as_glosses():
    gaku = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "学")
    en = [g.text for g in gaku.glosses if g.lang == "en"]
    assert en == ["study", "learning"]
    yama = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "山")
    # French meaning must NOT become a gloss in this pipeline
    assert all(g.text != "montagne" for g in yama.glosses)


def test_missing_grade_and_freq_become_none():
    flute = next(k for k in parse_kanjidic2(FIXTURE) if k.literal == "龠")
    assert flute.grade == 9
    assert flute.freq_rank is None
