# tests/test_loader.py
from kanjipipe.db import init_db
from kanjipipe.loader import load_kanji, load_stroke_order
from kanjipipe.models import Gloss, Kanji, Reading


def _yama():
    return Kanji(
        literal="山", codepoint=0x5C71, stroke_count=3, grade=1,
        freq_rank=360, radical=46, jlpt_level="N5",
        readings=[Reading("on", "サン"), Reading("kun", "やま"),
                  Reading("pinyin", "shan1"), Reading("eum", "산")],
        glosses=[Gloss("en", "mountain")],
    )


def test_inserts_kanji_with_readings_and_glosses():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])

    row = conn.execute(
        "SELECT literal, stroke_count, grade, jlpt_level, freq_rank, radical "
        "FROM kanji").fetchone()
    assert row == ("山", 3, 1, "N5", 360, 46)

    reading_count = conn.execute(
        "SELECT COUNT(*) FROM reading").fetchone()[0]
    assert reading_count == 4

    gloss = conn.execute(
        "SELECT lang, text FROM gloss").fetchone()
    assert gloss == ("en", "mountain")


def test_foreign_keys_link_children_to_parent():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    linked = conn.execute(
        "SELECT COUNT(*) FROM reading r JOIN kanji k ON r.kanji_id = k.id "
        "WHERE k.literal = '山'").fetchone()[0]
    assert linked == 4


def test_load_stroke_order_links_by_codepoint_in_order():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山, codepoint 0x5C71

    load_stroke_order(conn, {0x5C71: ["d1", "d2", "d3"]})

    rows = conn.execute(
        "SELECT ordinal, path_d FROM stroke_order so "
        "JOIN kanji k ON so.kanji_id = k.id WHERE k.literal = '山' "
        "ORDER BY ordinal").fetchall()
    assert rows == [(1, "d1"), (2, "d2"), (3, "d3")]


def test_load_stroke_order_skips_kanji_absent_from_map():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_stroke_order(conn, {})  # no strokes provided
    count = conn.execute("SELECT COUNT(*) FROM stroke_order").fetchone()[0]
    assert count == 0
