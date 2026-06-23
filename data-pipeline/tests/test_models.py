from kanjipipe.models import Kanji, Reading, Gloss


def test_kanji_defaults_to_empty_readings_and_glosses():
    k = Kanji(literal="山", codepoint=0x5C71, stroke_count=3,
              grade=1, freq_rank=360, radical=46)
    assert k.readings == []
    assert k.glosses == []
    assert k.jlpt_level is None


def test_reading_and_gloss_hold_values():
    r = Reading(lang_axis="on", value="サン")
    g = Gloss(lang="en", text="mountain")
    assert r.is_common is True
    assert (g.lang, g.text) == ("en", "mountain")
