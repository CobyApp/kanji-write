"""Parse a KANJIDIC2 XML file into a list of Kanji domain objects."""
from pathlib import Path

from lxml import etree

from kanjipipe.models import Gloss, Kanji, Reading

_AXIS = {"ja_on": "on", "ja_kun": "kun", "pinyin": "pinyin", "korean_h": "eum"}


def _int_or_none(text: str | None) -> int | None:
    return int(text) if text is not None else None


def parse_kanjidic2(path: str | Path) -> list[Kanji]:
    root = etree.parse(str(path)).getroot()
    result: list[Kanji] = []
    for ch in root.iterfind("character"):
        literal = ch.findtext("literal")

        codepoint = None
        for cp in ch.iterfind("codepoint/cp_value"):
            if cp.get("cp_type") == "ucs":
                codepoint = int(cp.text, 16)
        if codepoint is None:
            raise ValueError(f"character {literal!r} has no UCS codepoint")

        radical = None
        for rv in ch.iterfind("radical/rad_value"):
            if rv.get("rad_type") == "classical":
                radical = int(rv.text)

        misc = ch.find("misc")
        if misc is None:
            raise ValueError(f"character {literal!r} has no <misc> element")
        grade = _int_or_none(misc.findtext("grade"))
        stroke_count = _int_or_none(misc.findtext("stroke_count"))
        if stroke_count is None:
            raise ValueError(f"character {literal!r} has no <stroke_count>")
        freq_rank = _int_or_none(misc.findtext("freq"))

        readings: list[Reading] = []
        glosses: list[Gloss] = []
        for rm in ch.iterfind("reading_meaning/rmgroup"):
            for r in rm.iterfind("reading"):
                axis = _AXIS.get(r.get("r_type"))
                if axis and r.text:
                    readings.append(Reading(lang_axis=axis, value=r.text))
            for m in rm.iterfind("meaning"):
                if m.get("m_lang") is None and m.text:  # English meanings carry no m_lang
                    glosses.append(Gloss(lang="en", text=m.text))

        result.append(Kanji(
            literal=literal, codepoint=codepoint, stroke_count=stroke_count,
            grade=grade, freq_rank=freq_rank, radical=radical,
            readings=readings, glosses=glosses,
        ))
    return result
