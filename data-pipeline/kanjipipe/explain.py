"""Exam-style explanations in four languages, built from the dictionary.

A good 解説 answers three things: what the word is (reading and meaning), why
the answer fits *this* sentence, and why each other option does not. The
generated banks used to stop at the first; this module writes all three from
data the database already has:

* the word's reading and meaning (``word_gloss``), and — for 読み — which part
  of the reading belongs to which kanji;
* the sentence's translation, so the learner sees the context that decides;
* for every wrong option, what it actually is: a kanji with its Korean 훈음
  (耀 → 빛날 요) or meaning and a word it is used in, or the word a wrong
  reading belongs to (じゅうせい → 銃声).

Nothing is invented: a note is left out when the data has nothing to say.
Korean never puts a particle straight after Japanese text (its form depends on
how the word is read), so the templates are written around that.
"""
from __future__ import annotations

import re
import sqlite3
from collections import defaultdict
from dataclasses import dataclass, field

LANGS = ("ko", "ja", "zh", "en")

OTHER = {"ko": "다른 보기", "ja": "ほかの選択肢", "zh": "其他选项", "en": "Other options"}
SAME_SOUND = {"ko": "음은 같지만 다른 한자", "ja": "同じ音の別の漢字",
              "zh": "同音但不同的汉字", "en": "Same sound, different kanji"}
LOOKALIKE = {"ko": "모양이 비슷한 한자", "ja": "形の似た漢字",
             "zh": "字形相近的汉字", "en": "Look-alike kanji"}
SENTENCE = {"ko": "문장", "ja": "文意", "zh": "句意", "en": "Sentence"}
MEANING = {"ko": "뜻", "ja": "意味", "zh": "意思", "en": "Meaning"}
ANSWER = {"ko": "정답", "ja": "正解", "zh": "正确答案", "en": "Answer"}


def is_kanji(ch: str) -> bool:
    return "一" <= ch <= "鿿" or "㐀" <= ch <= "䶿" or "豈" <= ch <= "﫿"


def _short(text: str, limit: int) -> str:
    """First sense of a gloss, trimmed: 'まばゆく光りかがやく。その光。' → 'まばゆく光りかがやく'."""
    text = re.sub(r"[（(][^）)]*[）)]", "", text or "").strip()
    text = re.split(r"[。；;]|、(?=.{12,})", text)[0].strip() if text else ""
    text = text.split(",")[0].strip() if len(text) > limit else text
    return text[:limit].rstrip("、，, ")


def to_katakana(text: str) -> str:
    return "".join(chr(ord(c) + 0x60) if "ぁ" <= c <= "ゖ" else c for c in text)


@dataclass
class Dictionary:
    """Everything the explanations draw on, loaded once from the database."""
    kanji_gloss: dict[str, dict[str, str]] = field(default_factory=dict)
    on: dict[str, list[str]] = field(default_factory=lambda: defaultdict(list))
    kun: dict[str, list[str]] = field(default_factory=lambda: defaultdict(list))
    word_gloss: dict[tuple[str, str], dict[str, str]] = field(default_factory=dict)
    words_by_reading: dict[str, list[str]] = field(default_factory=lambda: defaultdict(list))
    examples: dict[str, list[tuple[str, str]]] = field(default_factory=lambda: defaultdict(list))

    @classmethod
    def load(cls, db: str) -> "Dictionary":
        d = cls()
        con = sqlite3.connect(db)
        for literal, lang, text in con.execute(
                "SELECT k.literal, g.lang, g.text FROM gloss g JOIN kanji k ON k.id = g.kanji_id "
                "ORDER BY g.id"):
            d.kanji_gloss.setdefault(literal, {}).setdefault(lang, text)
        for literal, axis, value in con.execute(
                "SELECT k.literal, r.lang_axis, r.value FROM reading r JOIN kanji k ON k.id = r.kanji_id "
                "WHERE r.lang_axis IN ('on','kun') ORDER BY r.id"):
            (d.on if axis == "on" else d.kun)[literal].append(value)
        # Most familiar first: JLPT N5 words, then N4 …, then other common words.
        rows = con.execute(
            "SELECT w.surface, w.reading_kana, w.is_common, g.lang, g.text FROM word w "
            "JOIN word_gloss g ON g.word_id = w.id "
            "ORDER BY COALESCE(CASE w.jlpt_level WHEN 'N5' THEN 0 WHEN 'N4' THEN 1 "
            "WHEN 'N3' THEN 2 WHEN 'N2' THEN 3 WHEN 'N1' THEN 4 END, 9), "
            "w.is_common DESC, LENGTH(w.surface), w.id, g.id")
        for surface, reading, common, lang, text in rows:
            d.word_gloss.setdefault((surface, reading), {}).setdefault(lang, text)
            if surface not in d.words_by_reading[reading]:
                d.words_by_reading[reading].append(surface)
            # short, familiar words that show a kanji in use (耀 → 栄耀)
            if common and len(surface) == 2 and all(is_kanji(c) for c in surface):
                for ch in surface:
                    ex = d.examples[ch]
                    if len(ex) < 12 and (surface, reading) not in ex:
                        ex.append((surface, reading))
        con.close()
        return d

    # ── pieces ────────────────────────────────────────────────────────────
    def kanji_label(self, ch: str, lang: str, with_example: bool = True,
                    sound: str | None = None) -> str:
        """耀(빛날 요) / 耀（ヨウ・かがやく） / 耀（照耀） / 耀 (shine), plus a word."""
        g = self.kanji_gloss.get(ch, {})
        if lang == "ko":
            core = g.get("ko", "")
            head = f"{ch}({core})" if core else ch
        elif lang == "ja":
            readings = self.on.get(ch, [])[:1] or \
                [r.replace(".", "") for r in self.kun.get(ch, []) if "-" not in r][:1]
            if sound:
                # show the reading that makes it a homophone (兵 as ヒョウ, not ヘイ)
                kata = to_katakana(sound)
                match = [r for r in self.on.get(ch, []) if r == kata] or \
                    [r.replace(".", "") for r in self.kun.get(ch, [])
                     if r.split(".")[0] == sound or to_katakana(r.split(".")[0]) == kata]
                readings = match[:1] or readings
            head = f"{ch}（{readings[0]}）" if readings else ch
        elif lang == "zh":
            core = _short(g.get("zh", ""), 8)
            head = f"{ch}（{core}）" if core else ch
        else:
            core = _short(g.get("en", ""), 18)
            head = f"{ch} ({core})" if core else ch
        example = self.example(ch, sound) if with_example else None
        if example:
            head += f" [{example}]" if lang == "en" else f"〔{example}〕"
        return head

    def example(self, ch: str, sound: str | None = None) -> str | None:
        """A familiar word using ``ch`` — read with ``sound`` there, when given."""
        options = self.examples.get(ch, [])
        if sound:
            hira = "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in sound)
            for surface, reading in options:
                half = reading[:len(hira)] if surface[0] == ch else reading[-len(hira):]
                if half == hira:
                    return surface
            return None
        return options[0][0] if options else None

    def meaning(self, surface: str, reading: str, lang: str, fallback: str = "") -> str:
        g = self.word_gloss.get((surface, reading), {})
        text = g.get(lang) or ""
        limit = 40 if lang == "en" else 24
        short = _short(text, limit)
        if short == surface:        # a zh gloss that only repeats the word
            short = ""
        return short or fallback

    def word_for_reading(self, reading: str, avoid: str) -> str | None:
        """A dictionary word read ``reading`` (not ``avoid``) — what a wrong reading 'is'."""
        for surface in self.words_by_reading.get(reading, []):
            if surface != avoid and any(is_kanji(c) for c in surface):
                return surface
        return None


def _sentence_line(translations: dict[str, str] | None, lang: str) -> str:
    t = (translations or {}).get(lang)
    return _label(SENTENCE, lang) + t if t else ""


def _colon(lang: str) -> str:
    return "：" if lang in ("ja", "zh") else ": "


def _label(table: dict[str, str], lang: str) -> str:
    return table[lang] + _colon(lang)


def _join(parts: list[str]) -> str:
    return "\n".join(p for p in parts if p)


def kanji_choice(d: Dictionary, *, word: str, reading: str, answer: str, options: list[str],
                 same_sound: set[str], translations: dict[str, str] | None,
                 meaning_fallback: dict[str, str] | None = None,
                 slot_sound: str | None = None) -> dict[str, str]:
    """書き取り / 同音・同訓異字: one kanji of ``word`` chosen from ``options``.

    ``slot_sound`` is the answer kanji's reading in the word (たい in 楽隊); the
    same-sound options then get an example where they are read that way too.
    """
    out = {}
    others = [o for o in options if o != answer]
    for lang in LANGS:
        m = d.meaning(word, reading, lang, (meaning_fallback or {}).get(lang, ""))
        head = {
            "ko": f"{ANSWER['ko']}: {d.kanji_label(answer, 'ko', False)} — 「{word}」({reading})"
                  + (f": {m}" if m else ""),
            "ja": f"{ANSWER['ja']}：{answer} —「{word}」（{reading}）" + (f"＝{m}" if m else ""),
            "zh": f"{ANSWER['zh']}：{answer} ——「{word}」（{reading}）" + (f"：{m}" if m else ""),
            "en": f"{ANSWER['en']}: {answer} — 「{word}」 ({reading})" + (f": {m}" if m else ""),
        }[lang]
        sound = [o for o in others if o in same_sound]
        shape = [o for o in others if o not in same_sound]
        sep = "·" if lang == "ko" else "、" if lang in ("ja", "zh") else ", "
        lines = [head, _sentence_line(translations, lang)]
        if sound:
            lines.append(_label(SAME_SOUND, lang) + sep.join(
                d.kanji_label(o, lang, sound=slot_sound) for o in sound))
        if shape:
            label = LOOKALIKE[lang] if not sound else OTHER[lang]
            lines.append(f"{label}{_colon(lang)}" + sep.join(d.kanji_label(o, lang) for o in shape))
        out[lang] = _join(lines)
    return out


def reading_choice(d: Dictionary, *, word: str, reading: str, options: list[str],
                   split: list[tuple[str, str]] | None, translations: dict[str, str] | None,
                   meaning_fallback: dict[str, str] | None = None,
                   kun_only: bool = False) -> dict[str, str]:
    """読み: the reading of ``word`` chosen from ``options``."""
    out = {}
    others = [o for o in options if o != reading]
    for lang in LANGS:
        m = d.meaning(word, reading, lang, (meaning_fallback or {}).get(lang, ""))
        parts = ""
        if split and len(split) > 1:
            eq = "=" if lang != "ja" else "＝"
            parts = "・".join(f"{c}{eq}{r}" for c, r in split) if lang in ("ja", "zh") \
                else ", ".join(f"{c}={r}" for c, r in split)
        kind = {"ko": "훈독" if kun_only else "읽기", "ja": "訓読み" if kun_only else "読み",
                "zh": "训读" if kun_only else "读音", "en": "kun reading" if kun_only else "reading"}[lang]
        head = {
            "ko": f"「{word}」의 {kind}: {reading}" + (f" ({parts})" if parts else ""),
            "ja": f"「{word}」の{kind}は「{reading}」" + (f"（{parts}）" if parts else "") + "。",
            "zh": f"「{word}」的{kind}是「{reading}」" + (f"（{parts}）" if parts else "") + "。",
            "en": f"The {kind} of 「{word}」 is {reading}" + (f" ({parts})" if parts else "") + ".",
        }[lang]
        lines = [head]
        if m:
            # a rare kanji's Korean "meaning" is its 훈음 (길할 기), and says so
            label = "훈음" + _colon(lang) if kun_only and lang == "ko" else _label(MEANING, lang)
            lines.append(label + m)
        lines.append(_sentence_line(translations, lang))
        notes = []
        for o in others:
            w = d.word_for_reading(o, word)
            if w:
                notes.append(f"{o}({w})" if lang == "ko" else f"{o}（{w}）" if lang in ("ja", "zh")
                             else f"{o} ({w})")
        if notes:
            sep = "·" if lang == "ko" else "、" if lang in ("ja", "zh") else ", "
            tail = {"ko": " — 다른 말의 읽기", "ja": "は別の語の読み", "zh": "是其他词的读音",
                    "en": " are readings of other words"}[lang]
            lines.append(_label(OTHER, lang) + sep.join(notes) + tail)
        out[lang] = _join(lines)
    return out


def option_notes(d: Dictionary, options: list[str], answer: str, explanation: str,
                 lang: str) -> str:
    """A line naming what each unmentioned wrong option is, for any bank.

    A one-kanji option gets its 훈음 / meaning; a word option its meaning.
    Readings (kana only) and whole sentences are left alone, as is any option
    the explanation already talks about.
    """
    notes = []
    for o in options:
        if o == answer or not o or o in explanation or len(o) > 6:
            continue
        if not any(is_kanji(c) for c in o):
            continue
        if len(o) == 1:
            notes.append(d.kanji_label(o, lang, False))
            continue
        meaning = next((_short(g.get(lang, ""), 16 if lang != "en" else 28)
                        for _, g in _gloss_for_surface(d, o) if g.get(lang)), "")
        if meaning:
            notes.append(f"{o}({meaning})" if lang in ("ko", "en") else f"{o}（{meaning}）")
    if not notes:
        return ""
    sep = "·" if lang == "ko" else "、" if lang in ("ja", "zh") else ", "
    return _label(OTHER, lang) + sep.join(notes)


_SURFACE_INDEX: dict[int, dict[str, list]] = {}


def _gloss_for_surface(d: Dictionary, surface: str):
    index = _SURFACE_INDEX.get(id(d))
    if index is None:
        index = defaultdict(list)
        for key, g in d.word_gloss.items():
            index[key[0]].append((key, g))
        _SURFACE_INDEX[id(d)] = index
    return index.get(surface, [])
