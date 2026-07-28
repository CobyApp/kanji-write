# tests/test_build_db.py
import sqlite3
from pathlib import Path

import pytest

from kanjipipe.build_db import build
from kanjipipe.filters import select_study_inventory
from kanjipipe.models import Gloss, Kanji, KankenAllocation, Reading
from kanjipipe.validate import KankenCountPolicy

FIX = Path(__file__).parent / "fixtures"
RESOURCES = Path(__file__).parents[2] / "app/Sources/DictionaryClient/Resources"
FIXTURE_KANKEN_COUNT_POLICY = KankenCountPolicy(
    legacy_memberships={"10級": 1, "9級": 1},
    unicode_advanced=1,
    image_pending=1,
    advanced_memberships={"準1級": 1, "1級": 1},
    shared_advanced=1,
)


def _kanji(literal: str, grade: int | None) -> Kanji:
    return Kanji(
        literal=literal,
        codepoint=ord(literal),
        stroke_count=1,
        grade=grade,
        freq_rank=None,
        radical=None,
        readings=[Reading("on", "ア")],
        glosses=[Gloss("en", "sample")],
    )


def _allocation(
    literal: str | None,
    level: str,
    ce_id: str = "CE-unicode",
) -> KankenAllocation:
    return KankenAllocation(
        ct_id="CT-sample",
        ce_id=ce_id,
        literal=literal,
        variant_kind="標準字体",
        source_level=level,
    )


def test_inventory_keeps_joyo_and_unicode_advanced_only():
    selected = select_study_inventory(
        [_kanji("山", 1), _kanji("亞", None), _kanji("齷", None)],
        [
            _allocation("亞", "準1級"),
            _allocation(None, "1級", ce_id="CE-image"),
        ],
    )

    assert [item.literal for item in selected] == ["山", "亞"]


def test_build_reports_unknown_kanken_levels_deterministically(tmp_path):
    kanken = tmp_path / "kanken.csv"
    kanken.write_text(
        "字種ID,字項ID,漢字テキスト,字体,漢検級\n"
        "CT-1,CE-1,山,標準字体,超級\n"
        "CT-2,CE-2,学,標準字体,特級\n",
        encoding="utf-8",
    )

    with pytest.raises(ValueError, match="unknown Kanken level: 特級"):
        build(
            kanjidic2_path=FIX / "kanjidic2_sample.xml",
            jlpt_path=FIX / "jlpt_sample.json",
            kanjivg_path=FIX / "kanjivg_sample.xml",
            jmdict_path=FIX / "jmdict_sample.xml",
            sentences_path=FIX / "sentences_sample.csv",
            links_path=FIX / "links_sample.csv",
            kanken_path=kanken,
            unihan_path=None,
            out_path=str(tmp_path / "kanji.sqlite"),
        )


def test_build_produces_sqlite_with_strokes(tmp_path):
    out = tmp_path / "kanji.sqlite"
    report = build(
        kanjidic2_path=FIX / "kanjidic2_sample.xml",
        jlpt_path=FIX / "jlpt_sample.json",
        kanjivg_path=FIX / "kanjivg_sample.xml",
        jmdict_path=FIX / "jmdict_sample.xml",
        sentences_path=FIX / "sentences_sample.csv",
        links_path=FIX / "links_sample.csv",
        kanken_path=FIX / "kanken_build_sample.csv",
        llm_glosses_path=FIX / "llm_glosses_sample.jsonl",
        word_ko_path=FIX / "word_glosses_ko_sample.jsonl",
        word_jazh_path=FIX / "word_glosses_jazh_sample.jsonl",
        yojijukugo_path=RESOURCES / "yojijukugo.source.json",
        taigirui_path=RESOURCES / "taigirui.source.json",
        unihan_path=None,
        kanken_count_policy=FIXTURE_KANKEN_COUNT_POLICY,
        out_path=str(out),
    )
    assert out.exists()
    assert report["total"] == 3          # 山, 学, 亞 — 龠 filtered out
    assert report["missing_reading"] == 0
    assert report["missing_en"] == 0
    assert report["missing_stroke_order"] == 1
    assert report["kanken_unicode_advanced"] == 1
    assert report["kanken_image_pending"] == 1
    assert report["missing_kanken_membership"] == 0
    assert report["missing_advanced_inventory"] == 0
    assert report["missing_advanced_reading"] == 0
    assert report["missing_advanced_meaning"] == 0
    assert report["stroke_capability_mismatch"] == 0

    import sqlite3
    with sqlite3.connect(out) as conn:
        literals = {r[0] for r in conn.execute("SELECT literal FROM kanji")}
        assert literals == {"山", "学", "亞"}
        assert conn.execute(
            "SELECT COUNT(*) FROM kanken_membership WHERE level_label = '準1級'"
        ).fetchone()[0] == 1
        assert conn.execute(
            "SELECT COUNT(*) FROM kanken_membership WHERE level_label = '1級'"
        ).fetchone()[0] == 1
        assert conn.execute(
            "SELECT COUNT(*) FROM stroke_order so "
            "JOIN kanji k ON so.kanji_id = k.id WHERE k.literal = '亞'"
        ).fetchone()[0] == 0
        capabilities = dict(conn.execute(
            "SELECT literal, has_verified_stroke_order FROM kanji"
        ))
        assert capabilities == {"山": 1, "学": 1, "亞": 0}
        assert conn.execute(
            "SELECT reading, meaning_ja, meaning_ko, kanken_level "
            "FROM yojijukugo WHERE yoji = '悪口雑言'"
        ).fetchone() == (
            "あっこうぞうごん",
            "口ぎたなくさんざんに悪口を言うこと。",
            "온갖 욕설을 마구 퍼붓는 것.",
            "5級",
        )
        assert conn.execute(
            "SELECT word_reading, answer, answer_reading, relation, kanken_level "
            "FROM taigirui WHERE word = '進級'"
        ).fetchone() == ("しんきゅう", "留年", "りゅうねん", "対義", "5級")
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
        # 山 word (jmdict id 1) gets its Korean word gloss from word_glosses_ko_sample.jsonl
        word_ko = conn.execute(
            "SELECT wg.text FROM word_gloss wg JOIN word w ON wg.word_id = w.id "
            "WHERE w.surface = '山' AND wg.lang = 'ko'").fetchone()
        assert word_ko == ("산",)
        # 山 word (jmdict id 1) gets ja + zh word glosses from word_glosses_jazh_sample.jsonl
        word_ja = conn.execute(
            "SELECT wg.text FROM word_gloss wg JOIN word w ON wg.word_id = w.id "
            "WHERE w.surface = '山' AND wg.lang = 'ja'").fetchone()
        assert word_ja == ("やま",)
        word_zh = conn.execute(
            "SELECT wg.text FROM word_gloss wg JOIN word w ON wg.word_id = w.id "
            "WHERE w.surface = '山' AND wg.lang = 'zh'").fetchone()
        assert word_zh == ("山",)
    conn.close()


def test_build_uses_canonical_kanken_count_policy_by_default(tmp_path):
    with pytest.raises(
        ValueError,
        match="kanken_unicode_advanced expected 3806, got 1",
    ):
        build(
            kanjidic2_path=FIX / "kanjidic2_sample.xml",
            jlpt_path=FIX / "jlpt_sample.json",
            kanjivg_path=FIX / "kanjivg_sample.xml",
            jmdict_path=FIX / "jmdict_sample.xml",
            sentences_path=FIX / "sentences_sample.csv",
            links_path=FIX / "links_sample.csv",
            kanken_path=FIX / "kanken_build_sample.csv",
            llm_glosses_path=FIX / "llm_glosses_sample.jsonl",
            word_ko_path=FIX / "word_glosses_ko_sample.jsonl",
            word_jazh_path=FIX / "word_glosses_jazh_sample.jsonl",
            yojijukugo_path=RESOURCES / "yojijukugo.source.json",
            taigirui_path=RESOURCES / "taigirui.source.json",
            unihan_path=None,
            out_path=str(tmp_path / "kanji.sqlite"),
        )


def test_build_pulls_uncommon_vocabulary_for_advanced_kanji(tmp_path):
    """準1級/1級 kanji must gain vocabulary even from uncommon JMdict entries.

    Regression guard: the advanced literal set was once derived from
    `Kanji.kanken_level`, which is still None at that point in the build, so the
    widening silently did nothing and the advanced exam sections stayed empty.
    """
    jmdict = tmp_path / "jmdict.xml"
    jmdict.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<JMdict>'
        # common, ordinary kanji — kept as always
        '<entry><k_ele><keb>山</keb><ke_pri>news1</ke_pri></k_ele>'
        '<r_ele><reb>やま</reb></r_ele><sense><gloss>mountain</gloss></sense></entry>'
        # uncommon, but written with 亞 (準1級) — must now be kept
        '<entry><k_ele><keb>亞流</keb></k_ele>'
        '<r_ele><reb>ありゅう</reb></r_ele><sense><gloss>epigone</gloss></sense></entry>'
        # uncommon and no advanced kanji — must stay out
        '<entry><k_ele><keb>山岳</keb></k_ele>'
        '<r_ele><reb>さんがく</reb></r_ele><sense><gloss>mountains</gloss></sense></entry>',
        encoding="utf-8")
    jmdict.write_text(jmdict.read_text(encoding="utf-8") + "</JMdict>", encoding="utf-8")

    out = tmp_path / "kanji.sqlite"
    build(
        kanjidic2_path=FIX / "kanjidic2_sample.xml",
        jlpt_path=FIX / "jlpt_sample.json",
        kanjivg_path=FIX / "kanjivg_sample.xml",
        jmdict_path=jmdict,
        sentences_path=FIX / "sentences_sample.csv",
        links_path=FIX / "links_sample.csv",
        kanken_path=FIX / "kanken_build_sample.csv",
        llm_glosses_path=FIX / "llm_glosses_sample.jsonl",
        yojijukugo_path=RESOURCES / "yojijukugo.source.json",
        taigirui_path=RESOURCES / "taigirui.source.json",
        unihan_path=None,
        kanken_count_policy=FIXTURE_KANKEN_COUNT_POLICY,
        out_path=str(out),
    )

    con = sqlite3.connect(out)
    surfaces = {row[0] for row in con.execute("SELECT surface FROM word")}
    assert surfaces == {"山", "亞流"}
    assert con.execute(
        "SELECT is_common FROM word WHERE surface = '亞流'").fetchone()[0] == 0
    # …and it is actually reachable from the advanced kanji, which is the point.
    linked = con.execute(
        "SELECT w.surface FROM word w JOIN word_kanji wk ON wk.word_id = w.id "
        "JOIN kanji k ON k.id = wk.kanji_id WHERE k.literal = '亞'").fetchall()
    assert [row[0] for row in linked] == ["亞流"]
