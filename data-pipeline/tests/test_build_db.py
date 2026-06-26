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
        sentences_path=FIX / "sentences_sample.csv",
        links_path=FIX / "links_sample.csv",
        llm_glosses_path=FIX / "llm_glosses_sample.jsonl",
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
        yama_words = conn.execute(
            "SELECT w.surface FROM word w "
            "JOIN word_kanji wk ON wk.word_id = w.id "
            "JOIN kanji k ON wk.kanji_id = k.id "
            "WHERE k.literal = '山' ORDER BY w.surface").fetchall()
        assert ("山",) in yama_words
        # 山 has an example sentence with an English translation
        yama_sentence = conn.execute(
            "SELECT s.text_ja FROM sentence s "
            "JOIN sentence_kanji sk ON sk.sentence_id = s.id "
            "JOIN kanji k ON sk.kanji_id = k.id "
            "WHERE k.literal = '山'").fetchone()
        assert yama_sentence is not None
        en = conn.execute(
            "SELECT st.text FROM sentence_translation st "
            "JOIN sentence_kanji sk ON sk.sentence_id = st.sentence_id "
            "JOIN kanji k ON sk.kanji_id = k.id "
            "WHERE k.literal = '山' AND st.lang = 'en'").fetchone()
        assert en is not None
        # 山 ↔ 学校 relation materialized from JMdict ant/xref
        rel = conn.execute(
            "SELECT a.surface, b.surface, r.type FROM relation r "
            "JOIN word a ON r.word_id_a = a.id JOIN word b ON r.word_id_b = b.id "
            "ORDER BY r.type").fetchall()
        assert ("山", "学校", "related") in rel
        assert ("学校", "山", "antonym") in rel
        # 山 native Korean gloss from the LLM JSONL, tagged source='llm'
        ko = conn.execute(
            "SELECT g.text, g.source FROM gloss g JOIN kanji k ON g.kanji_id = k.id "
            "WHERE k.literal = '山' AND g.lang = 'ko'").fetchone()
        assert ko == ("메 산", "llm")
    conn.close()
