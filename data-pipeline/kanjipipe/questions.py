"""Mechanical question generation for the 準1級/1級 exam bank.

準1級 and 1級 cover 3,800 kanji that no one has authored questions for, and
they are obscure enough that writing them by hand — or having a model invent
them — is where wrong answers come from. So every question here is derived from
vocabulary that actually exists in JMdict, and the generator returns None rather
than emit anything it cannot prove has exactly one correct answer.

Two kinds are produced:

* ``reading`` (漢検 大問1 読み) — show the word, pick its reading. A distractor
  is safe when it is not itself a reading of that word.
* ``orthography`` (大問2 書き取り) — blank the target kanji, pick it from four.
  A distractor is safe when substituting it does not spell another real word.
"""
from __future__ import annotations

import random
from dataclasses import dataclass

_OPTION_COUNT = 4
# 漢検 熟語 run two to four characters; longer JMdict surfaces are names.
_MAX_COMPOUND = 4

# Classic 漢検 traps: a dropped/added dakuten, a lost long vowel, a missing
# gemination. Each maps a kana to the one a careless reader confuses it with.
_DAKUTEN = str.maketrans({
    "か": "が", "き": "ぎ", "く": "ぐ", "け": "げ", "こ": "ご",
    "さ": "ざ", "し": "じ", "す": "ず", "せ": "ぜ", "そ": "ぞ",
    "た": "だ", "ち": "ぢ", "つ": "づ", "て": "で", "と": "ど",
    "は": "ば", "ひ": "び", "ふ": "ぶ", "へ": "べ", "ほ": "ぼ",
})
_UNDAKUTEN = str.maketrans({v: k for k, v in [
    ("か", "が"), ("き", "ぎ"), ("く", "ぐ"), ("け", "げ"), ("こ", "ご"),
    ("さ", "ざ"), ("し", "じ"), ("す", "ず"), ("せ", "ぜ"), ("そ", "ぞ"),
    ("た", "だ"), ("ち", "ぢ"), ("つ", "づ"), ("て", "で"), ("と", "ど"),
    ("は", "ば"), ("ひ", "び"), ("ふ", "ぶ"), ("へ", "べ"), ("ほ", "ぼ"),
]})


@dataclass(frozen=True)
class WordRow:
    """A vocabulary row as the generator needs it."""
    surface: str
    reading: str
    en: str | None = None
    ko: str | None = None


def _is_kana(text: str) -> bool:
    return bool(text) and all("ぁ" <= ch <= "ゟ" for ch in text)


def perturb_reading(reading: str) -> list[str]:
    """Near-miss readings a careless learner would accept.

    Only kana come back, and never the input itself — a "distractor" equal to
    the answer would make the question unanswerable.
    """
    out: list[str] = []
    for candidate in (
        reading.translate(_DAKUTEN),        # 濁点をつけてしまう
        reading.translate(_UNDAKUTEN),      # 濁点を落とす
        reading.replace("っ", "") if "っ" in reading else reading + "っ",
        reading.replace("ゅ", "") if "ゅ" in reading else reading,
        reading.replace("う", "") if reading.endswith("う") else reading + "う",
    ):
        if candidate != reading and _is_kana(candidate) and candidate not in out:
            out.append(candidate)
    return out


def _pick_distractors(
    pool: list[str], banned: set[str], rng: random.Random, count: int
) -> list[str] | None:
    chosen: list[str] = []
    for candidate in pool:
        if candidate in banned or candidate in chosen:
            continue
        chosen.append(candidate)
        if len(chosen) == count:
            return chosen
    return None


def _explanations(
    surface: str, reading: str, literal: str, word: WordRow, kind: str
) -> dict[str, str]:
    meaning_en = f" ({word.en})" if word.en else ""
    meaning_ko = f"({word.ko})" if word.ko else ""
    if kind == "reading":
        return {
            "ko": f"「{surface}」는 {reading}로 읽습니다{meaning_ko}. "
                  f"{literal}이(가) 쓰인 낱말입니다.",
            "ja": f"「{surface}」は {reading} と読みます。{literal} を用いた語です。",
            "en": f"「{surface}」is read {reading}{meaning_en}. "
                  f"It is written with {literal}.",
        }
    return {
        "ko": f"{reading}는 「{surface}」로 씁니다{meaning_ko}. "
              f"빈칸에 들어갈 한자는 {literal}입니다.",
        "ja": f"{reading} は「{surface}」と書きます。空欄に入る漢字は {literal} です。",
        "en": f"{reading} is written 「{surface}」{meaning_en}. "
              f"The kanji for the blank is {literal}.",
    }


def build_reading_question(
    word: WordRow,
    *,
    literal: str,
    level: str,
    other_readings: list[str],
    forbidden: set[str],
    rng: random.Random,
) -> dict | None:
    """読み: show the word, pick its reading.

    ``forbidden`` holds every reading that surface is known to take, so a
    homograph's other reading is never offered as a wrong answer.
    """
    if not _is_kana(word.reading):
        return None
    if not 2 <= len(word.surface) <= _MAX_COMPOUND:
        # 漢検 大問1 asks for the reading of a 熟語, or of a kanji with its
        # okurigana. A bare kanji collapses to a one-mora guess; past four
        # characters JMdict is mostly proper nouns and set phrases (皇學館大学,
        # 単于都護府), which the paper never asks about.
        return None
    banned = forbidden | {word.reading}
    # Readings of neighbouring vocabulary are far more convincing than a
    # perturbation, so they carry the question. A perturbation is allowed to
    # fill at most one slot: three of them together read as obvious noise and
    # give the answer away.
    pool = [r for r in other_readings if _is_kana(r)]
    rng.shuffle(pool)
    distractors = _pick_distractors(pool, banned, rng, _OPTION_COUNT - 1) or []
    if len(distractors) < _OPTION_COUNT - 1:
        distractors = (_pick_distractors(pool, banned, rng, _OPTION_COUNT - 2)
                       or [])
        near_miss = _pick_distractors(perturb_reading(word.reading),
                                      banned | set(distractors), rng, 1)
        if len(distractors) < _OPTION_COUNT - 2 or near_miss is None:
            return None
        distractors = distractors + near_miss

    options = distractors + [word.reading]
    rng.shuffle(options)
    return {
        "literal": literal,
        "level": level,
        "kind": "reading",
        "prompt": f"<u>{word.surface}</u>",
        "options": options,
        "answer": options.index(word.reading),
        "focus": word.surface,
        "explanations": _explanations(word.surface, word.reading, literal,
                                      word, "reading"),
    }


def build_orthography_question(
    word: WordRow,
    *,
    literal: str,
    level: str,
    candidates: list[str],
    real_surfaces: set[str],
    rng: random.Random,
) -> dict | None:
    """書き取り: blank the target kanji, pick it from four.

    The surrounding characters are what pin the answer, so single-character
    words are skipped, and a candidate is rejected when substituting it spells
    another word that exists — that would be a second defensible answer.
    """
    if not 2 <= len(word.surface) <= _MAX_COMPOUND:
        return None
    if literal not in word.surface:
        return None
    if word.surface.count(literal) > 1:
        # 侃侃諤諤 and friends: blank one and the other still spells the answer.
        return None
    index = word.surface.index(literal)
    blanked = word.surface[:index] + "□" + word.surface[index + 1:]

    safe = []
    for candidate in candidates:
        if candidate == literal:
            continue
        substituted = word.surface[:index] + candidate + word.surface[index + 1:]
        if substituted in real_surfaces:
            continue
        safe.append(candidate)
    rng.shuffle(safe)
    distractors = _pick_distractors(safe, set(), rng, _OPTION_COUNT - 1)
    if distractors is None:
        return None

    options = distractors + [literal]
    rng.shuffle(options)
    return {
        "literal": literal,
        "level": level,
        "kind": "orthography",
        "prompt": f"{word.reading}　—　<u>{blanked}</u>",
        "options": options,
        "answer": options.index(literal),
        "focus": blanked,
        "explanations": _explanations(word.surface, word.reading, literal,
                                      word, "orthography"),
    }
