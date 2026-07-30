"""Parse LLM-generated word-gloss JSONL files: Korean ({"surface", "reading",
"ko"} per line) and Japanese/Chinese ({"surface", "reading", "ja", "zh"}).

Keyed by surface + kana reading, not by word id. Ids are autoincrement rowids and
move whenever the word set changes — adding 117 kanji widened the vocabulary
filter and shifted 4,386 of them — which once silently attached 学校's gloss to a
word meaning "frontal width". Surface alone is not enough: 上手 is じょうず or
うわて and they are different words with different meanings."""
import json
from pathlib import Path


def parse_word_glosses(path: str | Path) -> list[tuple[str, str, str]]:
    """Return `(surface, reading, ko)` triples."""
    entries: list[tuple[str, str, str]] = []
    with open(path, encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as error:
                # LLM output can occasionally emit a malformed line; skip it
                # rather than aborting the whole file.
                print(f"word_glosses: skipping malformed line {line_number}: {error}")
                continue
            surface = obj.get("surface")
            reading = obj.get("reading")
            if not isinstance(surface, str) or not surface \
                    or not isinstance(reading, str) or not reading:
                print(f"word_glosses: skipping line {line_number} with no surface/reading")
                continue
            ko = obj.get("ko")
            if not isinstance(ko, str) or not ko.strip():
                print(f"word_glosses: skipping line {line_number} with empty ko")
                continue
            entries.append((surface, reading, ko.strip()))
    return entries


def parse_word_jazh(
    path: str | Path,
) -> list[tuple[str, str, str | None, str | None]]:
    """Return `(surface, reading, ja, zh)` tuples."""
    entries: list[tuple[str, str, str | None, str | None]] = []
    with open(path, encoding="utf-8") as handle:
        for line_number, raw in enumerate(handle, start=1):
            line = raw.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError as error:
                # LLM output can occasionally emit a malformed line; skip it
                # rather than aborting the whole file.
                print(f"word_glosses: skipping malformed line {line_number}: {error}")
                continue
            surface = obj.get("surface")
            reading = obj.get("reading")
            if not isinstance(surface, str) or not surface \
                    or not isinstance(reading, str) or not reading:
                print(f"word_glosses: skipping line {line_number} with no surface/reading")
                continue
            ja = obj.get("ja")
            ja = ja.strip() if isinstance(ja, str) and ja.strip() else None
            zh = obj.get("zh")
            zh = zh.strip() if isinstance(zh, str) and zh.strip() else None
            entries.append((surface, reading, ja, zh))
    return entries
