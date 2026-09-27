"""Per-kanji alignment of a word's reading, used by the 同音異字 generator."""
from kanjipipe.furigana import slice_at, segmentations

READINGS = {
    "開": ({"カイ"}, {"ひら.く", "あ.ける"}),
    "眼": ({"ガン", "ゲン"}, {"まなこ", "め"}),
    "学": ({"ガク"}, {"まな.ぶ"}),
    "校": ({"コウ", "キョウ"}, set()),
    "公": ({"コウ", "ク"}, {"おおやけ"}),
    "家": ({"カ", "ケ"}, {"いえ", "や"}),
    "収": ({"シュウ"}, {"おさ.める"}),
    "蔵": ({"ゾウ"}, {"くら"}),
    "悪": ({"アク", "オ"}, {"わる.い"}),
    "戯": ({"ギ", "ゲ"}, {"たわむ.れる"}),
}


def test_the_blank_gets_the_reading_the_word_uses():
    forms = slice_at("開眼", "かいがん", 1, READINGS)
    assert forms and {f.slice for f in forms} == {"がん"}
    assert {f.base for f in forms} == {"がん"}


def test_sokuon_and_rendaku_are_aligned():
    forms = slice_at("学校", "がっこう", 0, READINGS)
    assert forms and forms[0].slice == "がっ" and forms[0].change == "sokuon"
    forms = slice_at("公家", "くげ", 1, READINGS)
    assert forms and forms[0].slice == "げ"


def test_voicing_is_kept_in_the_slice():
    forms = slice_at("収蔵", "しゅうぞう", 1, READINGS)
    assert forms and forms[0].slice == "ぞう"


def test_jukujikun_does_not_align():
    assert segmentations("悪戯", "いたずら", READINGS) == []
    assert slice_at("悪戯", "いたずら", 1, READINGS) is None
