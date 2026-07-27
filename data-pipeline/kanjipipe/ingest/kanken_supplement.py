from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse


DEFAULT_SUPPLEMENT_PATH = (
    Path(__file__).resolve().parents[1] / "kanken_metadata_supplement.json"
)
ALLOWED_PROVENANCE_RELATIONSHIPS = {
    "direct_character",
    "indirect_lexical_anchor",
    "verification_only",
}


@dataclass(frozen=True)
class Provenance:
    source: str
    source_id: str
    url: str
    license: str
    relationship: str


@dataclass(frozen=True)
class SupplementEntry:
    literal: str
    readings: tuple[tuple[str, str], ...]
    english_glosses: tuple[str, ...]
    provenance: tuple[Provenance, ...]


def parse_kanken_supplement(
    path: str | Path,
) -> dict[str, SupplementEntry]:
    document = json.loads(Path(path).read_text(encoding="utf-8"))
    if document.get("version") != 1:
        raise ValueError("unsupported Kanken supplement version")

    result: dict[str, SupplementEntry] = {}
    for raw_entry in document.get("entries", []):
        literal = raw_entry.get("literal", "")
        if len(literal) != 1:
            raise ValueError("supplement literal must be one Unicode character")
        if literal in result:
            raise ValueError(f"duplicate supplement literal: {literal}")

        readings = tuple(
            (reading["axis"], reading["value"])
            for reading in raw_entry.get("readings", [])
        )
        if any(axis not in {"on", "kun"} or not value for axis, value in readings):
            raise ValueError(f"invalid supplement reading for {literal}")

        provenance = tuple(
            Provenance(
                source=item["source"],
                source_id=item["sourceId"],
                url=item["url"],
                license=item["license"],
                relationship=item.get("relationship", ""),
            )
            for item in raw_entry.get("provenance", [])
        )
        if not provenance:
            raise ValueError(f"supplement entry {literal} requires provenance")
        if any(
            item.relationship not in ALLOWED_PROVENANCE_RELATIONSHIPS
            for item in provenance
        ):
            raise ValueError(f"invalid supplement provenance relationship for {literal}")
        if any(
            not item.source
            or not item.source_id
            or not item.license
            or urlparse(item.url).scheme not in {"http", "https"}
            for item in provenance
        ):
            raise ValueError(f"invalid supplement provenance for {literal}")

        english_glosses = tuple(raw_entry.get("englishGlosses", []))
        if any(not gloss for gloss in english_glosses):
            raise ValueError(f"invalid English gloss for {literal}")
        if not readings and not english_glosses:
            raise ValueError(
                f"supplement entry {literal} requires readings or English glosses"
            )

        result[literal] = SupplementEntry(
            literal=literal,
            readings=readings,
            english_glosses=english_glosses,
            provenance=provenance,
        )
    return result
