"""Parse a KanjiVG XML file into a map of codepoint -> ordered stroke paths."""
import re
from pathlib import Path

from lxml import etree

# Top-level <kanji id="kvg:kanji_05c71"> carries the codepoint as hex.
_ID_RE = re.compile(r"kanji_([0-9a-fA-F]+)")


def _localname(el) -> str:
    return etree.QName(el.tag).localname if isinstance(el.tag, str) else ""


def _codepoint_from_id(kanji_id: str | None) -> int | None:
    if not kanji_id:
        return None
    match = _ID_RE.search(kanji_id)
    return int(match.group(1), 16) if match else None


def parse_kanjivg(path: str | Path) -> dict[int, list[str]]:
    root = etree.parse(str(path)).getroot()
    result: dict[int, list[str]] = {}
    for kanji in root.iter():
        if _localname(kanji) != "kanji":
            continue
        codepoint = _codepoint_from_id(kanji.get("id"))
        if codepoint is None:
            continue
        # The base form (e.g. id "kvg:kanji_05ce0") appears before its variants
        # (e.g. "...-Kaisho", "...-var"), which share the same codepoint. Keep
        # the first (base) entry so variants don't silently overwrite it.
        if codepoint in result:
            continue
        paths: list[str] = []
        for el in kanji.iter():
            if _localname(el) == "path":
                d = el.get("d")
                if d:
                    paths.append(d)
        result[codepoint] = paths
    return result
