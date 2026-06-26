"""Parse the LLM-generated native-gloss JSONL ({literal, ko, ja, zh} per line)."""
import json
from pathlib import Path

from kanjipipe.models import LlmGloss


def parse_llm_glosses(path: str | Path) -> list[LlmGloss]:
    def _clean(value: object) -> str | None:
        # Whitespace-only LLM placeholders count as "no gloss".
        return value.strip() if isinstance(value, str) and value.strip() else None

    entries: list[LlmGloss] = []
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
                print(f"llm_glosses: skipping malformed line {line_number}: {error}")
                continue
            literal = obj.get("literal")
            if not literal:
                print(f"llm_glosses: skipping line {line_number} with no literal")
                continue
            entries.append(LlmGloss(
                literal=literal,
                ko=_clean(obj.get("ko")),
                ja=_clean(obj.get("ja")),
                zh=_clean(obj.get("zh")),
            ))
    return entries
