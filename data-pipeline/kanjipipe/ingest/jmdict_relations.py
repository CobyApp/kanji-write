"""Parse JMdict antonym (<ant>) and cross-reference (<xref>) relations."""
from pathlib import Path

from lxml import etree

from kanjipipe.models import Relation


def _preferred_keb(entry) -> str | None:
    k_eles = entry.findall("k_ele")
    for k_ele in k_eles:
        keb = k_ele.findtext("keb")
        if keb and k_ele.find("ke_inf") is None:
            return keb
    return (k_eles[0].findtext("keb") if k_eles else None) or None


def _target_surface(text: str | None) -> str | None:
    # JMdict xref/ant targets look like "語・よみ・senseNo"; keep the surface only.
    if not text:
        return None
    return text.split("・", 1)[0] or None


def _entry_relations(entry) -> list[Relation]:
    source = _preferred_keb(entry)
    if source is None:
        return []
    relations: list[Relation] = []
    for sense in entry.iterfind("sense"):
        for ant in sense.iterfind("ant"):
            target = _target_surface(ant.text)
            if target:
                relations.append(Relation(source, target, "antonym"))
        for xref in sense.iterfind("xref"):
            target = _target_surface(xref.text)
            if target:
                relations.append(Relation(source, target, "related"))
    return relations


def parse_jmdict_relations(path: str | Path) -> list[Relation]:
    relations: list[Relation] = []
    for _event, entry in etree.iterparse(
        str(path), events=("end",), tag="entry",
        resolve_entities=True, no_network=True,
    ):
        relations.extend(_entry_relations(entry))
        entry.clear()
    return relations
