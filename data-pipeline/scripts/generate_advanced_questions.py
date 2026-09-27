#!/usr/bin/env python3
"""Generate the 準1級/1級 exam bank from a built kanji.sqlite.

Run after a build, then rebuild so the questions are ingested:

    python -m kanjipipe.build_db --out out/kanji.sqlite
    python scripts/generate_advanced_questions.py
    python -m kanjipipe.build_db --out out/kanji.sqlite

The two-pass shape is deliberate: the generator needs the vocabulary and
readings the build produces, and the build needs the questions the generator
produces. The intermediate JSONL is committed, so a plain build stays
reproducible without re-running this.

The output is deterministic (fixed seed, no hash-order dependence). Check it
with check_question_batch.py, check_ambiguity.py (--lexicon with all of
JMdict) and validate_advanced_questions.py.

JMdict itself (sources/jmdict.xml) is read as well, because the vocabulary
table keeps one reading per entry: the *answer* should be the standard reading
(肋骨 ろっこつ, not あばらぼね) and *no* reading JMdict lists may be offered as
a wrong one.

Rules, from reviewing samples of earlier output:

* 読み distractors differ from the answer only in the target kanji's slice of
  the reading — the other kanji's reading, the okurigana and the
  reduplication stay — so the easy part of the word gives nothing away.
  Replacement slices come from real words sharing the rest of the word
  (銃声 じゅう|せい for 砧声 ちん|せい), the target's other readings, and
  look-alike kanji. Only kanji where no word can be aligned fall back to
  whole-word distractors, and those still keep the kana frame.
* 書き取り distractors are 準1級/1級 kanji, look-alikes first; at most one
  常用 kanji, and only a look-alike. Never a variant of the answer, a
  compatibility ideograph, a character already in the word, or a substitution
  that spells any JMdict word.
* Proper nouns, titles, companies, species entries, kana-in-the-middle
  surfaces and non-四字熟語 four-kanji strings are skipped; one question per
  (surface, blank).
"""
from __future__ import annotations

import argparse
import io
import json
import math
import random
import re
import sqlite3
import sys
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from kanjipipe.questions import (  # noqa: E402
    NAME_TAGS,
    PROPER_GLOSS,
    STALE_TAGS,
    WORK_GLOSS,
    ReadingInfo,
    WordRow,
    _is_kana,
    _is_katakana,
    _segment_near_misses,
    align_reading,
    build_orthography_question,
    build_reading_question,
    fits_kana_frame,
    is_compat_ideograph,
    is_hira,
    is_kanji,
    is_name_like,
    is_species_like,
    kanji_reading_table,
    kata_to_hira,
    load_jmdict_lexicon,
    reading_distractors,
    reading_infos,
    surface_shape_ok,
    target_frame,
)

ADVANCED = ("準1級", "1級")
# Enough for a full 大問 without letting one prolific kanji dominate the draw.
PER_KANJI_PER_KIND = 3
SEED = 20260728
_VOICED = set("がぎぐげござじずぜぞだぢづでどばびぶべぼ")
_HANDAKU = set("ぱぴぷぺぽ")
_HANDAKU_OF = dict(zip("はひふへほ", "ぱぴぷぺぽ"))
_DAKU = str.maketrans(dict(zip("かきくけこさしすせそたちつてとはひふへほ",
                               "がぎぐげござじずぜぞだぢづでどばびぶべぼ")))
_VARIANT_FIELDS = {"kSemanticVariant", "kZVariant", "kSpecializedSemanticVariant",
                   "kTraditionalVariant", "kSimplifiedVariant", "kSpoofingVariant"}


def load_unihan_variants(path: Path) -> dict[str, set[str]]:
    """literal → every Unihan variant of it, both directions, two hops.

    蚯螾 for 蚯蚓 or 瓮 for 甕 is the same word in another glyph; offering the
    variant as a wrong answer makes the question wrong."""
    direct: dict[str, set[str]] = defaultdict(set)
    if not path.exists():
        return direct
    with zipfile.ZipFile(path) as archive, archive.open("Unihan_Variants.txt") as raw:
        for line in io.TextIOWrapper(raw, encoding="utf-8"):
            if line.startswith("#") or not line.strip():
                continue
            code, fld, value = line.rstrip("\n").split("\t", 2)
            if fld not in _VARIANT_FIELDS:
                continue
            a = chr(int(code[2:], 16))
            for other in re.findall(r"U\+([0-9A-F]+)", value):
                b = chr(int(other, 16))
                direct[a].add(b)
                direct[b].add(a)
    closed: dict[str, set[str]] = defaultdict(set)
    for a, bs in direct.items():
        closed[a] = set(bs) | {c for b in bs for c in direct.get(b, ())}
        closed[a].discard(a)
    return closed


class Data:
    def __init__(self, db: Path, jmdict: Path, lexicon: Path | None, unihan: Path):
        con = sqlite3.connect(db)
        self.level = dict(con.execute("SELECT literal, kanken_level FROM kanji"))
        self.advanced = {k for k, v in self.level.items() if v in ADVANCED}
        self.strokes = dict(con.execute("SELECT literal, stroke_count FROM kanji"))
        self.radical_of = dict(con.execute(
            "SELECT literal, radical FROM kanji WHERE radical IS NOT NULL"))
        self.by_radical: dict[int, list[str]] = defaultdict(list)
        for literal, radical in sorted(self.radical_of.items()):
            self.by_radical[radical].append(literal)
        self.similar: dict[str, list[str]] = defaultdict(list)
        for a, b in con.execute("""
                SELECT ka.literal, kb.literal FROM kanji_similar s
                JOIN kanji ka ON ka.id = s.kanji_id
                JOIN kanji kb ON kb.id = s.similar_id
                ORDER BY s.kanji_id, s.rank"""):
            self.similar[a].append(b)
        self.table = kanji_reading_table(con.execute("""
            SELECT k.literal, r.lang_axis, r.value FROM reading r
            JOIN kanji k ON k.id = r.kanji_id
            WHERE r.lang_axis IN ('on', 'kun')"""))
        # Readings of 準1級/1級 kanji by (axis, length): the last-resort
        # replacement slice when nothing sharper exists.
        self.generic_slices: dict[tuple[str, int], list[str]] = defaultdict(list)
        for literal in sorted(self.table):
            if self.level.get(literal) not in ADVANCED:
                continue
            for seg, axis in self.table[literal]:
                axis = "kun" if axis == "kun_okuri" else axis
                if seg not in self.generic_slices[(axis, len(seg))]:
                    self.generic_slices[(axis, len(seg))].append(seg)
        self.axis_of: dict[tuple[str, str], str] = {}
        for literal, pairs in self.table.items():
            for seg, axis in pairs:
                self.axis_of.setdefault((literal, seg), axis)

        glosses: dict[int, dict[str, str]] = defaultdict(dict)
        for word_id, lang, text in con.execute(
                "SELECT word_id, lang, text FROM word_gloss ORDER BY id"):
            if lang == "en" and "en" in glosses[word_id]:
                # English rows are one gloss each; keep the first two.
                if "; " not in glosses[word_id]["en"]:
                    glosses[word_id]["en"] += "; " + text
                continue
            glosses[word_id].setdefault(lang, text)
        self.db_rows: dict[str, list[tuple[str, dict[str, str]]]] = defaultdict(list)
        for word_id, surface, reading in con.execute(
                "SELECT id, surface, reading_kana FROM word ORDER BY id"):
            self.db_rows[surface].append((reading, glosses.get(word_id, {})))
        self.words_by_literal: dict[str, list[str]] = defaultdict(list)
        for surface, literal in con.execute("""
            SELECT w.surface, k.literal
            FROM word w
            JOIN word_kanji wk ON wk.word_id = w.id
            JOIN kanji k ON k.id = wk.kanji_id
            WHERE k.kanken_level IN (?, ?)
            ORDER BY w.is_common DESC, LENGTH(w.surface), w.id
            """, ADVANCED):
            if surface not in self.words_by_literal[literal]:
                self.words_by_literal[literal].append(surface)
        self.yoji = {y for (y,) in con.execute("SELECT yoji FROM yojijukugo")}
        con.close()

        print("parsing JMdict…", file=sys.stderr)
        self.lex = load_jmdict_lexicon(jmdict)
        # Every spelling → readings: JMdict, the vocabulary table, and any
        # wider lexicon handed in (the ambiguity checker's).
        self.spellings: dict[str, set[str]] = defaultdict(set)
        for surface, readings in self.lex.readings.items():
            self.spellings[surface] |= readings
        for surface, rows in self.db_rows.items():
            self.spellings[surface] |= {kata_to_hira(r) for r, _ in rows}
        if lexicon and lexicon.exists():
            for surface, readings in json.loads(lexicon.read_text("utf-8")).items():
                self.spellings[surface] |= {kata_to_hira(r) for r in readings}
        self.variants = load_unihan_variants(unihan)
        self._infos: dict[str, list[ReadingInfo]] = {}
        print("indexing reading frames…", file=sys.stderr)
        self._index_frames()

    def infos(self, surface: str) -> list[ReadingInfo]:
        if surface not in self._infos:
            self._infos[surface] = reading_infos(self.lex, surface)
        return self._infos[surface]

    # ── reading frames ──────────────────────────────────────────────────
    def _index_frames(self) -> None:
        """For every aligned JMdict word, what each kanji position reads as
        given the rest of the word. 砧声 ちん|せい then finds 銃声 じゅう|せい,
        名声 めい|せい: real readings that keep 声=せい."""
        self.seg_freq: Counter = Counter()
        self.frame_written: dict[tuple, list[str]] = defaultdict(list)
        self.frame_read: dict[tuple, list[str]] = defaultdict(list)
        self.frame_redup: dict[tuple, list[str]] = defaultdict(list)
        for surface, entries in self.lex.entries_by_keb.items():
            if not 2 <= len(surface) <= 4 or not surface_shape_ok(surface, True):
                continue
            if all(any(s.misc & NAME_TAGS for s in e.senses[:1]) for e in entries):
                continue
            for reading in sorted(self.lex.readings.get(surface, ())):
                aligned = align_reading(surface, reading, self.table)
                if aligned is None:
                    continue
                segs = [s for s, _ in aligned]
                pattern = "".join(ch if is_hira(ch) else "*" for ch in surface)
                for i, (ch, (seg, base)) in enumerate(zip(surface, aligned)):
                    if base is not None:
                        self.seg_freq[(ch, base)] += 1
                    if not is_kanji(ch) or ch == "々":
                        continue
                    if i + 1 < len(surface) and surface[i + 1] in ("々", ch):
                        # 畳語 (滔々 とう|とう): what doubled slices sound like.
                        if segs[i + 1] == seg:
                            pre, post = "".join(segs[:i]), "".join(segs[i + 2:])
                            self.frame_redup[(len(surface), i, pre, post)].append(seg)
                        continue
                    pre, post = "".join(segs[:i]), "".join(segs[i + 1:])
                    self.frame_written[(surface[:i], surface[i + 1:], pre, post)].append(seg)
                    self.frame_read[(pattern, i, pre, post)].append(seg)

    # ── answer choice ───────────────────────────────────────────────────
    def standard_reading(self, surface: str) -> tuple[ReadingInfo, str] | None:
        """The reading a native reader would give: common, not search-only,
        not archaic, not a suffix-only sense (搦み がらみ), and aligned with
        the kanji's usual readings (粗鬆 そしょう as in 骨粗鬆症)."""
        best = None
        for info in self.infos(surface):
            if info.affix_only:
                continue
            hira = kata_to_hira(info.reading)
            if not _is_kana(hira):
                continue
            score = 0.0
            if "sK" in info.keb_tags:
                score -= 6
            if info.keb_tags & {"rK", "oK", "iK"}:
                score -= 3
            if info.reb_tags & {"ok", "ik", "rk", "sk"}:
                score -= 4
            if info.common:
                score += 3
            if info.misc & STALE_TAGS:
                score -= 2
            if _is_katakana(info.reading) and info.has_hiragana_sibling:
                continue  # 餃子: ぎょうざ, never ギョーザ turned into ぎょーざ
            if _is_katakana(info.reading) and info.loanword:
                score -= 4  # 骰子: さいころ, not the mahjong loan シャイツ
            aligned = align_reading(surface, hira, self.table)
            if aligned is not None:
                # How often each slice reads that way in *other* words (the
                # word itself counts once per reading, so it cannot decide).
                freqs = [max(0, self.seg_freq[(ch, base)] - 1) for ch, (_, base)
                         in zip(surface, aligned) if base is not None]
                score += 1 + (0.4 * sum(math.log1p(f) for f in freqs) / len(freqs)
                              if freqs else 0)
                kanji_axes = [self.axis_of.get((ch, base)) for ch, (_, base)
                              in zip(surface, aligned) if base is not None]
                if len(kanji_axes) >= 2 and all(a == "on" for a in kanji_axes):
                    score += 0.5  # 吝嗇 りんしょく over the 熟字訓 けち
            if any(kata_to_hira(r) == hira for r, _ in self.db_rows.get(surface, [])):
                score += 0.3
            if best is None or score > best[0]:
                best = (score, info, hira)
        if best is None:
            return None
        return best[1], best[2]

    def glosses_for(self, surface: str, reading: str) -> dict[str, str]:
        rows = self.db_rows.get(surface, [])
        for r, g in rows:
            if kata_to_hira(r) == reading:
                return g
        # Same JMdict entry, other reading (肋骨: the row is あばらぼね).
        for entry in self.lex.entries_by_keb.get(surface, []):
            rebs = {kata_to_hira(reb) for reb, *_ in entry.rebs}
            if reading in rebs:
                for r, g in rows:
                    if kata_to_hira(r) in rebs:
                        return g
        return {}

    def usable(self, surface: str, relaxed: bool) -> tuple[ReadingInfo, str, WordRow] | None:
        """Exam vocabulary: shape, not a name, not a species entry, 四字 only
        when it is a 四字熟語. Returns the standard reading and glossed row."""
        if not 2 <= len(surface) <= 4 or not surface_shape_ok(surface, relaxed):
            return None
        infos = self.infos(surface)
        if not infos or all("sK" in i.keb_tags for i in infos):
            # Search-only spellings (番瀝青 for ペンキ) are not how anyone
            # writes the word.
            return None
        chosen = self.standard_reading(surface)
        if chosen is None:
            return None
        info, hira = chosen
        g = self.glosses_for(surface, hira)
        # The ko/ja/zh glosses were written from the vocabulary row's English,
        # so that English keeps the four languages saying the same thing;
        # JMdict's own pick is the fallback, and replaces a work title.
        en = g.get("en")
        if not en or WORK_GLOSS.search(en) or PROPER_GLOSS.search(en):
            en = info.en_gloss or en
        if is_name_like(infos, en):
            return None
        if not relaxed and is_species_like(infos, [en or "", info.en_gloss or ""]):
            return None
        if len(surface) == 4 and all(is_kanji(c) for c in surface):
            is_yoji = (surface in self.yoji
                       or any("yoji" in i.all_misc or i.common for i in infos))
            # Relaxed: a compound of two real words (花卉+園芸) is still
            # vocabulary, just not a 四字熟語.
            two_words = (relaxed and surface[:2] in self.lex.entries_by_keb
                         and surface[2:] in self.lex.entries_by_keb)
            if not (is_yoji or two_words):
                return None
        word = WordRow(surface, hira, en=en, ko=g.get("ko"), ja=g.get("ja"),
                       zh=g.get("zh"))
        return info, hira, word

    def surfaces_for(self, literal: str) -> list[str]:
        # Two- and three-kanji compounds are what the paper actually asks
        # about, so try those first (stable sort keeps common words ahead).
        return sorted(self.words_by_literal.get(literal, []),
                      key=lambda s: abs(len(s) - 2))

    # ── 読み distractors ────────────────────────────────────────────────
    def _context(self, alt: str, target_seg: str) -> list[str]:
        """Give a replacement slice the same sandhi the target's slice shows:
        voiced when the target is voiced (連濁), half-voiced when it is,
        geminated when it is."""
        outs = [alt]
        first = target_seg[0]
        if first in _HANDAKU:
            outs = [_HANDAKU_OF[alt[0]] + alt[1:]] if alt[0] in _HANDAKU_OF else outs
        elif first in _VOICED:
            voiced = alt[0].translate(_DAKU)
            outs = [voiced + alt[1:]] if voiced != alt[0] else outs
        if target_seg.endswith("っ"):
            outs = [o[:-1] + "っ" for o in outs if len(o) >= 2 and o[-1] in "つちくきり"]
        return outs

    def aligned_distractors(self, surface: str, reading: str, literal: str,
                            rng: random.Random) -> list[str] | None:
        frame = target_frame(surface, reading, literal, self.table)
        if frame is None:
            return None
        segs, slots = frame
        first = min(slots)
        target = segs[first]
        after = max(slots) + 1
        followed_by_kana = after < len(surface) and is_hira(surface[after])
        # Which reading the target slice is: an 音読み slice gets 音読み
        # look-alikes; an unaligned (wildcard) slice is treated as 音.
        aligned = align_reading(surface, reading, self.table)
        base = aligned[first][1] if aligned else None
        target_axis = self.axis_of.get((literal, base), "on") if base else "on"
        redup = len(slots) > 1
        # Before okurigana only verb/adjective stems make sense (なぶ|る, not
        # どう|る or the noun うがい|ぐ);
        # inside a compound a bare verb stem (か of か.む) reads as noise.
        if followed_by_kana:
            own_axes = look_axes = {"kun_okuri"}
        else:
            look_axes = {target_axis} if target_axis != "kun_okuri" else {"kun"}
            # The kanji's other reading is the classic 湯桶/重箱 trap, except
            # in a 畳語 (滔々), where a kun noun doubled (あたまあたま) is noise.
            own_axes = look_axes if redup else {"on", "kun"}

        own = []
        for b, axis in self.table.get(literal, []):
            if axis in own_axes:
                own.extend(self._context(b, target))
        look = []
        for other in self.similar.get(literal, [])[:10]:
            for b, axis in self.table.get(other, []):
                if axis in look_axes:
                    look.extend(self._context(b, target))
        frame_alts: list[str] = []
        if len(slots) == 1:
            pre = "".join(segs[:first])
            post = "".join(segs[first + 1:])
            pattern = "".join(ch if is_hira(ch) else "*" for ch in surface)
            written = self.frame_written.get(
                (surface[:first], surface[first + 1:], pre, post), [])
            read = self.frame_read.get((pattern, first, pre, post), [])
            for alt in list(dict.fromkeys(written)) + list(dict.fromkeys(read)):
                if abs(len(alt) - len(target)) <= 1:
                    frame_alts.append(alt)
            # Written frames (same neighbouring kanji) first, then reading
            # frames; cap so a common frame does not swamp the other sources.
            frame_alts = list(dict.fromkeys(frame_alts))[:40]
        elif slots == {first, first + 1}:
            pre = "".join(segs[:first])
            post = "".join(segs[first + 2:])
            frame_alts = [alt for alt in dict.fromkeys(
                self.frame_redup.get((len(surface), first, pre, post), []))
                if abs(len(alt) - len(target)) <= 1][:40]
        banned = self.spellings.get(surface, set()) | {reading}
        generic_axis = "kun" if followed_by_kana else target_axis
        generic = self.generic_slices.get((generic_axis, len(target)), [])
        generic = [self._context(g, target)[0] for g in
                   rng.sample(generic, min(30, len(generic)))
                   if self._context(g, target)]
        out = reading_distractors(
            segs, slots, surface,
            alternatives={"own": own, "lookalike": look, "frame": frame_alts,
                          "near": _segment_near_misses(target),
                          "generic": generic},
            banned=banned, rng=rng)
        if out is None:
            return None
        if not all(fits_kana_frame(surface, reading, d) for d in out):
            return None
        return out

    def fallback_pool(self, surface: str, reading: str, literal: str) -> list[str]:
        """Whole-word readings for words whose reading will not align
        (熟字訓): words sharing a non-target character in the same position,
        then any word of the same shape — always within the kana frame."""
        n = len(surface)
        pool: list[str] = []
        for s2, readings in self._shape_index.get(n, {}).items():
            if s2 == surface:
                continue
            shares = any(a == b and a != literal and not is_hira(a)
                         for a, b in zip(surface, s2))
            if shares:
                pool.extend(readings)
        pool = [r for r in pool if fits_kana_frame(surface, reading, r)]
        if len(pool) < 12:
            kanji_count = sum(1 for c in surface if not is_hira(c))
            pool.extend(r for r in self._by_shape.get((kanji_count, len(reading)), [])
                        if fits_kana_frame(surface, reading, r))
        return pool

    def build_fallback_indexes(self) -> None:
        self._shape_index: dict[int, dict[str, list[str]]] = defaultdict(dict)
        self._by_shape: dict[tuple[int, int], list[str]] = defaultdict(list)
        for surface in self.db_rows:
            if not surface_shape_ok(surface, True) or not 2 <= len(surface) <= 4:
                continue
            infos = self.infos(surface)
            if not infos or is_name_like(infos):
                continue
            # Loanword readings (ちべっと, ふぃりぴん) are never convincing.
            readings = sorted({kata_to_hira(i.reading) for i in infos
                               if _is_kana(kata_to_hira(i.reading))
                               and not self.is_foreign(i, i.en_gloss)})
            self._shape_index[len(surface)][surface] = readings
            kc = sum(1 for c in surface if not is_hira(c))
            for r in readings:
                self._by_shape[(kc, len(r))].append(r)

    # ── 書き取り candidates ──────────────────────────────────────────────
    def ortho_candidates(self, literal: str, rng: random.Random) -> list[str]:
        banned = self.variants.get(literal, set()) | {literal}

        def ok(c: str) -> bool:
            return (c not in banned and c in self.level
                    and not is_compat_ideograph(c))

        look = [c for c in self.similar.get(literal, []) if ok(c)]
        adv_look = [c for c in look if c in self.advanced]
        joyo_look = [c for c in look[:6] if c not in self.advanced
                     and self.level.get(c)]
        adv_rad = [c for c in self.by_radical.get(self.radical_of.get(literal), [])
                   if ok(c) and c in self.advanced]
        strokes = self.strokes.get(literal) or 0
        adv_strokes = [c for c in self.advanced if ok(c)
                       and abs((self.strokes.get(c) or 0) - strokes) <= 1]
        top = adv_look[:8]
        rng.shuffle(top)
        rng.shuffle(adv_rad)
        adv_strokes.sort()
        rng.shuffle(adv_strokes)
        ordered = top[:2] + adv_rad[:12] + top[2:] + adv_look[8:]
        ordered += joyo_look[:1] + adv_strokes[:30]
        return list(dict.fromkeys(ordered))

    @staticmethod
    def is_foreign(info: ReadingInfo, en: str | None) -> bool:
        """A katakana reading that is a loanword or foreign name (珈琲
        コーヒー, 暹羅 シャム), as opposed to a native word JMdict merely
        prints in katakana (轡虫 クツワムシ)."""
        r = info.reading
        if not any("ァ" <= c <= "ヿ" for c in r):
            return False
        if any(is_hira(c) for c in r):
            return True  # モーはい, リーぞく: half loanword
        if info.has_hiragana_sibling:
            return False
        return (info.loanword or "ateji" in info.keb_tags
                or any(c in "ーヴァィゥェォヮヵヶ" for c in r)
                or bool(en and en[:1].isupper()))

    def reading_answer_ok(self, info: ReadingInfo, en: str | None) -> bool:
        """読み answers are hiragana: a loanword's katakana reading turned
        into すいす or こーひー is not an answer anyone writes."""
        return not self.is_foreign(info, en)

    def ortho_prompt_reading(self, surface: str, info: ReadingInfo, hira: str,
                             en: str | None) -> str:
        """Hiragana, except a loanword (瑞西 スイス) keeps its katakana."""
        return info.reading if self.is_foreign(info, en) else hira


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--jmdict", default="sources/jmdict.xml")
    parser.add_argument("--lexicon", default=None,
                        help="optional JSON {surface: [readings]} merged into the "
                             "forbidden-reading/spelling sets")
    parser.add_argument("--unihan", default="sources/Unihan.zip")
    parser.add_argument("--out", default="sources/kanken_advanced_questions.jsonl")
    args = parser.parse_args()

    data = Data(Path(args.db), Path(args.jmdict),
                Path(args.lexicon) if args.lexicon else None, Path(args.unihan))
    data.build_fallback_indexes()
    rng = random.Random(SEED)
    db_surfaces = set(data.db_rows)

    out: list[dict] = []
    seen_surfaces: set[str] = set()          # 読み: one question per word
    seen_ortho: set[tuple[str, int]] = set()  # 書き取り: one per (word, blank)
    stats: Counter = Counter()
    usable_cache: dict[tuple[str, bool], tuple | None] = {}

    def usable(surface: str, relaxed: bool):
        key = (surface, relaxed)
        if key not in usable_cache:
            usable_cache[key] = data.usable(surface, relaxed)
        return usable_cache[key]

    made = {lit: Counter() for lit in data.advanced}

    def try_kanji(literal: str, relaxed: bool, want: dict[str, bool]) -> None:
        """Add at most one 読み and one 書き取り for ``literal``."""
        level = data.level[literal]
        got = {"reading": False, "orthography": False}
        for surface in data.surfaces_for(literal):
            if all(got[k] or not want[k] for k in got):
                return
            u = usable(surface, relaxed)
            if u is None:
                continue
            info, hira, word = u
            if (want["reading"] and not got["reading"] and surface not in seen_surfaces
                    and data.reading_answer_ok(info, word.en)):
                forbidden = data.spellings.get(surface, set())
                ds = data.aligned_distractors(surface, hira, literal, rng)
                q = None
                if ds is not None:
                    q = build_reading_question(
                        word, literal=literal, level=level, other_readings=[],
                        forbidden=forbidden, rng=rng, distractors=ds)
                    tag = "reading_aligned"
                elif relaxed:
                    pool = data.fallback_pool(surface, hira, literal)
                    rng.shuffle(pool)
                    q = build_reading_question(
                        word, literal=literal, level=level,
                        other_readings=pool[:60], forbidden=forbidden, rng=rng)
                    tag = "reading_fallback"
                if q is not None:
                    out.append(q)
                    seen_surfaces.add(surface)
                    made[literal]["reading"] += 1
                    got["reading"] = True
                    stats[tag] += 1
                    if relaxed:
                        stats["reading_relaxed"] += 1
            if (want["orthography"] and not got["orthography"]
                    and surface.count(literal) == 1):
                key = (surface, surface.index(literal))
                if key in seen_ortho:
                    continue
                prompt_reading = data.ortho_prompt_reading(surface, info, hira, word.en)
                ortho_word = WordRow(surface, prompt_reading, en=word.en,
                                     ko=word.ko, ja=word.ja, zh=word.zh)
                q = build_orthography_question(
                    ortho_word, literal=literal, level=level,
                    candidates=data.ortho_candidates(literal, rng),
                    real_surfaces=db_surfaces,
                    reading_spellings=data.spellings,
                    shuffle_candidates=False, rng=rng)
                if q is not None:
                    out.append(q)
                    seen_ortho.add(key)
                    made[literal]["orthography"] += 1
                    got["orthography"] = True
                    if relaxed:
                        stats["ortho_relaxed"] += 1

    # Round-robin over kanji, one item per kind per round: 咀嚼 is vocabulary
    # for both 咀 and 嚼, and letting 咀 take all three of its words first
    # would leave 嚼 with none.
    literals = sorted(data.advanced)
    # Scarcest first: a kanji whose only word is 阮咸 must get it before 咸,
    # which has others to choose from.
    scarcity = {lit: sum(1 for s in data.surfaces_for(lit) if usable(s, False))
                for lit in literals}
    for _round in range(PER_KANJI_PER_KIND):
        for literal in sorted(literals, key=lambda lit: (scarcity[lit], lit)):
            try_kanji(literal, False, {k: made[literal][k] < PER_KANJI_PER_KIND
                                       for k in ("reading", "orthography")})
    # Relaxed pass, only for a kind a kanji still has nothing of: species
    # entries, two-word four-kanji compounds, inner okurigana (包み釦) and
    # whole-word fallback 読み distractors.
    for literal in literals:
        want = {k: made[literal][k] == 0 for k in ("reading", "orthography")}
        if any(want.values()):
            try_kanji(literal, True, want)
    for literal in literals:
        if not data.words_by_literal.get(literal):
            stats["kanji_without_words"] += 1
        elif not made[literal]:
            stats["kanji_with_words_but_no_question"] += 1
        stats["reading"] += made[literal]["reading"]
        stats["orthography"] += made[literal]["orthography"]

    out_path = Path(args.out)
    out_path.write_text(
        "\n".join(json.dumps(q, ensure_ascii=False) for q in out) + "\n",
        encoding="utf-8")

    covered = len({q["literal"] for q in out})
    print(f"wrote {len(out)} questions → {out_path}")
    print(f"  reading={stats['reading']} (aligned {stats['reading_aligned']}, "
          f"fallback {stats['reading_fallback']}, relaxed {stats['reading_relaxed']}) orthography={stats['orthography']} "
          f"(relaxed {stats['ortho_relaxed']})")
    print(f"  advanced kanji covered: {covered}/{len(data.advanced)}")
    print(f"  no vocabulary at all: {stats['kanji_without_words']}")
    print(f"  had vocabulary but nothing safe: "
          f"{stats['kanji_with_words_but_no_question']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
