"""Parse Tatoeba sentences + links into Japanese sentences with translations."""
import csv
from pathlib import Path

from kanjipipe.models import Sentence

# Tatoeba lang code -> our translation lang key.
_LANG_MAP = {"eng": "en", "kor": "ko", "cmn": "zh"}
_KEEP_LANGS = {"jpn", *_LANG_MAP}


def parse_tatoeba(sentences_path: str | Path, links_path: str | Path) -> list[Sentence]:
    # 1. Keep only sentences in the languages we care about.
    by_id: dict[int, tuple[str, str]] = {}
    with open(sentences_path, encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 3:
                continue
            lang = row[1]
            if lang in _KEEP_LANGS:
                by_id[int(row[0])] = (lang, row[2])

    # 2. Undirected adjacency over translation links. Prune to links that touch
    #    a kept sentence — the real links dump is ~tens of millions of rows, and
    #    keeping all of them would cost several GB.
    adjacency: dict[int, set[int]] = {}
    with open(links_path, encoding="utf-8", newline="") as handle:
        for row in csv.reader(handle, delimiter="\t"):
            if len(row) < 2:
                continue
            a, b = int(row[0]), int(row[1])
            if a not in by_id and b not in by_id:
                continue
            adjacency.setdefault(a, set()).add(b)
            adjacency.setdefault(b, set()).add(a)

    # 3. For each Japanese sentence, gather one translation per target language.
    #    Iterate neighbours in id order so the chosen translation is deterministic
    #    (set iteration order varies by hash seed → non-reproducible builds).
    sentences: list[Sentence] = []
    for sid, (lang, text) in by_id.items():
        if lang != "jpn":
            continue
        translations: dict[str, str] = {}
        for neighbour in sorted(adjacency.get(sid, ())):
            entry = by_id.get(neighbour)
            if entry is None:
                continue
            key = _LANG_MAP.get(entry[0])
            if key and key not in translations:
                translations[key] = entry[1]
        if translations:
            sentences.append(Sentence(ja_text=text, translations=translations))
    return sentences
