"""The radical and parts of each kanji, as KanjiVG draws them.

漢検's 部首 section asks for the radical in the form it takes inside the
character — 氵 for 海, 扌 for 持, ⻌ for 道 — and offers the character's own
parts as the wrong answers. KANJIDIC's Kangxi number only names the radical's
base form (水, 手, 辵), so the form and the parts come from KanjiVG, where each
<g> carries `kvg:element` and the radical group is marked `kvg:radical`.

漢検 follows the traditional (康熙) classification: 問 is under 口 and 聞 under
耳, which KanjiVG marks "tradit" while Nelson's 門 is "nelson". So a "general"
radical wins, then "tradit"; "nelson" is never used.
"""
from __future__ import annotations

from pathlib import Path

from lxml import etree

from kanjipipe.ingest.kanjivg import _codepoint_from_id, _localname

_KVG = "{http://kanjivg.tagaini.net}"
_PREFERENCE = ("general", "tradit")


def parse_kanjivg_parts(path: str | Path) -> dict[int, tuple[str, list[str]]]:
    """{codepoint: (radical form, other parts in drawing order)}."""
    root = etree.parse(str(path)).getroot()
    result: dict[int, tuple[str, list[str]]] = {}
    for kanji in root.iter():
        if _localname(kanji) != "kanji":
            continue
        codepoint = _codepoint_from_id(kanji.get("id"))
        if codepoint is None or codepoint in result:
            continue
        literal = chr(codepoint)
        radicals: dict[str, str] = {}
        parts: list[str] = []
        for group in kanji.iter():
            if _localname(group) != "g":
                continue
            element = group.get(f"{_KVG}element")
            if not element or element == literal:
                continue
            kind = group.get(f"{_KVG}radical")
            if kind:
                radicals.setdefault(kind, element)
            if element not in parts:
                parts.append(element)
        form = next((radicals[k] for k in _PREFERENCE if k in radicals), None)
        if form is None:
            continue
        result[codepoint] = (form, [p for p in parts if p != form])
    return result
