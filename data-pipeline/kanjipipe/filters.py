# kanjipipe/filters.py
from kanjipipe.models import Kanji

JOYO_GRADES = frozenset({1, 2, 3, 4, 5, 6, 8})  # 1-6 = 小, 8 = 中学/常用


def filter_joyo(kanji: list[Kanji]) -> list[Kanji]:
    return [k for k in kanji if k.grade in JOYO_GRADES]
