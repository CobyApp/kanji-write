# kanjipipe/filters.py
import unicodedata

from kanjipipe.ingest.kanken_supplement import SupplementEntry
from kanjipipe.ingest.unihan import UnihanMetadata
from kanjipipe.models import Gloss, Kanji, KankenAllocation, Reading

JOYO_GRADES = frozenset({1, 2, 3, 4, 5, 6, 8})  # 1-6 = 小, 8 = 中学/常用
ADVANCED_KANKEN_LEVELS = frozenset({"準1級", "1/準1級", "1級"})


def filter_joyo(kanji: list[Kanji]) -> list[Kanji]:
    return [k for k in kanji if k.grade in JOYO_GRADES]


def apply_korean_readings(
    kanji: list[Kanji],
    unihan: dict[str, UnihanMetadata],
) -> None:
    """Replace each kanji's Sino-Korean reading with Unihan's primary one.

    kanjidic2 lists `korean_h` in no particular order, and the pipeline was
    taking the first — which is the wrong reading for 570 of the 6,352 kanji
    that have one (阿 as 옥 instead of 아, 丑 as 추 instead of 축). Unihan's
    kHangul is ordered with the primary first, so it wins wherever it exists;
    kanjidic2 stays where Unihan is silent, since a wrong-order reading still
    beats no reading.
    """
    for item in kanji:
        primary = unihan.get(item.literal)
        if primary is None or not primary.korean_reading:
            continue
        item.readings = [r for r in item.readings if r.lang_axis != "eum"]
        item.readings.append(Reading("eum", primary.korean_reading))


def select_study_inventory(
    kanji: list[Kanji],
    allocations: list[KankenAllocation],
    *,
    unihan: dict[str, UnihanMetadata] | None = None,
    supplements: dict[str, SupplementEntry] | None = None,
) -> list[Kanji]:
    unihan = unihan or {}
    supplements = supplements or {}
    kanji_by_literal = {item.literal: item for item in kanji}
    advanced_literals = list(dict.fromkeys(
        allocation.literal
        for allocation in allocations
        if allocation.literal is not None
        and allocation.source_level in ADVANCED_KANKEN_LEVELS
    ))
    allocations_by_ct: dict[str, list[str]] = {}
    for allocation in allocations:
        if allocation.literal is not None:
            literals = allocations_by_ct.setdefault(allocation.ct_id, [])
            if allocation.literal not in literals:
                literals.append(allocation.literal)
    ct_by_literal = {
        allocation.literal: allocation.ct_id
        for allocation in allocations
        if allocation.literal is not None
    }

    def kanjidic_candidate(literal: str) -> Kanji | None:
        exact = kanji_by_literal.get(literal)
        if exact is not None:
            return exact
        normalized = unicodedata.normalize("NFKC", literal)
        if normalized != literal:
            return kanji_by_literal.get(normalized)
        return None

    resolved: dict[str, Kanji] = {}
    for literal in advanced_literals:
        exact = kanji_by_literal.get(literal)
        normalized_literal = unicodedata.normalize("NFKC", literal)
        normalized = (
            kanji_by_literal.get(normalized_literal)
            if normalized_literal != literal
            else None
        )
        sibling_candidates = [
            candidate
            for sibling in allocations_by_ct.get(ct_by_literal[literal], [])
            if sibling != literal
            if (candidate := kanjidic_candidate(sibling)) is not None
        ]
        kanjidic_fallbacks = [
            candidate
            for candidate in (normalized, *sibling_candidates)
            if candidate is not None
        ]
        unihan_entry = unihan.get(literal)
        supplement = supplements.get(literal)

        scalar_candidates = [
            candidate
            for candidate in (exact, *kanjidic_fallbacks)
            if candidate is not None
        ]
        stroke_count = next(
            (candidate.stroke_count for candidate in scalar_candidates),
            unihan_entry.stroke_count if unihan_entry else None,
        )
        if stroke_count is None:
            continue
        radical = next(
            (
                candidate.radical
                for candidate in scalar_candidates
                if candidate.radical is not None
            ),
            unihan_entry.radical if unihan_entry else None,
        )

        readings = list(exact.readings) if exact is not None else []
        if not any(reading.lang_axis in {"on", "kun"} for reading in readings):
            for candidate in kanjidic_fallbacks:
                japanese = [
                    reading
                    for reading in candidate.readings
                    if reading.lang_axis in {"on", "kun"}
                ]
                if japanese:
                    readings.extend(japanese)
                    break
            else:
                if unihan_entry is not None:
                    for axis, values in (
                        ("on", unihan_entry.on_readings),
                        ("kun", unihan_entry.kun_readings),
                    ):
                        readings.extend(
                            Reading(axis, value)
                            for value in values
                            if _contains_kana(value)
                        )
                if (
                    not any(r.lang_axis in {"on", "kun"} for r in readings)
                    and supplement is not None
                ):
                    readings.extend(
                        Reading(axis, value)
                        for axis, value in supplement.readings
                    )

        glosses = list(exact.glosses) if exact is not None else []
        if not any(gloss.lang == "en" for gloss in glosses):
            for candidate in kanjidic_fallbacks:
                english = [
                    gloss for gloss in candidate.glosses if gloss.lang == "en"
                ]
                if english:
                    glosses.extend(english)
                    break
            else:
                if unihan_entry is not None and unihan_entry.definition:
                    glosses.append(Gloss("en", unihan_entry.definition))
                elif supplement is not None:
                    glosses.extend(
                        Gloss("en", value)
                        for value in supplement.english_glosses
                    )

        resolved[literal] = Kanji(
            literal=literal,
            codepoint=ord(literal),
            stroke_count=stroke_count,
            grade=exact.grade if exact is not None else None,
            freq_rank=exact.freq_rank if exact is not None else None,
            radical=radical,
            jlpt_level=exact.jlpt_level if exact is not None else None,
            kanken_level=exact.kanken_level if exact is not None else None,
            readings=readings,
            glosses=glosses,
        )

    selected: list[Kanji] = []
    selected_literals: set[str] = set()
    advanced_set = set(advanced_literals)
    for item in kanji:
        if item.grade in JOYO_GRADES or item.literal in advanced_set:
            selected.append(resolved.get(item.literal, item))
            selected_literals.add(item.literal)
    for literal in advanced_literals:
        if literal not in selected_literals and literal in resolved:
            selected.append(resolved[literal])
            selected_literals.add(literal)
    return selected


def _contains_kana(value: str) -> bool:
    return any(
        "\u3040" <= character <= "\u30ff"
        for character in value
    )


def advanced_coverage(
    kanji: list[Kanji],
    allocations: list[KankenAllocation],
) -> dict[str, int]:
    expected = {
        allocation.literal
        for allocation in allocations
        if allocation.literal is not None
        and allocation.source_level in ADVANCED_KANKEN_LEVELS
    }
    by_literal = {item.literal: item for item in kanji}
    return {
        "missing_advanced_inventory": sum(
            literal not in by_literal for literal in expected
        ),
        "missing_advanced_reading": sum(
            literal not in by_literal
            or not any(
                reading.lang_axis in {"on", "kun"}
                for reading in by_literal[literal].readings
            )
            for literal in expected
        ),
        "missing_advanced_meaning": sum(
            literal not in by_literal
            or not any(
                gloss.lang == "en"
                for gloss in by_literal[literal].glosses
            )
            for literal in expected
        ),
    }
