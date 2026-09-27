"""Look-alike kanji: pairs that share the parts they are built from.

待 / 持 / 特 / 時 differ only by the left-hand radical and are mixed up on every
誤字訂正 paper. KanjiVG already tells us each kanji's radical form and parts
(kanji.radical_form / kanji.parts), so similarity is the overlap of those part
sets (Jaccard), minus a little for every stroke of difference. Single strokes
(一 丨 丿 …) are ignored — nearly every kanji "contains" them.
"""
from __future__ import annotations

import json
import sqlite3
from collections import defaultdict

_STROKES = set("丿丶一丨乙亅")
_LEVELS = ("10級", "9級", "8級", "7級", "6級", "5級", "4級", "3級",
           "準2級", "2級", "準1級", "1級")
_RANK = {level: i for i, level in enumerate(_LEVELS)}
_EVERYDAY_CEILING = _RANK["2級"]


def compute_similar(conn: sqlite3.Connection, per_kanji: int = 6,
                    threshold: float = 0.3) -> dict[int, list[int]]:
    rank: dict[int, int] = {}
    for kid, level in conn.execute("SELECT kanji_id, level_label FROM kanken_membership"):
        if level in _RANK:
            rank[kid] = min(_RANK[level], rank.get(kid, 99))
    features: dict[int, tuple[set[str], int]] = {}
    for kid, form, parts, strokes in conn.execute(
            "SELECT id, radical_form, parts, stroke_count FROM kanji WHERE parts IS NOT NULL"):
        pieces = set(json.loads(parts)) | {form}
        pieces -= _STROKES
        if pieces:
            features[kid] = (pieces, strokes)
    by_part: dict[str, set[int]] = defaultdict(set)
    for kid, (pieces, _) in features.items():
        for piece in pieces:
            by_part[piece].add(kid)

    result: dict[int, list[int]] = {}
    for kid, (pieces, strokes) in features.items():
        # An everyday kanji is compared with everyday kanji only; an advanced
        # one may be confused with anything.
        ceiling = max(rank.get(kid, 99), _EVERYDAY_CEILING)
        candidates = set().union(*(by_part[p] for p in pieces)) - {kid}
        scored = []
        for other in candidates:
            if rank.get(other, 99) > ceiling:
                continue
            other_pieces, other_strokes = features[other]
            score = (len(pieces & other_pieces) / len(pieces | other_pieces)
                     - 0.03 * abs(strokes - other_strokes))
            if score >= threshold:
                scored.append((score, other))
        scored.sort(key=lambda s: (-s[0], s[1]))
        if scored:
            result[kid] = [other for _, other in scored[:per_kanji]]
    return result


def load_similar(conn: sqlite3.Connection) -> int:
    conn.execute("""
        CREATE TABLE IF NOT EXISTS kanji_similar (
            kanji_id   INTEGER NOT NULL REFERENCES kanji(id),
            similar_id INTEGER NOT NULL REFERENCES kanji(id),
            rank       INTEGER NOT NULL,
            PRIMARY KEY (kanji_id, similar_id)
        )""")
    conn.execute("DELETE FROM kanji_similar")
    rows = [(kid, other, i)
            for kid, others in compute_similar(conn).items()
            for i, other in enumerate(others)]
    conn.executemany(
        "INSERT INTO kanji_similar (kanji_id, similar_id, rank) VALUES (?, ?, ?)", rows)
    conn.commit()
    return len(rows)
