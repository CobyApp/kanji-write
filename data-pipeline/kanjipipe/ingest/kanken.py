import csv
from pathlib import Path

from kanjipipe.models import KankenAllocation

DEFAULT_RESOLVED_LITERALS_PATH = (
    Path(__file__).resolve().parents[2] / "sources/kanken_resolved_literals.csv"
)


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


def load_resolved_literals(
    path: str | Path | None = DEFAULT_RESOLVED_LITERALS_PATH,
) -> dict[str, str]:
    """字項ID → the Unicode character for entries 漢検 publishes only as an image.

    The list leaves 漢字テキスト blank for those, so without this they arrive with
    no character and are never shipped — 117 head characters at 準1級/1級 were
    missing from the app for exactly that reason. See the file's own header for
    why only 親字 entries are resolved and not the 旧字 variant rows.
    """
    if path is None:
        return {}
    file = Path(path)
    if not file.exists():
        return {}
    with file.open(encoding="utf-8", newline="") as source:
        return {row["ce_id"]: row["literal"] for row in csv.DictReader(source)
                if row["literal"]}


def parse_kanken_allocations(
    path: str | Path,
    resolved_literals_path: str | Path | None = None,
) -> list[KankenAllocation]:
    """Parse the 漢検 allocation list.

    `resolved_literals_path` supplies characters for the entries the list
    publishes only as an image. It defaults to None so a fixture build is not
    silently reshaped by the production mapping; build_db passes the real one.
    """
    resolved = load_resolved_literals(resolved_literals_path)
    with Path(path).open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames is not None:
            reader.fieldnames = [name.strip() for name in reader.fieldnames]
        return [
            KankenAllocation(
                ct_id=row["字種ID"],
                ce_id=row["字項ID"],
                literal=(row["漢字テキスト"]
                         or resolved.get(row["字項ID"])
                         or None),
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
