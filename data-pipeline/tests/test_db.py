import sqlite3

import pytest

from kanjipipe.db import init_db


def test_init_db_creates_core_tables():
    conn = init_db(":memory:")
    tables = {row[0] for row in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'")}
    assert {"kanji", "reading", "gloss", "stroke_order",
            "word", "word_kanji", "word_gloss",
            "sentence", "sentence_translation", "sentence_kanji",
            "relation"} <= tables


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


def test_schema_contains_reproducible_kanken_tables():
    conn = init_db(":memory:")
    tables = {
        row[0]
        for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
    }
    assert {
        "kanken_membership",
        "glyph_asset",
        "kanji_variant",
        "yojijukugo",
        "taigirui",
    } <= tables
    kanji_columns = {
        row[1]: row
        for row in conn.execute("PRAGMA table_info(kanji)")
    }
    columns = set(kanji_columns)
    assert "kanken_level" in columns
    assert "has_verified_stroke_order" in columns
    assert kanji_columns["has_verified_stroke_order"][3] == 1
    assert kanji_columns["has_verified_stroke_order"][4] == "0"


def test_kanken_metadata_schema_has_required_columns_and_links():
    conn = init_db(":memory:")

    glyph_columns = {
        row[1]: row[3] for row in conn.execute("PRAGMA table_info(glyph_asset)")
    }
    assert {
        "provider",
        "glyph_name",
        "revision",
        "sha256",
        "source_url",
        "license_url",
        "local_svg_name",
    } <= glyph_columns.keys()
    assert all(glyph_columns[column] == 1 for column in glyph_columns if column != "id")

    variant_columns = {
        row[1] for row in conn.execute("PRAGMA table_info(kanji_variant)")
    }
    assert {
        "canonical_kanji_id",
        "glyph_asset_id",
        "source_ct_id",
        "source_ce_id",
        "variant_kind",
    } <= variant_columns
    variant_foreign_keys = {
        (row[3], row[2]) for row in conn.execute("PRAGMA foreign_key_list(kanji_variant)")
    }
    assert {
        ("canonical_kanji_id", "kanji"),
        ("glyph_asset_id", "glyph_asset"),
    } <= variant_foreign_keys


def test_curated_kanken_tables_match_app_query_columns():
    conn = init_db(":memory:")
    yoji_columns = {
        row[1] for row in conn.execute("PRAGMA table_info(yojijukugo)")
    }
    assert {
        "id",
        "yoji",
        "reading",
        "meaning_ja",
        "meaning_ko",
        "kanken_level",
    } <= yoji_columns
    taigirui_columns = {
        row[1] for row in conn.execute("PRAGMA table_info(taigirui)")
    }
    assert {
        "id",
        "word",
        "word_reading",
        "answer",
        "answer_reading",
        "relation",
        "kanken_level",
    } <= taigirui_columns
