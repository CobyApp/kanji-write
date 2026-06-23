# tests/test_build_db.py
from pathlib import Path

from kanjipipe.build_db import build

FIX = Path(__file__).parent / "fixtures"


def test_build_produces_sqlite_with_only_joyo(tmp_path):
    out = tmp_path / "kanji.sqlite"
    report = build(
        kanjidic2_path=FIX / "kanjidic2_sample.xml",
        jlpt_path=FIX / "jlpt_sample.json",
        out_path=str(out),
    )
    assert out.exists()
    assert report["total"] == 2          # 山, 学 — 龠 filtered out
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0

    import sqlite3
    conn = sqlite3.connect(out)
    literals = {r[0] for r in conn.execute("SELECT literal FROM kanji")}
    assert literals == {"山", "学"}
    jlpt = dict(conn.execute("SELECT literal, jlpt_level FROM kanji"))
    assert jlpt == {"山": "N5", "学": "N5"}
