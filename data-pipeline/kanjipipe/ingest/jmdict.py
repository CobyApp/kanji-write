"""Parse JMdict into common kanji-bearing words with English glosses."""
from pathlib import Path

from lxml import etree

from kanjipipe.ingest._jmdict_util import preferred_keb
from kanjipipe.models import Word

_XML_LANG = "{http://www.w3.org/XML/1998/namespace}lang"
_MAX_GLOSSES = 3


def _entry_to_word(entry) -> Word | None:
    surface = preferred_keb(entry)
    if surface is None:
        return None  # kana-only entry — no kanji to attach to
    is_common = (entry.find("k_ele/ke_pri") is not None
                 or entry.find("r_ele/re_pri") is not None)
    if not is_common:
        return None
    reb = entry.find("r_ele/reb")
    if reb is None or not reb.text:
        return None
    glosses: list[str] = []
    for gloss in entry.iterfind("sense/gloss"):
        lang = gloss.get(_XML_LANG)
        if (lang is None or lang == "eng") and gloss.text:
            glosses.append(gloss.text)
            if len(glosses) >= _MAX_GLOSSES:
                break
    return Word(surface=surface, reading_kana=reb.text, is_common=True, en_glosses=glosses)


def parse_jmdict(path: str | Path) -> list[Word]:
    # Stream entry-by-entry: JMdict_e is ~60MB, so a whole-DOM parse is costly.
    # resolve_entities=True expands JMdict's internal DTD entities (e.g. &n;).
    words: list[Word] = []
    for _event, entry in etree.iterparse(
        str(path), events=("end",), tag="entry",
        resolve_entities=True, no_network=True,
    ):
        word = _entry_to_word(entry)
        if word is not None:
            words.append(word)
        entry.clear()  # release the processed subtree to keep memory flat
    return words
