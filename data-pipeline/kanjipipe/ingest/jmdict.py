"""Parse JMdict into common kanji-bearing words with English glosses."""
from pathlib import Path

from lxml import etree

from kanjipipe.models import Word

_XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
_MAX_GLOSSES = 3


def parse_jmdict(path: str | Path) -> list[Word]:
    # JMdict ships an internal DTD with entity definitions (e.g. &n;); lxml
    # resolves internal entities by default. no_network avoids fetching anything.
    parser = etree.XMLParser(resolve_entities=True, no_network=True)
    root = etree.parse(str(path), parser).getroot()

    words: list[Word] = []
    for entry in root.iterfind("entry"):
        kebs = entry.findall("k_ele/keb")
        if not kebs or not kebs[0].text:
            continue  # kana-only entry — no kanji to attach to
        is_common = (entry.find("k_ele/ke_pri") is not None
                     or entry.find("r_ele/re_pri") is not None)
        if not is_common:
            continue
        reb = entry.find("r_ele/reb")
        if reb is None or not reb.text:
            continue

        glosses: list[str] = []
        for gloss in entry.iterfind("sense/gloss"):
            lang = gloss.get(_XML_LANG)
            if (lang is None or lang == "eng") and gloss.text:
                glosses.append(gloss.text)
                if len(glosses) >= _MAX_GLOSSES:
                    break

        words.append(Word(
            surface=kebs[0].text,
            reading_kana=reb.text,
            is_common=True,
            en_glosses=glosses,
        ))
    return words
