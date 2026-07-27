import csv
from pathlib import Path

from kanjipipe.models import KankenAllocation


VALID_LEVELS = {
    "10級",
    "9級",
    "8級",
    "7級",
    "6級",
    "5級",
    "4級",
    "3級",
    "準2級",
    "2級",
    "準1級",
    "1/準1級",
    "1級",
}


def parse_kanken_allocations(path: str | Path) -> list[KankenAllocation]:
    with Path(path).open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames is not None:
            reader.fieldnames = [name.strip() for name in reader.fieldnames]
        return [
            KankenAllocation(
                ct_id=row["字種ID"],
                ce_id=row["字項ID"],
                literal=row["漢字テキスト"] or None,
                variant_kind=row["字体"],
                source_level=row["漢検級"],
            )
            for row in reader
        ]


def memberships_for(source_level: str) -> tuple[str, ...]:
    if source_level not in VALID_LEVELS:
        raise ValueError(f"unknown Kanken level: {source_level}")
    if source_level == "1/準1級":
        return ("準1級", "1級")
    return (source_level,)
