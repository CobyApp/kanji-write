"""Parse LLM-generated sentence-translation JSONL ({"ja", "ko", "zh"} per line),
keyed by the Japanese sentence text. Tatoeba only supplies ko/zh translations for
a small fraction of sentences; this fills the rest so non-English learners aren't
shown an English fallback."""
import json
from pathlib import Path


def parse_sentence_glosses(
    path: str | Path,
) -> list[tuple[str, str | None, str | None]]:
    """Return `(ja_text, ko, zh)` tuples. Skips blank/malformed lines, lines with
    no Japanese text, and lines with neither a ko nor a zh translation. ko/zh are
    stripped; whitespace-only values become None."""
    entries: list[tuple[str, str | None, str | None]] = []
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
                print(f"sentence_glosses: skipping malformed line {line_number}: {error}")
                continue
            ja = obj.get("ja")
            if not isinstance(ja, str) or not ja.strip():
                print(f"sentence_glosses: skipping line {line_number} with no ja")
                continue
            ko = obj.get("ko")
            ko = ko.strip() if isinstance(ko, str) and ko.strip() else None
            zh = obj.get("zh")
            zh = zh.strip() if isinstance(zh, str) and zh.strip() else None
            if ko is None and zh is None:
                continue
            entries.append((ja.strip(), ko, zh))
    return entries
