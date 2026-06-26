"""Parse the LLM-generated native-gloss JSONL ({literal, ko, ja, zh} per line)."""
import json
from pathlib import Path

from kanjipipe.models import LlmGloss


def parse_llm_glosses(path: str | Path) -> list[LlmGloss]:
    entries: list[LlmGloss] = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            entries.append(LlmGloss(
                literal=obj["literal"],
                ko=obj.get("ko"),
                ja=obj.get("ja"),
                zh=obj.get("zh"),
            ))
    return entries
