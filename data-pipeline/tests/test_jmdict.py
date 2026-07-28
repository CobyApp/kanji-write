# tests/test_jmdict.py
from pathlib import Path

from kanjipipe.ingest.jmdict import parse_jmdict

FIXTURE = Path(__file__).parent / "fixtures" / "jmdict_sample.xml"


def test_keeps_only_common_entries_with_kanji():
    words = parse_jmdict(FIXTURE)
    assert [w.surface for w in words] == ["山", "学校"]  # 山岳 (no pri) + これ (no keb) dropped


def test_keeps_uncommon_entry_when_it_carries_a_requested_kanji():
    # 準1級/1級 kanji barely appear in common vocabulary, so the exam sections
    # would have no material without widening the filter for those kanji only.
    words = parse_jmdict(FIXTURE, extra_literals={"岳"})
    assert [w.surface for w in words] == ["山", "学校", "山岳"]


def test_uncommon_entry_is_flagged_not_common():
    words = parse_jmdict(FIXTURE, extra_literals={"岳"})
    by_surface = {w.surface: w for w in words}
    assert by_surface["山岳"].is_common is False
    assert by_surface["山"].is_common is True


def test_extra_literals_do_not_pull_in_unrelated_uncommon_entries():
    # 山岳 carries neither 校 nor 学 as a *requested* kanji, so it stays out.
    assert [w.surface for w in parse_jmdict(FIXTURE, extra_literals={"校"})] == ["山", "学校"]
    # …and with no request at all the filter is common-only, as before.
    assert [w.surface for w in parse_jmdict(FIXTURE)] == ["山", "学校"]


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
