# tests/test_loader.py
from kanjipipe.db import init_db
from kanjipipe.loader import load_kanji
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
