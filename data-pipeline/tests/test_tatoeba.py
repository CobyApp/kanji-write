# tests/test_tatoeba.py
from pathlib import Path

from kanjipipe.ingest.tatoeba import parse_tatoeba

FIX = Path(__file__).parent / "fixtures"


def _parse():
    return parse_tatoeba(FIX / "sentences_sample.csv", FIX / "links_sample.csv")


def test_collects_japanese_sentences_with_translations():
    sentences = _parse()
    by_text = {s.ja_text: s.translations for s in sentences}
    assert by_text["山が高い。"] == {
        "en": "The mountain is high.",
        "ko": "산이 높다.",
        "zh": "这是山。",
    }


def test_sentence_with_only_english_keeps_english_only():
    sentences = _parse()
    gakkou = next(s for s in sentences if s.ja_text == "学校に行く。")
    assert gakkou.translations == {"en": "I go to school."}


def test_non_japanese_sentences_are_not_returned_as_entries():
    # The French sentence (id 7) is never a returned Sentence; only jpn entries are.
    sentences = _parse()
    assert all("montagne" not in s.ja_text.lower() for s in sentences)
    assert len(sentences) == 2


def test_parse_tatoeba_drops_sentences_unfit_for_a_study_app(tmp_path):
    """A Tatoeba sentence stating a first-person desire to commit rape was being
    shown beside 強 and 姦 like any other example."""
    sentences = tmp_path / "sentences.csv"
    sentences.write_text(
        "1\tjpn\t私はたまに強姦したくなる。\n"
        "2\teng\tI sometimes feel like it.\n"
        "3\tjpn\t山に登る。\n"
        "4\teng\tI climb the mountain.\n",
        encoding="utf-8")
    links = tmp_path / "links.csv"
    links.write_text("1\t2\n3\t4\n", encoding="utf-8")

    parsed = parse_tatoeba(sentences, links)

    assert [s.ja_text for s in parsed] == ["山に登る。"]
