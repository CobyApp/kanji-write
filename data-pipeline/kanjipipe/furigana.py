"""Align a word's kana reading to its kanji, one slice per character.

The word table stores a reading for the whole surface (開眼 → かいがん) but not
which part belongs to which kanji. Questions that contrast one kanji's reading
(同音異字) need exactly that: 眼 is read がん here, not げん, so only がん
homophones are fair distractors.

The aligner tries every way of cutting the reading into one slice per kanji,
where each slice is a dictionary reading of that kanji in one of the surface
forms it takes inside a compound:

* as listed (カイ → かい);
* 連濁 — voiced first mora when not word-initial (ケ → げ in 公家, ホン → ぽん);
* 促音便 — final つ/ち/く/き → っ when not word-final (ガク → がっ in 学校).

Kana in the surface must match themselves. An alignment is only trusted when
every segmentation agrees on the slice in question; anything else is ambiguous
and the caller should skip the word rather than guess.
"""
from __future__ import annotations

from dataclasses import dataclass

_VOICE = dict(zip("かきくけこさしすせそたちつてとはひふへほ",
                  "がぎぐげござじずぜぞだぢづでどばびぶべぼ"))
_SEMI = dict(zip("はひふへほ", "ぱぴぷぺぽ"))
_SOKUON_FINAL = set("つちくき")
# 五段 dictionary ending → 連用形 ending, for kun readings used as a noun stem
# inside a compound (取り → 取, 受付 うけつけ).
_RENYOU = dict(zip("うくぐすつぬぶむる", "いきぎしちにびみり"))


def to_hiragana(text: str) -> str:
    return "".join(
        chr(ord(ch) - 0x60) if "ァ" <= ch <= "ヶ" else ch for ch in text)


def is_kanji(ch: str) -> bool:
    return "一" <= ch <= "鿿" or "㐀" <= ch <= "䶿" or ch in "々〆"


@dataclass(frozen=True)
class Form:
    """One way a kanji can surface in a compound."""
    slice: str      # the kana as it appears in the word
    base: str       # the dictionary reading it came from (hiragana)
    axis: str       # "on" | "kun"
    change: str     # "" | "rendaku" | "sokuon"


def kun_stems(value: str) -> set[str]:
    """Surface stems a KANJIDIC kun entry (``う.ける``, ``-づ.く``) can take."""
    value = value.strip("-")
    if "." not in value:
        return {value} if value else set()
    stem, okuri = value.split(".", 1)
    out = {stem, stem + okuri}
    if okuri and okuri[-1] in _RENYOU:
        out.add(stem + okuri[:-1] + _RENYOU[okuri[-1]])
    if okuri.endswith("る") and len(okuri) >= 2:
        out.add(stem + okuri[:-1])        # 一段: う.ける → うけ
    return {s for s in out if s}


def forms_for(on: set[str], kun: set[str], *, initial: bool, final: bool) -> list[Form]:
    """Every surface form a kanji can take at one position of a word."""
    raw: list[tuple[str, str]] = [(to_hiragana(r), "on") for r in on]
    for value in kun:
        raw.extend((stem, "kun") for stem in kun_stems(value))
    out: dict[tuple[str, str, str], Form] = {}

    def add(slice_: str, base: str, axis: str, change: str) -> None:
        out.setdefault((slice_, base, axis), Form(slice_, base, axis, change))

    for base, axis in raw:
        if not base:
            continue
        variants = [(base, "")]
        if not initial and base[0] in _VOICE:
            variants.append((_VOICE[base[0]] + base[1:], "rendaku"))
            if base[0] in _SEMI:
                variants.append((_SEMI[base[0]] + base[1:], "rendaku"))
        for text, change in variants:
            add(text, base, axis, change)
            if not final and len(text) >= 2 and text[-1] in _SOKUON_FINAL:
                add(text[:-1] + "っ", base, axis, change or "sokuon")
    return list(out.values())


def segmentations(surface: str, reading: str,
                  readings_of: dict[str, tuple[set[str], set[str]]],
                  limit: int = 64) -> list[list[Form]]:
    """All ways to cut ``reading`` into one Form per character of ``surface``.

    ``readings_of[kanji]`` is ``(on_readings, kun_readings)``. Kana characters
    in the surface must match themselves. At most ``limit`` segmentations are
    returned — a word with more than that is hopelessly ambiguous anyway.
    """
    reading = to_hiragana(reading)
    n = len(surface)
    per_position: list[list[Form]] = []
    for i, ch in enumerate(surface):
        if is_kanji(ch):
            if ch == "々" and i > 0:
                prev = readings_of.get(surface[i - 1], (set(), set()))
                on, kun = prev
            else:
                on, kun = readings_of.get(ch, (set(), set()))
            per_position.append(forms_for(on, kun, initial=i == 0, final=i == n - 1))
        else:
            kana = to_hiragana(ch)
            per_position.append([Form(kana, kana, "kana", "")])

    results: list[list[Form]] = []

    def walk(i: int, pos: int, acc: list[Form]) -> None:
        if len(results) >= limit:
            return
        if i == n:
            if pos == len(reading):
                results.append(list(acc))
            return
        for form in per_position[i]:
            if reading.startswith(form.slice, pos):
                acc.append(form)
                walk(i + 1, pos + len(form.slice), acc)
                acc.pop()

    walk(0, 0, [])
    return results


def slice_at(surface: str, reading: str, index: int,
             readings_of: dict[str, tuple[set[str], set[str]]]) -> list[Form] | None:
    """The Forms character ``index`` takes in this word, or None if unsure.

    Returns every Form the segmentations assign to that position, all sharing
    one slice (e.g. がっ from both ガク and ガツ). None when the word cannot be
    aligned or the segmentations disagree on the slice.
    """
    segs = segmentations(surface, reading, readings_of)
    if not segs:
        return None
    forms = {seg[index] for seg in segs}
    if len({f.slice for f in forms}) != 1:
        return None
    return sorted(forms, key=lambda f: (f.axis, f.base, f.change))
