"""Near-miss trap distractors for the 一字訓読み (rare advanced kanji) bank.

These reading questions build their own options (not via reading_distractors),
so they get their own confusable-near-miss pass. A trap must never be a real
reading of the answer kanji, which would make a second right answer.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from generate_rare_kun_questions import near_miss_traps


def test_traps_include_long_short_vowel_misses():
    traps = near_miss_traps("こう", forbidden=set())
    assert "こ" in traps            # dropped long vowel
    assert "こう" not in traps       # never the answer itself


def test_traps_exclude_real_readings_of_the_kanji():
    # If the kanji legitimately also reads こ, then こ cannot be a trap —
    # it would be a second correct answer.
    assert "こ" not in near_miss_traps("こう", forbidden={"こ"})


def test_traps_exclude_the_katakana_form_of_a_real_reading():
    assert "こ" not in near_miss_traps("こう", forbidden={"コ"})


def test_traps_are_always_kana():
    for reading in ("けい", "ほう", "しょう"):
        for t in near_miss_traps(reading, forbidden=set()):
            assert all("ぁ" <= ch <= "ゟ" for ch in t), (reading, t)
