"""Mechanical question generation for the 準1級/1級 exam bank.

準1級 and 1級 cover 3,800 kanji that no one has authored questions for, and
they are obscure enough that writing them by hand — or having a model invent
them — is where wrong answers come from. So every question here is derived from
vocabulary that actually exists in JMdict, and the generator returns None rather
than emit anything it cannot prove has exactly one correct answer.

Two kinds are produced:

* ``reading`` (漢検 大問1 読み) — show the word, pick its reading. A distractor
  is safe when it is not itself a reading of that word. It is *good* when it
  cannot be eliminated without knowing the target kanji: it keeps the word's
  kana and the reading of every other character, and differs only in the part
  the target kanji spells (see ``align_reading`` / ``reading_distractors``).
* ``orthography`` (大問2 書き取り) — blank the target kanji, pick it from four.
  A distractor is safe when substituting it does not spell another real word.
"""
from __future__ import annotations

import html
import random
import re
import unicodedata
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

_OPTION_COUNT = 4
# 漢検 熟語 run two to four characters; longer JMdict surfaces are names.
_MAX_COMPOUND = 4

# Classic 漢検 traps: a dropped/added dakuten, a lost long vowel, a missing
# gemination. Each maps a kana to the one a careless reader confuses it with.
_DAKUTEN_PAIRS = [
    ("か", "が"), ("き", "ぎ"), ("く", "ぐ"), ("け", "げ"), ("こ", "ご"),
    ("さ", "ざ"), ("し", "じ"), ("す", "ず"), ("せ", "ぜ"), ("そ", "ぞ"),
    ("た", "だ"), ("ち", "ぢ"), ("つ", "づ"), ("て", "で"), ("と", "ど"),
    ("は", "ば"), ("ひ", "び"), ("ふ", "ぶ"), ("へ", "べ"), ("ほ", "ぼ"),
]
_DAKUTEN = str.maketrans(dict(_DAKUTEN_PAIRS))
_UNDAKUTEN = str.maketrans({v: k for k, v in _DAKUTEN_PAIRS})
_HANDAKUTEN = {"は": "ぱ", "ひ": "ぴ", "ふ": "ぷ", "へ": "ぺ", "ほ": "ぽ"}
_UNVOICE = {**{v: k for k, v in _DAKUTEN_PAIRS},
            **{v: k for k, v in _HANDAKUTEN.items()}}
# 促音便: 学(がく)+校 → がっこう, 骨(こつ)+折 → こっせつ.
_GEMINABLE = set("つちくきり")

# JMdict misc tags for names, titles and other encyclopedic entries. 漢検 never
# asks for 山一證券 or 白鷗大学, and they make obvious distractors besides.
NAME_TAGS = frozenset({
    "organization", "company", "work", "product", "place", "person",
    "surname", "given", "fict", "char", "creat", "dei", "ev", "group", "myth",
    "obj", "oth", "relig", "serv", "ship", "leg", "unclass", "station",
    "fem", "masc", "doc",
})
STALE_TAGS = frozenset({"arch", "obs", "dated", "rare"})
_AFFIX_POS = frozenset({"suf", "pref", "n-suf", "n-pref", "ctr"})
_BAD_KEB = frozenset({"sK", "rK", "oK", "iK"})
# Latin binomials and "species of" glosses mark encyclopedic flora/fauna
# entries (茶色蛹貝, 梟鸚鵡), which are dictionary filler rather than 熟語.
SPECIES_GLOSS = re.compile(
    r"\((?![A-Z][a-z]+ (?:dynasty|period|era|clan|school|sect|style)\b)"
    r"[A-Z][a-z]+ [a-z]+(?: [a-z]+)?[);,]|\bspp?\.|\bspecies of\b|\bgenus\b"
    r"|\bfamily [A-Z][a-z]+dae\b"
    r"|\bdinosaur\b")
PROPER_GLOSS = re.compile(
    r"\b(University|College|Company|Corporation|Co\.|Ltd|Inc\.|Securities|"
    r"Railway)\b|\bBank of\b"
    r"|[A-Z][\w-]+ (Temple|Shrine|Castle|Station|River|Island|Province|"
    r"Prefecture|Mountains?)\b|\([A-Z][a-z]+\)$|^(?:[A-Z][a-z]+ )+dynasty\b")

# A gloss describing a creative work rather than the word (火蜥蜴: "Salamander
# (poem by Octavio Paz)").
WORK_GLOSS = re.compile(r"\((?:poem|novel|film|song|manga|anime|play|opera|book)\b"
                        r"|\bby [A-Z][a-z]+ [A-Z]")


# ── kana helpers ────────────────────────────────────────────────────────────

def kata_to_hira(text: str) -> str:
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def _is_kana(text: str) -> bool:
    return bool(text) and all("ぁ" <= ch <= "ゟ" or ch == "ー" for ch in text)


def _is_katakana(text: str) -> bool:
    return bool(text) and all("ァ" <= ch <= "ヿ" or ch == "ー" for ch in text)


def is_hira(ch: str) -> bool:
    return "ぁ" <= ch <= "ゟ"


def is_kanji(ch: str) -> bool:
    return ch == "々" or "㐀" <= ch <= "鿿" or "豈" <= ch <= "﫿" or ch >= "𠀀"


def is_compat_ideograph(ch: str) -> bool:
    cp = ord(ch)
    return 0xF900 <= cp <= 0xFAFF or 0x2F800 <= cp <= 0x2FA1F


_PARTICLES = frozenset("のがにをはとへもやで")


def surface_shape_ok(surface: str, allow_inner_okurigana: bool = False) -> bool:
    """Kanji, then optionally trailing okurigana — nothing else.

    Kana in the middle (割り鏨, 鬼の霍乱) or in front (あい嚢鈔) are set phrases,
    titles or partial spellings, and 漢検 大問1/2 prints neither shape.
    ``allow_inner_okurigana`` admits a short non-particle kana run between
    kanji (包み釦, 擦れ疵) — only used to keep a kanji covered when it has no
    other vocabulary.
    """
    if not surface or not is_kanji(surface[0]) or surface[0] == "々":
        return False
    if any(not (is_kanji(ch) or is_hira(ch)) for ch in surface):
        return False
    runs = list(re.finditer(r"[ぁ-ゟ]+", surface))
    inner = [m for m in runs if m.end() < len(surface)]
    if not inner:
        return True
    if not allow_inner_okurigana or len(inner) > 1:
        return False
    run = inner[0].group()
    return len(run) <= 2 and not (set(run) & _PARTICLES)


def kana_runs(surface: str) -> list[str]:
    return re.findall(r"[ぁ-ゟ]+", surface)


def is_reduplicated(reading: str) -> bool:
    half = len(reading) // 2
    return len(reading) % 2 == 0 and half > 0 and reading[:half] == reading[half:]


def reading_variants(base: str) -> list[str]:
    """How a kanji reading surfaces inside a compound: as is, voiced
    (連濁: ほね → ぼね), half-voiced (ふう → ぷう) or geminated (こつ → こっ)."""
    out = [base]
    first = base[0]
    voiced = first.translate(_DAKUTEN)
    if voiced != first:
        out.append(voiced + base[1:])
    if first in _HANDAKUTEN:
        out.append(_HANDAKUTEN[first] + base[1:])
    if len(base) >= 2 and base[-1] in _GEMINABLE:
        for v in list(out):
            out.append(v[:-1] + "っ")
    return out


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
        reading.replace("ょう", "ゅう") if "ょう" in reading
        else reading.replace("ゅう", "ょう"),
        reading.replace("う", "") if reading.endswith("う") else reading + "う",
    ):
        if candidate != reading and _is_kana(candidate) and candidate not in out:
            out.append(candidate)
    return out


def _segment_near_misses(segment: str) -> list[str]:
    """perturb_reading for a single kanji's slice of a reading, plus the
    first-kana voicing swaps that a compound's 連濁 invites."""
    out = perturb_reading(segment)
    first = segment[0]
    if first in _UNVOICE:
        out.append(_UNVOICE[first] + segment[1:])
    if len(segment) >= 2 and segment.endswith("い"):
        out.append(segment[:-1] + "う")
    elif len(segment) >= 2 and segment.endswith("う"):
        out.append(segment[:-1] + "い")
    # わん→わんう, いっ→いっう are not near misses, just impossible kana.
    return [s for s in dict.fromkeys(out)
            if s and s != segment and _is_kana(s) and "んう" not in s
            and "っう" not in s and not s.endswith("っ")]


# ── JMdict ──────────────────────────────────────────────────────────────────

@dataclass
class JMSense:
    pos: set[str] = field(default_factory=set)
    misc: set[str] = field(default_factory=set)
    stagk: list[str] = field(default_factory=list)
    stagr: list[str] = field(default_factory=list)
    glosses: list[str] = field(default_factory=list)


@dataclass
class JMEntry:
    seq: int
    kebs: list[tuple[str, set[str], bool]] = field(default_factory=list)
    # (reb, re_inf, has re_pri, re_restr, re_nokanji)
    rebs: list[tuple[str, set[str], bool, list[str], bool]] = field(default_factory=list)
    senses: list[JMSense] = field(default_factory=list)
    loanword: bool = False

    def readings_for(self, surface: str) -> list[tuple[str, set[str], bool]]:
        return [(reb, inf, pri) for reb, inf, pri, restr, nokanji in self.rebs
                if not nokanji and (not restr or surface in restr)]

    def keb_info(self, surface: str) -> tuple[set[str], bool] | None:
        for keb, inf, pri in self.kebs:
            if keb == surface:
                return inf, pri
        return None

    def senses_for(self, surface: str, reading: str) -> list[JMSense]:
        return [s for s in self.senses
                if (not s.stagk or surface in s.stagk)
                and (not s.stagr or reading in s.stagr)]


@dataclass
class JMLexicon:
    entries_by_keb: dict[str, list[JMEntry]]
    # Every reading (hiragana) JMdict gives any spelling, ignoring re_restr —
    # over-excluding a distractor is harmless, under-excluding is a second
    # right answer.
    readings: dict[str, set[str]]

    def all_readings(self, surface: str) -> set[str]:
        return self.readings.get(surface, set())


_TAG = re.compile(r"<(\w+)(?: [^>]*)?>(.*)</\1>|<(\w+)/>|<(/?\w+)>")
_ENT = re.compile(r"&([\w-]+);")


def load_jmdict_lexicon(path: str | Path) -> JMLexicon:
    """Kanji-bearing JMdict entries with the tags the generator needs.

    A line scanner rather than an XML parser: JMdict writes one element per
    line, and the misc/pos entities are wanted by *name* (``&company;``), which
    an entity-resolving parser would expand into prose.
    """
    entries_by_keb: dict[str, list[JMEntry]] = defaultdict(list)
    readings: dict[str, set[str]] = defaultdict(set)
    entry: JMEntry | None = None
    sense: JMSense | None = None
    reb_state: list | None = None
    keb_state: list | None = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line.startswith("<"):
                continue
            if line == "<entry>":
                entry = JMEntry(seq=0)
                continue
            if entry is None:
                continue
            if line == "</entry>":
                if entry.kebs:
                    for keb, _inf, _pri in entry.kebs:
                        entries_by_keb[keb].append(entry)
                        for reb, *_ in entry.rebs:
                            readings[keb].add(kata_to_hira(reb))
                entry = None
                continue
            if line == "<k_ele>":
                keb_state = ["", set(), False]
                continue
            if line == "</k_ele>":
                entry.kebs.append((keb_state[0], keb_state[1], keb_state[2]))
                keb_state = None
                continue
            if line == "<r_ele>":
                reb_state = ["", set(), False, [], False]
                continue
            if line == "</r_ele>":
                entry.rebs.append(tuple(reb_state))  # type: ignore[arg-type]
                reb_state = None
                continue
            if line == "<sense>":
                sense = JMSense()
                continue
            if line == "</sense>":
                # A sense with no pos inherits the previous one's (JMdict rule).
                if not sense.pos and entry.senses:
                    sense.pos = set(entry.senses[-1].pos)
                entry.senses.append(sense)
                sense = None
                continue
            if line.startswith("<lsource"):
                entry.loanword = True
                continue
            m = _TAG.match(line)
            if not m:
                continue
            if m.group(3) == "re_nokanji" and reb_state is not None:
                reb_state[4] = True
                continue
            tag, text = m.group(1), m.group(2)
            if tag is None:
                continue
            ent = _ENT.fullmatch(text or "")
            name = ent.group(1) if ent else None
            if tag == "ent_seq":
                entry.seq = int(text)
            elif tag == "keb" and keb_state is not None:
                keb_state[0] = text
            elif tag == "ke_inf" and keb_state is not None and name:
                keb_state[1].add(name)
            elif tag == "ke_pri" and keb_state is not None:
                keb_state[2] = True
            elif tag == "reb" and reb_state is not None:
                reb_state[0] = text
            elif tag == "re_inf" and reb_state is not None and name:
                reb_state[1].add(name)
            elif tag == "re_pri" and reb_state is not None:
                reb_state[2] = True
            elif tag == "re_restr" and reb_state is not None:
                reb_state[3].append(text)
            elif sense is not None:
                if tag == "pos" and name:
                    sense.pos.add(name)
                elif tag in ("misc", "field") and name:
                    sense.misc.add(name)
                elif tag == "stagk":
                    sense.stagk.append(text)
                elif tag == "stagr":
                    sense.stagr.append(text)
                elif tag == "gloss" and 'xml:lang="' not in line.split(">", 1)[0]:
                    sense.glosses.append(html.unescape(text))
                elif tag == "gloss" and 'xml:lang="eng"' in line.split(">", 1)[0]:
                    sense.glosses.append(html.unescape(text))
    return JMLexicon(dict(entries_by_keb), dict(readings))


@dataclass(frozen=True)
class ReadingInfo:
    """One (surface, reading) pair as JMdict describes it."""
    reading: str            # as JMdict spells it (may be katakana)
    common: bool
    keb_tags: frozenset[str]
    reb_tags: frozenset[str]
    misc: frozenset[str]    # misc of the first sense that applies
    all_misc: frozenset[str]
    pos: frozenset[str]
    affix_only: bool
    loanword: bool
    has_hiragana_sibling: bool
    en_gloss: str | None


def reading_infos(lex: JMLexicon, surface: str) -> list[ReadingInfo]:
    out: list[ReadingInfo] = []
    for entry in lex.entries_by_keb.get(surface, []):
        info = entry.keb_info(surface)
        if info is None:
            continue
        keb_inf, keb_pri = info
        applicable = entry.readings_for(surface)
        has_hira = any(not _is_katakana(r) for r, _, _ in applicable)
        for reb, re_inf, re_pri in applicable:
            senses = entry.senses_for(surface, reb) or entry.senses
            if not senses:
                continue
            first = senses[0]
            all_misc = set().union(*(s.misc for s in senses))
            pos = set().union(*(s.pos for s in senses))
            affix_only = all((s.pos and s.pos <= _AFFIX_POS) for s in senses)
            out.append(ReadingInfo(
                reading=reb, common=bool(keb_pri or re_pri),
                keb_tags=frozenset(keb_inf), reb_tags=frozenset(re_inf),
                misc=frozenset(first.misc), all_misc=frozenset(all_misc),
                pos=frozenset(pos), affix_only=affix_only,
                loanword=entry.loanword, has_hiragana_sibling=has_hira,
                en_gloss=_pick_en_gloss(senses)))
    return out


def _pick_en_gloss(senses: list[JMSense]) -> str | None:
    """First sense that is not a name or a work title; at most two glosses
    from it, so the meaning stays a gloss and not a paragraph."""
    ranked = sorted(senses, key=lambda s: bool(s.misc & NAME_TAGS))
    for sense in ranked:
        glosses = [g for g in sense.glosses if g]
        if glosses:
            return "; ".join(glosses[:2])
    return None


def is_name_like(infos: list[ReadingInfo], en: str | None = None) -> bool:
    """Proper nouns, products and titles: skip the whole surface."""
    if any(i.misc & NAME_TAGS for i in infos) and not any(
            i.common and not (i.misc & NAME_TAGS) for i in infos):
        return True
    if any(i.common for i in infos):
        return False
    return bool(en and PROPER_GLOSS.search(en))


def is_species_like(infos: list[ReadingInfo], glosses: list[str]) -> bool:
    if any(i.common for i in infos):
        return False
    return any(SPECIES_GLOSS.search(g) for g in glosses if g)


# ── reading alignment ───────────────────────────────────────────────────────

def kanji_reading_table(rows) -> dict[str, list[tuple[str, str]]]:
    """literal → [(hiragana segment, 'on'|'kun'|'kun_okuri')] from KANJIDIC-style rows
    (literal, axis, value): on in katakana, kun as なぶ.る / こわ-."""
    table: dict[str, list[tuple[str, str]]] = defaultdict(list)
    for literal, axis, value in rows:
        if axis not in ("on", "kun") or not value:
            continue
        v = kata_to_hira(value).strip("-").split(".")[0].replace("-", "")
        # A kun reading with okurigana (か.む) contributes only its stem; it
        # is marked so a noun compound is not offered a bare verb stem (そか).
        if axis == "kun" and "." in value:
            axis = "kun_okuri"
        if v and _is_kana(v) and (v, axis) not in table[literal]:
            table[literal].append((v, axis))
    return dict(table)


_NON_INITIAL = frozenset("んっゃゅょぁぃぅぇぉゎー")


def align_reading(
    surface: str,
    reading: str,
    table: dict[str, list[tuple[str, str]]],
    wildcard: str | None = None,
) -> list[tuple[str, str | None]] | None:
    """Split ``reading`` into one slice per character of ``surface``.

    Returns [(slice, base)] where ``base`` is the dictionary reading the slice
    came from (None for kana, 々 and the wildcard). Kana in the surface must
    match verbatim; 々 repeats the previous slice (possibly voiced). If
    ``wildcard`` is given, that character may take any non-empty slice when
    its dictionary readings do not fit — the target kanji of a question is
    exactly the character whose reading may be unusual.
    """
    reading = kata_to_hira(reading)
    n = len(surface)
    memo: dict[tuple[int, int, str], list | None] = {}

    def go(i: int, pos: int, prev: str) -> list | None:
        if i == n:
            return [] if pos == len(reading) else None
        key = (i, pos, prev)
        if key in memo:
            return memo[key]
        ch = surface[i]
        result = None
        if is_hira(ch):
            if reading.startswith(ch, pos):
                rest = go(i + 1, pos + 1, ch)
                if rest is not None:
                    result = [(ch, None)] + rest
        else:
            options: list[tuple[str, str | None]] = []
            if ch == "々" and prev:
                options = [(v, None) for v in reading_variants(prev)]
            else:
                for base, _axis in table.get(ch, []):
                    options.extend((v, base) for v in reading_variants(base))
            # Longest first: 黄金 prefers こ|がね over nothing, and a greedy
            # longer match rarely strands the tail.
            for seg, base in sorted(set(options), key=lambda o: (-len(o[0]), o[0], o[1] or "")):
                if seg and reading.startswith(seg, pos):
                    rest = go(i + 1, pos + len(seg), seg)
                    if rest is not None:
                        result = [(seg, base)] + rest
                        break
            if result is None and wildcard is not None and ch == wildcard:
                for end in range(pos + 1, len(reading) + 1):
                    seg = reading[pos:end]
                    # A slice starts on a mora: 鞦韆 is not ぶら|んこ.
                    if seg[0] in _NON_INITIAL:
                        break
                    rest = go(i + 1, end, seg)
                    if rest is not None:
                        result = [(seg, None)] + rest
                        break
        memo[key] = result
        return result

    return go(0, 0, "")


def target_frame(
    surface: str, reading: str, literal: str,
    table: dict[str, list[tuple[str, str]]],
) -> tuple[list[str], set[int]] | None:
    """The reading as per-character slices, and which slices spell the target
    (every occurrence of ``literal`` plus a 々 that repeats it)."""
    aligned = align_reading(surface, reading, table)
    if aligned is None:
        aligned = align_reading(surface, reading, table, wildcard=literal)
    if aligned is None:
        return None
    slots = set()
    for i, ch in enumerate(surface):
        if ch == literal or (ch == "々" and i - 1 in slots):
            slots.add(i)
    if not slots:
        return None
    return [seg for seg, _ in aligned], slots


# ── distractors ─────────────────────────────────────────────────────────────

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


def reading_distractors(
    segments: list[str],
    slots: set[int],
    surface: str,
    *,
    alternatives: dict[str, list[str]],
    banned: set[str],
    rng: random.Random,
) -> list[str] | None:
    """Three wrong readings that differ from the answer only in the target's
    slice, so the easy kanji and the kana give nothing away.

    ``alternatives`` maps a source name to replacement slices for the target:
    "own" (the target's other on/kun readings — the 湯桶/重箱 trap), "frame"
    (what that position reads as in real words sharing the rest of the
    surface), "lookalike" (readings of kanji that look like the target),
    "near" (near misses of the slice itself) and "generic" (any kanji reading
    of the slice's length, used only when the others run out). At most two
    near misses, never without a real reading beside them: several together
    read as noise and point at the one real word.
    """
    first = min(slots)
    target = segments[first]
    followed_by_kana = (max(slots) + 1 < len(surface)
                        and is_hira(surface[max(slots) + 1]))

    def build(alt: str) -> str:
        return "".join(
            (alt if i in slots else seg) for i, seg in enumerate(segments))

    close_b: dict[str, list[str]] = {}
    loose_b: dict[str, list[str]] = {}
    for name, alts in alternatives.items():
        close, loose = [], []
        for alt in alts:
            if not alt or alt == target or not _is_kana(alt):
                continue
            if len(alt) > len(target) + 2:
                continue
            candidate = build(alt)
            if candidate in banned or candidate in close or candidate in loose:
                continue
            if is_reduplicated(candidate) and not is_reduplicated(build(target)):
                continue
            # A slice of about the target's length is far more convincing
            # than one twice as long or short (いんぎん vs いんねんごろ).
            (close if abs(len(alt) - len(target)) <= 1 else loose).append(candidate)
        rng.shuffle(close)
        rng.shuffle(loose)
        close_b[name], loose_b[name] = close, loose
    order = ["frame", "own", "lookalike"]
    if followed_by_kana:
        # A verb or adjective stem: other words' stems before the same
        # okurigana (なじる, いじる for なぶる) beat on-readings (どうる).
        order = ["frame", "lookalike", "own"]
    start = rng.randrange(len(order))
    order = order[start:] + order[:start]
    chosen: list[str] = []

    def round_robin(buckets: dict[str, list[str]]) -> None:
        while len(chosen) < _OPTION_COUNT - 1 and any(buckets.get(n) for n in order):
            for name in order:
                pool = buckets.get(name)
                while pool:
                    cand = pool.pop(0)
                    if cand not in chosen:
                        chosen.append(cand)
                        break
                if len(chosen) == _OPTION_COUNT - 1:
                    break

    # Real readings of about the right length, then one near miss, then
    # real readings of an off length, then any kanji reading of the same
    # length ("generic"), and only then a second near miss — never three.
    round_robin(close_b)
    near = close_b.get("near", []) + loose_b.get("near", [])
    near_used = 0

    def add_near() -> None:
        nonlocal near_used
        while near and len(chosen) < _OPTION_COUNT - 1:
            cand = near.pop(0)
            if cand not in chosen:
                chosen.append(cand)
                near_used += 1
                return

    add_near()
    round_robin(loose_b)
    order = ["generic"]
    round_robin(close_b)
    round_robin(loose_b)
    # A second near miss only beside at least one real reading.
    if len(chosen) == _OPTION_COUNT - 2 and near_used < len(chosen):
        add_near()
    if len(chosen) < _OPTION_COUNT - 1:
        return None
    return chosen


# ── explanations ────────────────────────────────────────────────────────────

def _kana_batchim(reading: str) -> bool:
    """Whether a Japanese word, said aloud, ends in a consonant for the
    purpose of Korean particles: only ん does (なぶる는, こんろ는, ろっこつ는
    but にんじん은)."""
    return bool(reading) and reading[-1] in "んン"


def _ko(reading: str, pair: str) -> str:
    """Korean particle agreeing with the final sound of ``reading``.
    ``pair`` is "은/는", "이/가", "을/를", "이라고/라고" or "으로/로"."""
    with_b, without_b = pair.split("/")
    return with_b if _kana_batchim(reading) else without_b


def _explanations(
    surface: str, reading: str, literal: str, word: "WordRow", kind: str
) -> dict[str, str]:
    """All four app languages. The meaning is included wherever the build has
    a gloss in that language, and left out rather than faked where not."""
    ko_m = f" 뜻은 ‘{word.ko}’입니다." if word.ko else ""
    ja_m = f"「{word.ja}」という意味です。" if word.ja else ""
    zh_m = f"意思是“{word.zh}”。" if word.zh else ""
    en_m = f' and means "{word.en}"' if word.en else ""
    if kind == "reading":
        return {
            "ko": f"「{surface}」{_ko(reading, '은/는')} {reading}"
                  f"{_ko(reading, '이라고/라고')} 읽습니다.{ko_m}",
            "ja": f"「{surface}」は「{reading}」と読みます。{ja_m}",
            "zh": f"「{surface}」读作 {reading}。{zh_m}",
            "en": f"「{surface}」 is read {reading}{en_m}.",
        }
    return {
        "ko": f"{reading}{_ko(reading, '은/는')} 「{surface}」"
              f"{_ko(reading, '으로/로')} 씁니다.{ko_m} "
              f"빈칸에 들어갈 한자는 {literal}입니다.",
        "ja": f"「{reading}」は「{surface}」と書きます。{ja_m}"
              f"空欄に入る漢字は「{literal}」です。",
        "zh": f"{reading} 写作「{surface}」。{zh_m}填入空格的汉字是 {literal}。",
        "en": f"{reading} is written 「{surface}」{en_m}. "
              f"The kanji for the blank is {literal}.",
    }


@dataclass(frozen=True)
class WordRow:
    """A vocabulary row as the generator needs it."""
    surface: str
    reading: str
    en: str | None = None
    ko: str | None = None
    ja: str | None = None
    zh: str | None = None


def build_reading_question(
    word: WordRow,
    *,
    literal: str,
    level: str,
    other_readings: list[str],
    forbidden: set[str],
    rng: random.Random,
    distractors: list[str] | None = None,
) -> dict | None:
    """読み: show the word, pick its reading.

    ``forbidden`` holds every reading that surface is known to take, so a
    homograph's other reading is never offered as a wrong answer.

    ``distractors``, when given, are used as is (the generator's aligned,
    frame-preserving ones); otherwise three are drawn from ``other_readings``
    — keeping the surface's kana runs and reduplication — with at most one
    near-miss perturbation to fill in.
    """
    if not _is_kana(word.reading):
        return None
    if not 2 <= len(word.surface) <= _MAX_COMPOUND:
        # 漢検 大問1 asks for the reading of a 熟語, or of a kanji with its
        # okurigana. A bare kanji collapses to a one-mora guess; past four
        # characters JMdict is mostly proper nouns and set phrases (皇學館大学,
        # 単于都護府), which the paper never asks about.
        return None
    banned = {kata_to_hira(r) for r in forbidden} | {word.reading}
    if distractors is not None:
        chosen = [d for d in dict.fromkeys(distractors) if d not in banned]
        if len(chosen) < _OPTION_COUNT - 1:
            return None
        chosen = chosen[:_OPTION_COUNT - 1]
    else:
        pool = [r for r in other_readings
                if _is_kana(r) and fits_kana_frame(word.surface, word.reading, r)]
        rng.shuffle(pool)
        chosen = _pick_distractors(pool, banned, rng, _OPTION_COUNT - 1) or []
        if len(chosen) < _OPTION_COUNT - 1:
            chosen = (_pick_distractors(pool, banned, rng, _OPTION_COUNT - 2)
                      or [])
            near_miss = _pick_distractors(
                [p for p in perturb_reading(word.reading)
                 if fits_kana_frame(word.surface, word.reading, p)],
                banned | set(chosen), rng, 1)
            if len(chosen) < _OPTION_COUNT - 2 or near_miss is None:
                return None
            chosen = chosen + near_miss

    options = chosen + [word.reading]
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


def fits_kana_frame(surface: str, answer: str, candidate: str) -> bool:
    """A distractor must show the same kana the surface prints — same
    okurigana at the end, every kana run in order — and be reduplicated
    when the surface is a 畳語. Otherwise the kana alone picks the answer
    (嬲る: only なぶる ends in る)."""
    # 畳語 (嘖々, 噁噁): the answer is XYXY, so every option must be. Judged
    # on the surface — 交媾 こうこう only happens to repeat.
    if len(surface) == 2 and (surface[1] == "々" or surface[0] == surface[1]):
        if not is_reduplicated(candidate):
            return False
    runs = kana_runs(surface)
    if runs:
        if surface.endswith(runs[-1]):
            if not candidate.endswith(runs[-1]) or len(candidate) <= len(runs[-1]):
                return False
        pos = 0
        for run in runs:
            found = candidate.find(run, pos)
            if found < 0:
                return False
            pos = found + len(run)
    return True


def build_orthography_question(
    word: WordRow,
    *,
    literal: str,
    level: str,
    candidates: list[str],
    real_surfaces: set[str],
    rng: random.Random,
    kind: str = "orthography",
    reading_spellings: dict[str, set[str]] | None = None,
    shuffle_candidates: bool = True,
) -> dict | None:
    """書き取り: blank the target kanji, pick it from four.

    `kind` selects which 大問 the question belongs to. 同音・同訓異字
    ("doonkun") is the identical shape with a homophone candidate pool — the
    reading is then no help and only the meaning picks the answer out.

    The surrounding characters are what pin the answer, so single-character
    words are skipped, and a candidate is rejected when substituting it spells
    another word that exists — that would be a second defensible answer.
    ``reading_spellings`` (surface → readings, e.g. all of JMdict) widens that
    check to spellings the vocabulary table does not carry (濯ぐ for すすぐ).
    A candidate already visible in the word, a compatibility ideograph, or one
    that normalises to another option is never offered.

    With ``shuffle_candidates=False`` the caller's order (best first) is kept.
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
    reading = kata_to_hira(word.reading)

    safe = []
    seen_norm = {unicodedata.normalize("NFKC", literal)}
    for candidate in candidates:
        if candidate == literal or candidate in word.surface:
            continue
        if is_compat_ideograph(candidate):
            continue
        norm = unicodedata.normalize("NFKC", candidate)
        if norm in seen_norm:
            continue
        substituted = word.surface[:index] + candidate + word.surface[index + 1:]
        if substituted in real_surfaces:
            continue
        if reading_spellings is not None and (
                substituted in reading_spellings
                or reading in reading_spellings.get(substituted, ())):
            continue
        seen_norm.add(norm)
        safe.append(candidate)
    if shuffle_candidates:
        rng.shuffle(safe)
    distractors = _pick_distractors(safe, set(), rng, _OPTION_COUNT - 1)
    if distractors is None:
        return None

    options = distractors + [literal]
    rng.shuffle(options)
    assert len({unicodedata.normalize("NFKC", o) for o in options}) == _OPTION_COUNT
    return {
        "literal": literal,
        "level": level,
        "kind": kind,
        "prompt": f"{word.reading}　—　<u>{blanked}</u>",
        "options": options,
        "answer": options.index(literal),
        "focus": blanked,
        "explanations": _explanations(word.surface, word.reading, literal,
                                      word, "orthography"),
    }
