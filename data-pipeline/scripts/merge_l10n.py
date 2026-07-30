#!/usr/bin/env python3
"""Merge translated l10n batches into their source files, validating first.

A mistranslation reads perfectly well and is only caught by someone who knows
the language, so the checks here are about the things that *are* mechanically
checkable — and every one of them caught a real batch defect at least once:

* the id / 四字熟語 must exist, and must actually have been missing that language
  (a batch that renumbers itself silently overwrites correct data)
* the text must be in the right script — a "Korean" gloss that is still the
  English one, or a "Chinese" one written in kana, is the common agent slip
* nothing may be blank, and nothing may be the untouched English source

Latin letters are allowed in small amounts: 「H₂O」, 「600g」 and 「CD」 are the
right answer in every language, and banning them rejected 121 correct glosses
when this rule was first written. Three or more Latin letters in a row is the
line that separates those from an untranslated phrase.

    python scripts/merge_l10n.py words batch1.json batch2.json --write
    python scripts/merge_l10n.py sentences --lang ko batch.json --write
    python scripts/merge_l10n.py yoji batch.json --write
"""
from __future__ import annotations

import argparse
import json
import re
import sqlite3
import sys
from pathlib import Path

WORD_KO = Path("sources/word_glosses_ko.jsonl")
WORD_JAZH = Path("sources/word_glosses_jazh.jsonl")
SENTENCE_GLOSSES = Path("sources/sentence_glosses.jsonl")

LATIN_RUN = re.compile(r"[A-Za-z]{3,}")


def _has(text: str, lo: str, hi: str) -> bool:
    return any(lo <= ch <= hi for ch in text)


def has_hangul(t: str) -> bool:
    return _has(t, "가", "힣")


def has_kana(t: str) -> bool:
    return _has(t, "぀", "ゟ") or _has(t, "゠", "ヿ")


def has_han(t: str) -> bool:
    return _has(t, "一", "鿿")


def script_problem(lang: str, text: str) -> str | None:
    if not text or not text.strip():
        return "blank"
    if lang == "ko":
        if not has_hangul(text):
            return "no hangul — looks untranslated"
        if has_kana(text):
            return "contains kana"
    elif lang == "ja":
        # An all-kanji Japanese gloss is normal (「学問の道」has no kana), so the
        # only reliable signal is Hangul, or a run of Latin.
        if has_hangul(text):
            return "contains hangul"
        if not (has_kana(text) or has_han(text)):
            return "neither kana nor kanji"
    elif lang == "zh":
        if has_hangul(text):
            return "contains hangul"
        if has_kana(text):
            return "contains kana"
        if not has_han(text):
            return "no han characters"
    elif lang == "en":
        if has_hangul(text) or has_kana(text):
            return "not English"
    if lang != "en" and LATIN_RUN.search(text) and not has_han(text) \
            and not has_hangul(text) and not has_kana(text):
        return "looks like untranslated English"
    return None


def load_word_file(path: Path) -> dict[tuple[str, str], dict]:
    """Word-gloss files are keyed by (surface, reading) — see merge_words."""
    out: dict[tuple[str, str], dict] = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                entry = json.loads(line)
                out[(entry["surface"], entry["reading"])] = entry
    return out


def read_batches(paths: list[str]) -> list[dict]:
    items: list[dict] = []
    for p in paths:
        text = Path(p).read_text(encoding="utf-8")
        parsed = json.loads(text) if text.lstrip().startswith("[") else [
            json.loads(l) for l in text.splitlines() if l.strip()]
        items.extend(parsed)
    return items


def merge_words(conn: sqlite3.Connection, items: list[dict], write: bool) -> int:
    """Merge word glosses, keyed by surface + kana reading.

    Not by word id: ids are autoincrement rowids and move whenever the
    vocabulary set changes. Adding 117 kanji widened the JMdict filter and
    shifted 4,386 of them, which under the old id keying would have silently
    re-pointed every gloss after the shift.
    """
    known: set[tuple[str, str]] = set()
    for surface, reading in conn.execute("SELECT surface, reading_kana FROM word"):
        known.add((surface, reading))
    already: set[tuple[str, str]] = set()
    for surface, reading in conn.execute(
        "SELECT DISTINCT w.surface, w.reading_kana FROM word w "
        "JOIN word_gloss g ON g.word_id = w.id WHERE g.lang = 'ko'"
    ):
        already.add((surface, reading))

    ko = load_word_file(WORD_KO)
    jazh = load_word_file(WORD_JAZH)
    problems: list[str] = []
    staged_ko: dict[tuple[str, str], dict] = {}
    staged_jazh: dict[tuple[str, str], dict] = {}
    skipped_present = 0
    for i, item in enumerate(items):
        surface, reading = item.get("surface"), item.get("reading")
        tag = f"[{i}:{surface}/{reading}]"
        if not surface or not reading:
            problems.append(f"{tag} needs both a surface and a reading")
            continue
        key = (surface, reading)
        if key not in known:
            problems.append(f"{tag} no such word in this build")
            continue
        if key in already:
            skipped_present += 1
            continue
        for lang in ("ko", "ja", "zh"):
            bad = script_problem(lang, item.get(lang, ""))
            if bad:
                problems.append(f"{tag} {lang}: {bad}")
        staged_ko[key] = {"surface": surface, "reading": reading,
                          "ko": item.get("ko", "")}
        staged_jazh[key] = {"surface": surface, "reading": reading,
                            "ja": item.get("ja", ""), "zh": item.get("zh", "")}
    if problems:
        print(f"FAIL ({len(problems)} problems)")
        for p in problems[:40]:
            print("  " + p)
        return 1
    print(f"OK — {len(staged_ko)} words"
          + (f", {skipped_present} already glossed" if skipped_present else ""))
    if write:
        ko.update(staged_ko)
        jazh.update(staged_jazh)
        for path, data in ((WORD_KO, ko), (WORD_JAZH, jazh)):
            path.write_text("\n".join(
                json.dumps(data[k], ensure_ascii=False) for k in sorted(data)) + "\n",
                encoding="utf-8")
        print(f"wrote {len(ko)} → {WORD_KO}, {len(jazh)} → {WORD_JAZH}")
    return 0


def merge_sentences(conn: sqlite3.Connection, items: list[dict], lang: str,
                    write: bool, inputs: list[str] | None = None) -> int:
    """sentence_glosses.jsonl is keyed by the Japanese text, not by id, because
    sentence ids are autoincrement rowids and are not stable: dropping a single
    sentence at ingest renumbers every later one, and a batch translated against
    yesterday's build would then attach its text to the wrong sentence. (That is
    not hypothetical — one blocked sentence shifted 1,500 ids and this check is
    what caught it.)

    So a batch that carries only ids has to be paired with the input files it was
    emitted from, via --inputs: those hold the id → Japanese text mapping as of
    the build that produced them.
    """
    ja_by_id: dict[int, str] = {}
    if inputs:
        for path in inputs:
            for entry in json.loads(Path(path).read_text(encoding="utf-8")):
                ja_by_id[entry["id"]] = entry["ja"]
    else:
        ja_by_id = dict(conn.execute("SELECT id, text_ja FROM sentence"))
    known_text = {r[0] for r in conn.execute("SELECT text_ja FROM sentence")}
    already = {r[0] for r in conn.execute(
        "SELECT DISTINCT s.text_ja FROM sentence s JOIN sentence_translation t "
        "ON t.sentence_id = s.id WHERE t.lang = ?", (lang,))}
    existing: dict[str, dict] = {}
    if SENTENCE_GLOSSES.exists():
        for line in SENTENCE_GLOSSES.read_text(encoding="utf-8").splitlines():
            if line.strip():
                entry = json.loads(line)
                existing[entry["ja"]] = entry
    problems: list[str] = []
    staged: dict[str, dict] = {}
    skipped_present = 0
    skipped_gone = 0
    for i, item in enumerate(items):
        sid = item.get("id")
        tag = f"[{i}:{sid}]"
        ja = item.get("ja") or ja_by_id.get(sid)
        if not ja:
            problems.append(f"{tag} cannot resolve the Japanese text — pass --inputs")
            continue
        if ja not in known_text:
            # Dropped at ingest since the batch was emitted (the blocklist), so
            # its translation has nowhere to go. Not an error.
            skipped_gone += 1
            continue
        if ja in already:
            # A sentence that gained this language since the batch was emitted
            # (Tatoeba, or another sentence sharing the same text). Not an error.
            skipped_present += 1
            continue
        bad = script_problem(lang, item.get(lang, ""))
        if bad:
            problems.append(f"{tag} {lang}: {bad}")
            continue
        merged = dict(existing.get(ja, {"ja": ja}))
        merged[lang] = item[lang]
        staged[ja] = merged
    if problems:
        print(f"FAIL ({len(problems)} problems)")
        for p in problems[:40]:
            print("  " + p)
        return 1
    notes = []
    if skipped_present:
        notes.append(f"{skipped_present} already had it")
    if skipped_gone:
        notes.append(f"{skipped_gone} no longer in the build")
    print(f"OK — {len(staged)} sentences ({lang})"
          + (", " + ", ".join(notes) if notes else ""))
    if write:
        existing.update(staged)
        SENTENCE_GLOSSES.write_text("\n".join(
            json.dumps(existing[k], ensure_ascii=False) for k in existing) + "\n",
            encoding="utf-8")
        print(f"wrote {len(existing)} → {SENTENCE_GLOSSES}")
    return 0


def merge_yoji(items: list[dict], write: bool) -> int:
    path = Path("sources/yojijukugo.json")
    if not path.exists():
        path = Path("../app/Sources/DictionaryClient/Resources/yojijukugo.source.json")
    entries = json.loads(path.read_text(encoding="utf-8"))
    by_yoji = {e["yoji"]: e for e in entries}
    problems: list[str] = []
    for i, item in enumerate(items):
        y = item.get("yoji")
        tag = f"[{i}:{y}]"
        if y not in by_yoji:
            problems.append(f"{tag} no such 四字熟語")
            continue
        for lang in ("zh", "en"):
            bad = script_problem(lang, item.get(lang, ""))
            if bad:
                problems.append(f"{tag} {lang}: {bad}")
    if problems:
        print(f"FAIL ({len(problems)} problems)")
        for p in problems[:40]:
            print("  " + p)
        return 1
    print(f"OK — {len(items)} 四字熟語")
    if write:
        for item in items:
            entry = by_yoji[item["yoji"]]
            entry["meaningZh"] = item["zh"]
            entry["meaningEn"] = item["en"]
        path.write_text(json.dumps(entries, ensure_ascii=False, indent=1) + "\n",
                        encoding="utf-8")
        print(f"wrote {len(entries)} → {path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("words", "sentences", "yoji"))
    parser.add_argument("batches", nargs="+")
    parser.add_argument("--db", default="out/kanji.sqlite")
    parser.add_argument("--lang", default="ko", choices=("ko", "zh", "en"))
    parser.add_argument("--write", action="store_true")
    parser.add_argument("--inputs", nargs="*",
                        help="the emitted batch files these outputs came from; "
                             "they carry the id → Japanese text mapping, which "
                             "ids alone cannot be trusted for")
    args = parser.parse_args()

    items = read_batches(args.batches)
    conn = sqlite3.connect(args.db)
    if args.kind == "words":
        return merge_words(conn, items, args.write)
    if args.kind == "sentences":
        return merge_sentences(conn, items, args.lang, args.write, args.inputs)
    return merge_yoji(items, args.write)


if __name__ == "__main__":
    raise SystemExit(main())
