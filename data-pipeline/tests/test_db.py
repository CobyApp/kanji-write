from kanjipipe.db import init_db


def test_init_db_creates_core_tables():
    conn = init_db(":memory:")
    tables = {row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    assert {"kanji", "reading", "gloss"} <= tables


def test_init_db_enables_foreign_keys():
    conn = init_db(":memory:")
    assert conn.execute("PRAGMA foreign_keys").fetchone()[0] == 1
