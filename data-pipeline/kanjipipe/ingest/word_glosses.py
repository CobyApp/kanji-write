"""Parse the LLM-generated Korean word-gloss JSONL ({"id", "ko"} per line)."""
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
