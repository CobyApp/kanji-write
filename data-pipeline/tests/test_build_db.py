# tests/test_build_db.py
from pathlib import Path

from kanjipipe.build_db import build

FIX = Path(__file__).parent / "fixtures"


def test_build_produces_sqlite_with_strokes(tmp_path):
    out = tmp_path / "kanji.sqlite"
    report = build(
        kanjidic2_path=FIX / "kanjidic2_sample.xml",
        jlpt_path=FIX / "jlpt_sample.json",
        kanjivg_path=FIX / "kanjivg_sample.xml",
        jmdict_path=FIX / "jmdict_sample.xml",
        out_path=str(out),
    )
    assert out.exists()
    assert report["total"] == 2          # 山, 学 — 龠 filtered out
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0
    assert report["missing_stroke_order"] == 0

    import sqlite3
    with sqlite3.connect(out) as conn:
        literals = {r[0] for r in conn.execute("SELECT literal FROM kanji")}
        assert literals == {"山", "学"}
        yama_strokes = conn.execute(
            "SELECT so.path_d FROM stroke_order so JOIN kanji k ON so.kanji_id = k.id "
            "WHERE k.literal = '山' ORDER BY so.ordinal").fetchall()
        assert [r[0] for r in yama_strokes] == ["M21,30 L21,70", "M50,20 L50,80", "M79,30 L79,70"]
        gaku_count = conn.execute(
            "SELECT COUNT(*) FROM stroke_order so JOIN kanji k ON so.kanji_id = k.id "
            "WHERE k.literal = '学'").fetchone()[0]
        assert gaku_count == 8
        # 山 has the word 山 linked
        yama_words = conn.execute(
            "SELECT w.surface FROM word w "
            "JOIN word_kanji wk ON wk.word_id = w.id "
            "JOIN kanji k ON wk.kanji_id = k.id "
            "WHERE k.literal = '山' ORDER BY w.surface").fetchall()
        assert ("山",) in yama_words
    conn.close()
