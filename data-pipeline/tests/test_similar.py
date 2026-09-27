import json

from kanjipipe.db import init_db
from kanjipipe.similar import compute_similar


def _kanji(conn, kid, literal, form, parts, strokes, level="3級"):
    conn.execute(
        "INSERT INTO kanji (id, literal, codepoint, stroke_count, radical_form, parts) "
        "VALUES (?, ?, ?, ?, ?, ?)",
        (kid, literal, ord(literal), strokes, form, json.dumps(parts, ensure_ascii=False)))
    conn.execute("INSERT INTO kanken_membership VALUES (?, ?, 'test')", (kid, level))


def test_shared_parts_make_look_alikes():
    conn = init_db(":memory:")
    _kanji(conn, 1, "待", "彳", ["寺", "土", "寸"], 9)
    _kanji(conn, 2, "持", "扌", ["寺", "土", "寸"], 9)
    _kanji(conn, 3, "山", "山", [], 3)
    _kanji(conn, 4, "侍", "亻", ["寺", "土", "寸"], 8, level="1級")
    similar = compute_similar(conn)
    assert similar[1] == [2]            # 侍 is 1級 — not offered for an everyday kanji
    assert 3 not in similar             # nothing shares a part with 山
    assert set(similar[4]) == {1, 2}    # an advanced kanji may resemble anything
