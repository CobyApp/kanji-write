from __future__ import annotations

import hashlib
import io
import zipfile
from dataclasses import dataclass
from pathlib import Path


UNIHAN_URL = "https://www.unicode.org/Public/17.0.0/ucd/Unihan.zip"
UNIHAN_SHA256 = (
    "f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e"
)
UNIHAN_LICENSE_URL = "https://www.unicode.org/license.txt"


@dataclass(frozen=True)
class UnihanMetadata:
    literal: str
    stroke_count: int | None
    radical: int | None
    on_readings: tuple[str, ...]
    kun_readings: tuple[str, ...]
    definition: str | None
    # The primary Sino-Korean reading, or None when Unihan lists none.
    korean_reading: str | None = None


def _verify_sha256(path: Path, expected_sha256: str) -> None:
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != expected_sha256:
        raise ValueError(
            f"Unihan SHA-256 mismatch: expected {expected_sha256}, got {digest}"
        )


def parse_unihan(
    path: str | Path,
    *,
    expected_sha256: str | None = UNIHAN_SHA256,
) -> dict[str, UnihanMetadata]:
    archive_path = Path(path)
    if not archive_path.is_file():
        raise FileNotFoundError(
            f"Unihan archive not found at {archive_path}; "
            "run scripts/fetch_sources.sh to download the pinned source"
        )
    if expected_sha256 is not None:
        _verify_sha256(archive_path, expected_sha256)

    properties: dict[str, dict[str, str]] = {}
    filenames = (
        "Unihan_Readings.txt",
        "Unihan_IRGSources.txt",
        "Unihan_RadicalStrokeCounts.txt",
    )
    with zipfile.ZipFile(archive_path) as archive:
        for filename in filenames:
            with archive.open(filename) as raw:
                for line in io.TextIOWrapper(raw, encoding="utf-8"):
                    if line.startswith("#"):
                        continue
                    parts = line.rstrip("\n").split("\t", 2)
                    if len(parts) != 3:
                        continue
                    codepoint, property_name, value = parts
                    if property_name not in {
                        "kDefinition",
                        "kJapaneseOn",
                        "kJapaneseKun",
                        "kHangul",
                        "kTotalStrokes",
                        "kRSUnicode",
                    }:
                        continue
                    literal = chr(int(codepoint.removeprefix("U+"), 16))
                    properties.setdefault(literal, {})[property_name] = value

    result: dict[str, UnihanMetadata] = {}
    for literal, values in properties.items():
        strokes = values.get("kTotalStrokes")
        radical_strokes = values.get("kRSUnicode")
        result[literal] = UnihanMetadata(
            literal=literal,
            stroke_count=int(strokes.split()[0]) if strokes else None,
            radical=(
                int(
                    radical_strokes.split()[0]
                    .split(".", 1)[0]
                    .rstrip("'")
                )
                if radical_strokes
                else None
            ),
            on_readings=tuple(values.get("kJapaneseOn", "").split()),
            kun_readings=tuple(values.get("kJapaneseKun", "").split()),
            definition=values.get("kDefinition"),
            # kHangul is "축:0E 추:0N" — space-separated readings each tagged
            # with a source, primary first. kanjidic2's ordering is not this,
            # which is why its first korean_h is often the wrong one.
            korean_reading=(
                values["kHangul"].split()[0].split(":")[0]
                if values.get("kHangul") else None
            ),
        )
    return result
