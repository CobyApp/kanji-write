# kanjipipe/ingest/jlpt.py
import json
from pathlib import Path

from kanjipipe.models import Kanji


def merge_jlpt(kanji: list[Kanji], jlpt_path: str | Path) -> list[Kanji]:
    mapping = json.loads(Path(jlpt_path).read_text(encoding="utf-8"))
    for k in kanji:
        k.jlpt_level = mapping.get(k.literal)
    return kanji
