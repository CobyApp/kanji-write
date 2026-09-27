"""The sentence rules that keep contextualized questions answerable."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from contextualize_questions import (  # noqa: E402
    IMPOSSIBLE, leaks_answer, repeats_okurigana, sentence_with)
from check_context_sentences import problems  # noqa: E402


def test_okurigana_already_in_the_reading_is_caught():
    # 揭 read かかげる written 揭げる: the underlined kanji is only かか
    assert repeats_okurigana("旗を揭げる。", "揭", "かかげる")
    # 竢 read まつ written 竢つ
    assert repeats_okurigana("時機を竢つことにした。", "竢", "まつ")
    # 虛 read むなしい conjugated 虛しく
    assert repeats_okurigana("努力も虛しく終わった。", "虛", "むなしい")


def test_a_particle_after_a_noun_is_not_okurigana():
    assert not repeats_okurigana("國に帰る。", "國", "くに")
    assert not repeats_okurigana("北の海で鯡がとれる。", "鯡", "にしん")
    assert not repeats_okurigana("駅前で旧友と會う約束をした。", "會う", "あう")


def test_the_answer_elsewhere_in_the_sentence_is_a_leak():
    assert leaks_answer("隊長が楽隊を率いた。", "楽隊", "隊")
    assert not leaks_answer("パレードの先頭を楽隊が進んだ。", "楽隊", "隊")


def test_sentence_with_replaces_the_word_once():
    assert sentence_with("若手を擢用する。", "擢用", "<u>テキ</u>用") == "若手を<u>テキ</u>用する。"


def test_impossible_sokuon_is_detected():
    for bad in ("いっもち", "べっや", "しっりょ", "かいさっ"):
        assert IMPOSSIBLE.search(bad)
    for good in ("いっしゃく", "べっそう", "がっこう"):
        assert not IMPOSSIBLE.search(good)


def test_checker_rejects_a_compound_swallowing_the_word():
    row = {"word": "用意", "reading": "ようい", "level": "準1級",
           "sentence": "何事も用意周到に進める。",
           "translations": {"ko": "무슨 일이든 용의주도하게 진행한다.", "zh": "凡事周密准备。",
                            "en": "Everything is done with care."}}
    assert any("touches" in p for p in problems(row, {}))


def test_checker_holds_lower_levels_to_their_kanji():
    row = {"word": "楽隊", "reading": "がくたい", "level": "7級",
           "sentence": "楽隊が華麗な演奏を披露した。",
           "translations": {"ko": "악대가 화려한 연주를 선보였다.", "zh": "乐队进行了华丽的演奏。",
                            "en": "The band gave a splendid performance."}}
    ranks = {"楽": 0, "隊": 3, "演": 4, "奏": 5}
    assert any("above the level" in p for p in problems(row, ranks))
