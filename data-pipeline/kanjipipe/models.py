from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Reading:
    lang_axis: str  # 'on' | 'kun' | 'pinyin' | 'eum'
    value: str
    is_common: bool = True


@dataclass
class Gloss:
    lang: str  # 'ko' | 'ja' | 'zh' | 'en'
    text: str


@dataclass
class Kanji:
    literal: str
    codepoint: int          # Unicode scalar (UCS)
    stroke_count: int
    grade: int | None       # 1-6 = 小, 8 = 中学/常用
    freq_rank: int | None
    radical: int | None     # classical radical number
    jlpt_level: str | None = None  # 'N5'..'N1'
    readings: list[Reading] = field(default_factory=list)
    glosses: list[Gloss] = field(default_factory=list)


@dataclass
class Word:
    surface: str
    reading_kana: str
    is_common: bool = True
    en_glosses: list[str] = field(default_factory=list)


@dataclass
class Sentence:
    ja_text: str
    translations: dict[str, str] = field(default_factory=dict)


@dataclass
class Relation:
    source_surface: str
    target_surface: str
    type: str


@dataclass
class LlmGloss:
    literal: str
    ko: str | None = None
    ja: str | None = None
    zh: str | None = None


@dataclass
class JlptQuestion:
    literal: str                  # the kanji this question is about (join key)
    level: str                    # 'N5'..'N1'
    kind: str                     # 'reading' | 'orthography' | 'context'
    prompt: str
    options: list[str]
    answer: int                   # 0-based index into options
    explanations: dict            # lang code → 해설 (ko/ja/zh/en)
    focus: str | None = None      # substring of prompt to underline
    focus: str | None = None   # substring of prompt to underline (target word)
