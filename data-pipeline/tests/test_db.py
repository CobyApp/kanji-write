import sqlite3

import pytest

from kanjipipe.db import init_db


def test_init_db_creates_core_tables():
    conn = init_db(":memory:")
    tables = {row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    assert {"kanji", "reading", "gloss", "stroke_order",
            "word", "word_kanji", "word_gloss"} <= tables


def test_init_db_enables_foreign_keys():
    conn = init_db(":memory:")
    assert conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1


def test_foreign_keys_are_enforced():
    conn = init_db(":memory:")
    # Inserting a reading that references a non-existent kanji must be rejected.
    with pytest.raises(sqlite3.IntegrityError):
        conn.execute(
            "INSERT INTO reading (kanji_id, lang_axis, value) VALUES (999, 'on', 'サン')")
        conn.commit()
