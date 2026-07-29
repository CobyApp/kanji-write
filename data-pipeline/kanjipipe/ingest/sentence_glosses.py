"""Parse LLM-generated sentence-translation JSONL ({"ja", "ko", "zh", "en"} per
line), keyed by the Japanese sentence text. Tatoeba supplies translations for only
a fraction of sentences — unevenly, and English is not always among them — so this
fills the rest, in every language the app offers."""
import json
from pathlib import Path


def parse_sentence_glosses(
    path: str | Path,
) -> list[tuple[str, str | None, str | None, str | None]]:
    """Return `(ja_text, ko, zh, en)` tuples. Skips blank/malformed lines, lines
    with no Japanese text, and lines with no translation at all. Values are
    stripped; whitespace-only ones become None."""
    entries: list[tuple[str, str | None, str | None, str | None]] = []
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
            en = obj.get("en")
            en = en.strip() if isinstance(en, str) and en.strip() else None
            if ko is None and zh is None and en is None:
                continue
            entries.append((ja.strip(), ko, zh, en))
    return entries
