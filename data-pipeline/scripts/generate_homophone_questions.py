#!/usr/bin/env python3
"""Generate the 同音・同訓異字 bank for every 漢検 level.

漢検 tests this from 8級 up: a word with one kanji blanked, and four kanji that
all share the reading, so the reading itself is no help and only the meaning
picks the answer. That is the same shape as 書き取り with a different candidate
pool, so it reuses the same builder and the same safety rule — a candidate is
rejected when substituting it spells a word that also exists.

The rules, each of which exists because a reviewed sample broke it:

1. **Homophones of the reading actually used.** The word's kana reading is
   aligned to its kanji (``kanjipipe.furigana``: dictionary readings plus
   連濁 and 促音便), and the blank's slice — 眼 is がん in 開眼 — is what the
   distractors must share. Every segmentation has to agree on that slice and
   it has to come from a standard 音読み of the kanji; otherwise the word is
   skipped. Only all-kanji surfaces are used, so okurigana (偉い) and kun
   words (稼ぎ) cannot sneak through on a substring match.
2. **Standard readings only.** KANJIDIC marks every reading common, so 尽 サン
   and 区 コウ looked like homophones of 傘 and 好. A 音読み counts as standard
   when it is the aligned reading of that kanji in at least
   ``STANDARD_MIN_WORDS`` distinct words of the shipped vocabulary (JMdict
   words in ``out/kanji.sqlite``) whose kanji are all 常用 (2級 or easier).
   An alignment only counts when it is unique; where a slice fits several
   readings, the unchanged one wins (危惧 ぐ: グ, not ク voiced), a kun stem
   that repeats the 音 (詮 せん.ずる) is no rival, and otherwise the word
   credits whichever reading already has unambiguous evidence. This is a
   corpus stand-in for the 常用漢字表's reading column, which the pipeline
   does not ship; it excludes every rare reading the review found (尽サン
   区コウ 峡コウ 突カ 可コク 数ソク 巻ケン 公ク 習ジュ 入ジュ 軽キョウ 是シ 郎リョウ)
   while keeping thinly attested 常用 ones such as 納トウ (出納). Distractors
   need a standard reading; the answer's own reading needs only one word of
   evidence (挨拶 is the single word with 挨 アイ), since the word itself
   proves it.
3. **Exact-reading distractors.** A distractor must have a standard 音読み that
   surfaces as the same slice, voicing included (蔵 ぞう takes 象 像 増, never
   窓 争); it must not already appear in the word (授受); substituting it must
   not spell any JMdict headword (``--jmdict``, ``--lexicon``) nor a kanji
   string attested in a Japanese Tatoeba sentence (``--sentences``, which
   catches 画号 and 坑殺, missing from JMdict); a word is used once across the
   whole bank (押収 is not asked as both 押□ and □収); and every other kanji
   in the word must be at or below the item's 級.
4. **Distractor level.** Drawn from the item's level or easier; only when
   fewer than three exist are kanji up to ``LEVEL_STRETCH`` levels harder
   allowed (never beyond 2級). Still fewer, and the word is skipped rather than
   padded with a different reading the prompt would give away.

Run after a build, then rebuild so the questions are ingested:

    python -m kanjipipe.build_db --out out/kanji.sqlite
    python scripts/generate_homophone_questions.py
    python -m kanjipipe.build_db --out out/kanji.sqlite
"""
from __future__ import annotations

import argparse
import json
import random
import re
import sqlite3
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from kanjipipe.furigana import (  # noqa: E402
    _SEMI, _VOICE, Form, is_kanji, segmentations, slice_at, to_hiragana)
from kanjipipe.questions import (  # noqa: E402
    WordRow, build_orthography_question)

# The levels whose paper actually contains 同音異字 / 同音・同訓異字.
LEVELS = ("8級", "7級", "6級", "5級", "4級", "3級", "準2級", "2級")
# Easiest first. A distractor must be a kanji the learner could plausibly know,
# so it is drawn from this level or an easier one — offering a 5級 candidate the
# obscure 鐫 tests nothing, since it is eliminated on sight.
LEVEL_ORDER = ("10級", "9級", "8級", "7級", "6級", "5級", "4級", "3級",
               "準2級", "2級", "準1級", "1級")
RANK = {level: index for index, level in enumerate(LEVEL_ORDER)}
JOUYOU_MAX = RANK["2級"]
PER_KANJI = 2
# A level short of this gets a second pass allowing more words per kanji.
LEVEL_TARGET = 160
PER_KANJI_TOPUP = 6
STANDARD_MIN_WORDS = 2
LEVEL_STRETCH = 2
SEED = 20260728
# Real spellings no dictionary the pipeline ships lists, found in review:
# 画号 (a painter's art name, vs 雅号), 坑殺 (burying alive, vs 絞殺), 達摩
# (an accepted spelling of 達磨). A substitution landing on one is rejected.
KNOWN_REAL = frozenset({"画号", "坑殺", "達摩"})


def _all_kanji(surface: str) -> bool:
    return all(is_kanji(ch) and ch not in "々〆" for ch in surface)


_PARENS = re.compile(r"\s*[(（][^()（）]*[)）]")


def _parens_free(text: str) -> str:
    return _PARENS.sub("", text).strip()


def clean_gloss(text: str | None, limit: int = 30) -> str | None:
    """A gloss fit to print inside an explanation.

    Parenthesised asides are dropped innermost-first (「조용함 (주택가 등)」
    → 「조용함」, "quiet (e.g. neighbourhood)" → "quiet"), and an overlong
    gloss is cut back to its first ;/,-separated sense.
    """
    if not text:
        return None
    out = text
    while True:
        stripped = _PARENS.sub("", out)
        if stripped == out:
            break
        out = stripped
    out = re.sub(r"[()（）]", "", out).split("。")[0]
    out = re.sub(r"\s+", " ", out).strip(" ;,、，；・")
    if len(out) > limit:
        for sep in ("; ", "；", "、", "，", ", ", "・"):
            if sep in out:
                out = out.split(sep)[0].strip()
                break
    return out or None


class EnglishGlossPicker:
    """JMdict's first English sense, unless it is the obscure one.

    The first sense is occasionally a rare word (収蔵 "garnering", 漂白
    "blanching") where the second is the everyday one ("collection",
    "bleaching"). A gloss scores by its rarest word's document frequency
    across every English gloss in the DB; the second sense replaces the first
    only when the first is near-unique (≤ 2 glosses use its rarest word) and the
    second is clearly more common, or when the first will not fit in ~30
    characters and the second does. Looking further down the list picks up
    stray senses (俳諧 "absurd", 哀悼 "regret"), so it stops at two.
    """

    def __init__(self, all_glosses: list[str]):
        self.df: Counter[str] = Counter()
        for gloss in all_glosses:
            self.df.update(set(self._words(gloss)))

    @staticmethod
    def _words(text: str) -> list[str]:
        return re.findall(r"[a-z]+", _parens_free(text).lower())

    def score(self, gloss: str) -> int:
        words = [w for w in self._words(gloss) if len(w) > 2] or self._words(gloss)
        return min((self.df[w] for w in words), default=0)

    def pick(self, glosses: list[str]) -> str | None:
        # "a mere ... (e.g. a mere clerk)" reads as a fragment on its own.
        options = [g for g in (clean_gloss(g) for g in glosses[:2])
                   if g and "..." not in g and "…" not in g]
        if not options:
            return None
        first = options[0]
        if len(options) == 1:
            return first
        second = options[1]
        if len(first) > 30 and len(second) <= 30:
            return second
        s1, s2 = self.score(first), self.score(second)
        if s1 <= 2 and s2 >= max(4, 3 * s1):
            return second
        return first


def _batchim(syllable: str, *, rieul_is_open: bool = False) -> bool | None:
    """Whether a Hangul syllable ends in a consonant (None: not Hangul)."""
    if not ("가" <= syllable <= "힣"):
        return None
    final = (ord(syllable) - 0xAC00) % 28
    return final != 0 and not (rieul_is_open and final == 8)


def explanations(row: WordRow, literal: str, eum_of: dict[str, str]) -> dict[str, str]:
    """All four languages, each with the word's meaning when a gloss exists.

    Korean particles follow the sound before them: after the kana reading, ん
    is a final ㄴ (かんげん은, いかん은); after 「surface」 a Korean reader says
    the 한자음, so its last syllable decides (「還元」 환원 → 으로, 「楽隊」 악대
    → 로, ㄹ takes 로). An unknown 한자음 falls back to the neutral (으)로.
    """
    reading, surface = row.reading, row.surface
    topic = "은" if reading.endswith("ん") else "는"
    last = eum_of.get(surface[-1], "")[-1:]
    if not last and row.ko:
        # 収 has no 한자음 in KANJIDIC; the ko gloss usually opens with the
        # Sino-Korean word itself (押収 → 압수).
        head = re.split(r"[,\s]", row.ko)[0]
        if len(head) == len(surface) and all("가" <= ch <= "힣" for ch in head):
            last = head[-1]
    b = _batchim(last, rieul_is_open=True)
    instr = "(으)로" if b is None else ("으로" if b else "로")
    ko_m = f" 뜻은 ‘{row.ko}’입니다." if row.ko else ""
    ja_m = f"「{row.ja}」という意味です。" if row.ja else ""
    zh_m = f"意思是“{row.zh}”。" if row.zh else ""
    en_m = f' and means "{row.en}"' if row.en else ""
    return {
        "ko": f"{reading}{topic} 「{surface}」{instr} 씁니다.{ko_m} "
              f"빈칸에 들어갈 한자는 {literal}입니다.",
        "ja": f"「{reading}」は「{surface}」と書きます。{ja_m}"
              f"空欄に入る漢字は「{literal}」です。",
        "zh": f"{reading} 写作「{surface}」。{zh_m}填入空格的汉字是 {literal}。",
        "en": f"{reading} is written 「{surface}」{en_m}. "
              f"The kanji for the blank is {literal}.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--out", default="sources/kanken_doonkun_questions.jsonl")
    parser.add_argument(
        "--jmdict", default="sources/jmdict.xml",
        help="every JMdict headword counts as a real word when rejecting a "
             "distractor; the shipped word table alone is common words only, "
             "which let 一朝 through as a wrong answer for いっちょう 一□")
    parser.add_argument(
        "--lexicon", default="/tmp/jmlex.json",
        help="optional JSON {surface: [readings]}; every surface counts as a "
             "real word too")
    parser.add_argument(
        "--sentences", default="sources/sentences.csv",
        help="Tatoeba sentences.csv; kanji strings in Japanese sentences count "
             "as attested words (画号, 坑殺 are not JMdict headwords)")
    args = parser.parse_args()

    con = sqlite3.connect(args.db)
    rank_of: dict[str, int] = {}
    for literal, level in con.execute(
            "SELECT k.literal, km.level_label FROM kanji k "
            "JOIN kanken_membership km ON km.kanji_id = k.id"):
        # 準1級/1級 overlap: a kanji's level is its easiest one.
        rank = RANK.get(level, 99)
        rank_of[literal] = min(rank, rank_of.get(literal, 99))
    readings_of: dict[str, tuple[set[str], set[str]]] = defaultdict(
        lambda: (set(), set()))
    for literal, axis, value in con.execute(
            "SELECT k.literal, r.lang_axis, r.value FROM kanji k "
            "JOIN reading r ON r.kanji_id = k.id WHERE r.lang_axis IN ('on','kun')"):
        readings_of[literal][0 if axis == "on" else 1].add(value)

    eum_of: dict[str, str] = {}
    for literal, value in con.execute(
            "SELECT k.literal, r.value FROM kanji k JOIN reading r "
            "ON r.kanji_id = k.id WHERE r.lang_axis = 'eum' ORDER BY r.id"):
        eum_of.setdefault(literal, value)
    glosses: dict[int, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    for word_id, lang, text in con.execute(
            "SELECT word_id, lang, text FROM word_gloss ORDER BY id"):
        glosses[word_id][lang].append(text)
    en_picker = EnglishGlossPicker(
        [g for per in glosses.values() for g in per.get("en", [])])

    def compounds(common: int) -> list[tuple[int, str, str]]:
        return [
            (wid, surface, to_hiragana(reading))
            for wid, surface, reading in con.execute(
                "SELECT id, surface, reading_kana FROM word WHERE is_common = ? "
                "ORDER BY LENGTH(surface), id", (common,))
            if 2 <= len(surface) <= 4 and _all_kanji(surface)
            and not re.search(r"[ァ-ヶ]", reading)
        ]
    common_words = compounds(1)
    # Shipped but untagged JMdict words: only used to top up a level that the
    # common vocabulary cannot fill (2級's 2010 additions have few 熟語).
    other_words = compounds(0)
    all_surfaces = {row[0] for row in con.execute("SELECT surface FROM word")}
    con.close()

    # ── rule 2: which 音読み are standard ──────────────────────────────────
    aligned: dict[tuple[int, int], list[Form]] = {}
    for wid, surface, reading in common_words + other_words:
        segs = segmentations(surface, reading, readings_of)
        for i in range(len(surface)):
            forms = {seg[i] for seg in segs}
            if forms and len({f.slice for f in forms}) == 1:
                aligned[(wid, i)] = sorted(forms, key=lambda f: (f.axis, f.base))
    evidence: dict[tuple[str, str], set[int]] = defaultdict(set)
    surface_of = {wid: surface for wid, surface, _ in common_words + other_words}
    jouyou_word = {wid: all(rank_of.get(ch, 99) <= JOUYOU_MAX for ch in s)
                   for wid, s in surface_of.items()}
    ambiguous: list[tuple[int, str, list[str]]] = []
    for (wid, i), forms in aligned.items():
        if not jouyou_word[wid]:
            continue
        on_forms = [f for f in forms if f.axis == "on"]
        on_bases = sorted({f.base for f in on_forms})
        # KANJIDIC lists サ変 stems as kun (詮 せん.ずる), so a kun form that
        # merely repeats an 音 is not a competing reading.
        kun_rivals = [f for f in forms if f.axis == "kun" and f.base not in on_bases]
        # 危惧 ぐ fits グ as is or ク voiced; the unchanged reading wins.
        plain = sorted({f.base for f in on_forms if f.change == ""})
        if len(on_bases) > 1 and len(plain) == 1:
            on_bases = plain
        if len(on_bases) == 1 and not kun_rivals:
            evidence[(surface_of[wid][i], on_bases[0])].add(wid)
        elif on_bases:
            ambiguous.append((wid, surface_of[wid][i], on_bases))
    for wid, literal, bases in ambiguous:
        best = max(bases, key=lambda b: len(evidence.get((literal, b), ())))
        if evidence.get((literal, best)):
            evidence[(literal, best)].add(wid)
    standard_on: dict[str, set[str]] = defaultdict(set)
    attested_on: dict[str, set[str]] = defaultdict(set)
    for (literal, base), wids in evidence.items():
        attested_on[literal].add(base)
        if len(wids) >= STANDARD_MIN_WORDS:
            standard_on[literal].add(base)

    # Surface slices each kanji's standard 音読み can take, keyed by slice.
    def surface_forms(base: str, change: str) -> set[str]:
        out = {base}
        if change == "sokuon" and base[-1:] in "つちくき" and len(base) >= 2:
            out.add(base[:-1] + "っ")
        if change == "rendaku":
            if base[0] in _VOICE:
                out.add(_VOICE[base[0]] + base[1:])
            if base[0] in _SEMI:
                out.add(_SEMI[base[0]] + base[1:])
        return out

    def homophones_of(slice_: str, change: str) -> list[str]:
        return sorted(
            other for other, bases in standard_on.items()
            if rank_of.get(other, 99) <= JOUYOU_MAX
            and any(slice_ in surface_forms(b, change) for b in bases))

    # ── real-word guard for substitutions ─────────────────────────────────
    if args.jmdict and Path(args.jmdict).exists():
        from lxml import etree
        for _, entry in etree.iterparse(args.jmdict, tag="entry", load_dtd=False,
                                        resolve_entities=False, huge_tree=True):
            all_surfaces.update(k.text for k in entry.iter("keb") if k.text)
            entry.clear()
    if args.lexicon and Path(args.lexicon).exists():
        lexicon = json.loads(Path(args.lexicon).read_text("utf-8"))
        all_surfaces.update(lexicon)
    attested: set[str] = set()
    if args.sentences and Path(args.sentences).exists():
        run = re.compile(r"[㐀-䶿一-鿿]{2,}")
        with open(args.sentences, encoding="utf-8") as fh:
            for line in fh:
                if "\tjpn\t" not in line:
                    continue
                for chunk in run.findall(line.split("\t", 2)[2]):
                    for n in (2, 3, 4):
                        for start in range(len(chunk) - n + 1):
                            attested.add(chunk[start:start + n])

    def is_real(surface: str) -> bool:
        return surface in all_surfaces or surface in attested or surface in KNOWN_REAL

    words_by_literal: dict[str, list[tuple[int, str, str]]] = defaultdict(list)
    for wid, surface, reading in common_words:
        for ch in dict.fromkeys(surface):
            words_by_literal[ch].append((wid, surface, reading))
    extra_by_literal: dict[str, list[tuple[int, str, str]]] = defaultdict(list)
    for wid, surface, reading in other_words:
        for ch in dict.fromkeys(surface):
            extra_by_literal[ch].append((wid, surface, reading))

    rng = random.Random(SEED)
    out: list[dict] = []
    used_surfaces: set[str] = set()
    made_for: Counter[str] = Counter()
    stats: Counter[str] = Counter()
    targets = sorted(
        (literal, LEVEL_ORDER[rank]) for literal, rank in rank_of.items()
        if rank < len(LEVEL_ORDER) and LEVEL_ORDER[rank] in LEVELS)

    def try_word(literal: str, level: str, wid: int, surface: str,
                 reading: str) -> dict | None:
        limit = RANK[level]
        if surface in used_surfaces or surface.count(literal) != 1:
            return None
        if any(rank_of.get(ch, 99) > limit for ch in surface if ch != literal):
            stats["skip: context kanji above level"] += 1
            stats[f"{level} skip: context kanji above level"] += 1
            return None
        index = surface.index(literal)
        forms = slice_at(surface, reading, index, readings_of)
        if forms is None:
            stats["skip: reading not aligned"] += 1
            stats[f"{level} skip: reading not aligned"] += 1
            return None
        # The answer's own reading only needs this common word as evidence
        # (挨拶 is the one common word with 挨 アイ); distractors need two.
        used = [f for f in forms if f.axis == "on"  and f.base in attested_on[literal]]
        if not used:
            stats["skip: blank is not a standard 音読み"] += 1
            stats[f"{level} skip: blank is not a standard 音読み"] += 1
            return None
        slice_ = forms[0].slice
        used.sort(key=lambda f: f.change != "")
        change = used[0].change
        pool = [c for c in homophones_of(slice_, change)
                if c != literal and c not in surface]
        safe = [c for c in pool
                if not is_real(surface[:index] + c + surface[index + 1:])]
        tiers: list[list[str]] = []
        for stretch in range(LEVEL_STRETCH + 1):
            tier = [c for c in safe if (rank_of[c] <= limit if stretch == 0
                                        else rank_of[c] == min(limit + stretch,
                                                               JOUYOU_MAX))]
            rng.shuffle(tier)
            tiers.append(tier)
        # In-level first; harder tiers only fill what the easier ones lack.
        chosen = list(dict.fromkeys(c for tier in tiers for c in tier))
        if len(chosen) < 3:
            reach = min(limit + LEVEL_STRETCH, JOUYOU_MAX)
            why = ("fewer than 3 exact homophones"
                   if sum(rank_of[c] <= reach for c in pool) < 3
                   else "substitutions spell real words")
            stats[f"skip: {why}"] += 1
            stats[f"{level} skip: {why}"] += 1
            return None
        per = glosses[wid]
        row = WordRow(
            surface, reading,
            en=en_picker.pick(per.get("en", [])),
            ko=clean_gloss((per.get("ko") or [None])[0], limit=30),
            ja=clean_gloss((per.get("ja") or [None])[0], limit=30),
            zh=clean_gloss((per.get("zh") or [None])[0], limit=20))
        q = build_orthography_question(
            row, literal=literal, level=level, kind="doonkun",
            candidates=chosen, real_surfaces=all_surfaces, rng=rng,
            shuffle_candidates=False)
        if q is not None:
            # Written here rather than by the shared builder so the particle
            # can follow the 한자음 and the meaning is always in all four.
            q["explanations"] = explanations(row, literal, eum_of)
            stats["stretched distractors"] += any(
                rank_of[c] > limit for c in q["options"])
        return q

    def run_pass(cap: int, levels: set[str], pool=None) -> None:
        pool = words_by_literal if pool is None else pool
        for literal, level in targets:
            if level not in levels:
                continue
            for wid, surface, reading in pool.get(literal, []):
                if made_for[literal] >= cap:
                    break
                q = try_word(literal, level, wid, surface, reading)
                if q is not None:
                    out.append(q)
                    used_surfaces.add(surface)
                    made_for[literal] += 1

    run_pass(PER_KANJI, set(LEVELS))
    per_level = Counter(q["level"] for q in out)
    short = {lv for lv in LEVELS if per_level[lv] < LEVEL_TARGET}
    if short:
        run_pass(PER_KANJI_TOPUP, short)
        per_level = Counter(q["level"] for q in out)
        still = {lv for lv in short if per_level[lv] < LEVEL_TARGET}
        if still:
            run_pass(PER_KANJI_TOPUP, still, extra_by_literal)
    # Stable order: by level then literal, the way the bank was always laid out.
    out.sort(key=lambda q: (q["literal"],))

    Path(args.out).write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")
    per_level = Counter(q["level"] for q in out)
    print(f"wrote {len(out)} 同音・同訓異字 questions → {args.out}")
    for level in LEVELS:
        print(f"  {level}: {per_level[level]}"
              f"{'  (topped up)' if level in short else ''}")
    no_q = sum(1 for lit, lv in targets if made_for[lit] == 0)
    print(f"  kanji with no question: {no_q} of {len(targets)}")
    for key, value in sorted(stats.items()):
        print(f"  {key}: {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
