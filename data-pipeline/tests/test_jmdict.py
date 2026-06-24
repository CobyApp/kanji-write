# tests/test_jmdict.py
from pathlib import Path

from kanjipipe.ingest.jmdict import parse_jmdict

FIXTURE = Path(__file__).parent / "fixtures" / "jmdict_sample.xml"


def test_keeps_only_common_entries_with_kanji():
    words = parse_jmdict(FIXTURE)
    assert [w.surface for w in words] == ["山", "学校"]  # 山岳 (no pri) + これ (no keb) dropped


def test_extracts_reading_and_english_glosses():
    yama = next(w for w in parse_jmdict(FIXTURE) if w.surface == "山")
    assert yama.reading_kana == "やま"
    assert yama.en_glosses == ["mountain", "hill"]


def test_gloss_count_capped_at_three(tmp_path):
    p = tmp_path / "j.xml"
    p.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<JMdict><entry>'
        '<k_ele><keb>例</keb><ke_pri>news1</ke_pri></k_ele>'
        '<r_ele><reb>れい</reb></r_ele>'
        '<sense><gloss>a</gloss><gloss>b</gloss><gloss>c</gloss><gloss>d</gloss></sense>'
        '</entry></JMdict>',
        encoding="utf-8")
    assert parse_jmdict(p)[0].en_glosses == ["a", "b", "c"]


def test_resolves_internal_dtd_entities(tmp_path):
    p = tmp_path / "j.xml"
    p.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE JMdict [ <!ENTITY n "noun"> ]>\n'
        '<JMdict><entry>'
        '<k_ele><keb>名詞</keb><ke_pri>news1</ke_pri></k_ele>'
        '<r_ele><reb>めいし</reb></r_ele>'
        '<sense><pos>&n;</pos><gloss>noun</gloss></sense>'
        '</entry></JMdict>',
        encoding="utf-8")
    words = parse_jmdict(p)
    assert [w.surface for w in words] == ["名詞"]
    assert words[0].en_glosses == ["noun"]
