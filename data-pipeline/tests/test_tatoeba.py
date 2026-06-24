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
