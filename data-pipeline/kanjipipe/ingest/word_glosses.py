"""Parse LLM-generated word-gloss JSONL files: Korean ({"id", "ko"} per line)
and Japanese/Chinese ({"id", "ja", "zh"} per line)."""
import json
from pathlib import Path


def parse_word_glosses(path: str | Path) -> list[tuple[int, str]]:
    entries: list[tuple[int, str]] = []
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
            word_id = obj.get("id")
            if not isinstance(word_id, int) or isinstance(word_id, bool):
                print(f"word_glosses: skipping line {line_number} with no integer id")
                continue
            ko = obj.get("ko")
            if not isinstance(ko, str) or not ko.strip():
                print(f"word_glosses: skipping line {line_number} with empty ko")
                continue
            entries.append((word_id, ko.strip()))
    return entries


def parse_word_jazh(
    path: str | Path,
) -> list[tuple[int, str | None, str | None]]:
    entries: list[tuple[int, str | None, str | None]] = []
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
            word_id = obj.get("id")
            if not isinstance(word_id, int) or isinstance(word_id, bool):
                print(f"word_glosses: skipping line {line_number} with no integer id")
                continue
            ja = obj.get("ja")
            ja = ja.strip() if isinstance(ja, str) and ja.strip() else None
            zh = obj.get("zh")
            zh = zh.strip() if isinstance(zh, str) and zh.strip() else None
            entries.append((word_id, ja, zh))
    return entries
