# tests/test_loader.py
import pytest

from kanjipipe.db import init_db
from kanjipipe.loader import (
    load_kanji,
    load_kanken_memberships,
    load_llm_glosses,
    load_relations,
    load_sentence_glosses,
    load_sentence_words,
    load_sentences,
    load_stroke_order,
    load_word_jazh_glosses,
    load_word_ko_glosses,
    load_words,
)
from kanjipipe.models import (
    Gloss,
    Kanji,
    KankenAllocation,
    LlmGloss,
    Reading,
    Relation,
    Sentence,
    Word,
)


def _yama():
    return Kanji(
        literal="山", codepoint=0x5C71, stroke_count=3, grade=1,
        freq_rank=360, radical=46, jlpt_level="N5", kanken_level="10級",
        readings=[Reading("on", "サン"), Reading("kun", "やま"),
                  Reading("pinyin", "shan1"), Reading("eum", "산")],
        glosses=[Gloss("en", "mountain")],
    )


def test_inserts_kanji_with_readings_and_glosses():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])

    row = conn.execute(
        "SELECT literal, stroke_count, grade, jlpt_level, kanken_level, freq_rank, radical "
        "FROM kanji").fetchone()
    assert row == ("山", 3, 1, "N5", "10級", 360, 46)

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


def _advanced_kanji(literal: str) -> Kanji:
    return Kanji(
        literal=literal,
        codepoint=ord(literal),
        stroke_count=8,
        grade=None,
        freq_rank=None,
        radical=7,
    )


def _allocation(literal: str | None, level: str) -> KankenAllocation:
    return KankenAllocation(
        ct_id="CT-000002",
        ce_id="CE-000003",
        literal=literal,
        variant_kind="旧字",
        source_level=level,
    )


def test_shared_allocation_loads_two_memberships_with_pre1_intro_level():
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced_kanji("亞")])

    load_kanken_memberships(conn, [_allocation("亞", "1/準1級")])

    memberships = conn.execute(
        "SELECT level_label, source_classification "
        "FROM kanken_membership ORDER BY level_label"
    ).fetchall()
    assert memberships == [
        ("1級", "1/準1級"),
        ("準1級", "1/準1級"),
    ]
    assert conn.execute(
        "SELECT kanken_level FROM kanji WHERE literal = '亞'"
    ).fetchone() == ("準1級",)


@pytest.mark.parametrize(
    "levels",
    [
        ("5級", "1級"),
        ("1級", "5級"),
    ],
)
def test_duplicate_literal_keeps_earliest_introduction_level_regardless_of_order(
    levels: tuple[str, str],
):
    conn = init_db(":memory:")
    load_kanji(conn, [_advanced_kanji("缶")])

    load_kanken_memberships(
        conn,
        [_allocation("缶", level) for level in levels],
    )

    memberships = conn.execute(
        "SELECT level_label FROM kanken_membership ORDER BY level_label"
    ).fetchall()
    assert memberships == [("1級",), ("5級",)]
    assert conn.execute(
        "SELECT kanken_level FROM kanji WHERE literal = '缶'"
    ).fetchone() == ("5級",)


def test_unicode_allocation_absent_from_inventory_is_rejected():
    conn = init_db(":memory:")

    with pytest.raises(ValueError, match="not present in selected inventory: 亞"):
        load_kanken_memberships(conn, [_allocation("亞", "準1級")])


def test_image_only_allocation_is_deferred_without_membership():
    conn = init_db(":memory:")

    load_kanken_memberships(conn, [_allocation(None, "1級")])

    assert conn.execute("SELECT COUNT(*) FROM kanken_membership").fetchone() == (0,)


def test_load_stroke_order_links_by_codepoint_in_order():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山, codepoint 0x5C71

    load_stroke_order(conn, {0x5C71: ["d1", "d2", "d3"]})

    rows = conn.execute(
        "SELECT ordinal, path_d FROM stroke_order so "
        "JOIN kanji k ON so.kanji_id = k.id WHERE k.literal = '山' "
        "ORDER BY ordinal").fetchall()
    assert rows == [(1, "d1"), (2, "d2"), (3, "d3")]
    assert conn.execute(
        "SELECT has_verified_stroke_order FROM kanji WHERE literal = '山'"
    ).fetchone() == (1,)


def test_load_stroke_order_skips_kanji_absent_from_map():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_stroke_order(conn, {})  # no strokes provided
    count = conn.execute("SELECT COUNT(*) FROM stroke_order").fetchone()[0]
    assert count == 0
    assert conn.execute(
        "SELECT has_verified_stroke_order FROM kanji WHERE literal = '山'"
    ).fetchone() == (0,)


def _gaku():
    return Kanji(literal="学", codepoint=0x5B66, stroke_count=8, grade=1,
                 freq_rank=63, radical=39, jlpt_level="N5",
                 readings=[Reading("on", "ガク")], glosses=[Gloss("en", "study")])


def test_load_words_links_each_joyo_kanji_in_surface():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama(), _gaku()])  # 山, 学

    load_words(conn, [
        Word(surface="学校", reading_kana="がっこう", en_glosses=["school"]),
        Word(surface="山", reading_kana="やま", en_glosses=["mountain"]),
    ])

    # 学校 links to 学 (校 is not a seeded kanji, so no link to it)
    gakkou_links = conn.execute(
        "SELECT k.literal FROM word_kanji wk "
        "JOIN word w ON wk.word_id = w.id JOIN kanji k ON wk.kanji_id = k.id "
        "WHERE w.surface = '学校'").fetchall()
    assert gakkou_links == [("学",)]

    # gloss stored
    gloss = conn.execute(
        "SELECT lang, text FROM word_gloss g JOIN word w ON g.word_id = w.id "
        "WHERE w.surface = '山'").fetchone()
    assert gloss == ("en", "mountain")


def test_load_words_word_without_joyo_kanji_has_no_links():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_words(conn, [Word(surface="校", reading_kana="こう", en_glosses=["school"])])
    assert conn.execute("SELECT COUNT(*) FROM word").fetchone()[0] == 1
    assert conn.execute("SELECT COUNT(*) FROM word_kanji").fetchone()[0] == 0


def test_common_words_keep_their_ids_when_uncommon_ones_are_added():
    """word_glosses_ko.jsonl addresses words by autoincrement id.

    So inserting uncommon words in JMdict order — interleaved among the common
    ones — silently repoints every later gloss at the wrong word (学校 came out
    meaning "정면 폭"). Common words must keep the ids they had before uncommon
    vocabulary existed, which means loading them first, in their original order.
    """
    conn = init_db(":memory:")
    load_kanji(conn, [_yama(), _gaku()])

    load_words(
        conn,
        [
            Word(surface="山", reading_kana="やま", en_glosses=["mountain"]),
            Word(surface="山学", reading_kana="やまがく", is_common=False,
                 en_glosses=["obscure"]),
            Word(surface="学", reading_kana="がく", en_glosses=["study"]),
        ],
        advanced_literals={"学"},
    )

    ids = dict(conn.execute("SELECT surface, id FROM word"))
    assert ids["山"] == 1
    assert ids["学"] == 2          # NOT 3 — the uncommon word must not displace it
    assert ids["山学"] == 3


def test_uncommon_word_links_only_to_the_advanced_kanji_that_justified_it():
    """An uncommon word is pulled in for its 準1級/1級 kanji, so it must not
    surface under the everyday kanji it happens to also contain — otherwise a
    10級 word list fills up with things like 「ランブル鞭毛虫症」.
    """
    conn = init_db(":memory:")
    load_kanji(conn, [_yama(), _gaku()])  # 山 (everyday), 学 (stands in for advanced)

    load_words(
        conn,
        [Word(surface="山学", reading_kana="やまがく", is_common=False,
              en_glosses=["obscure"])],
        advanced_literals={"学"},
    )

    links = conn.execute(
        "SELECT k.literal FROM word_kanji wk JOIN kanji k ON k.id = wk.kanji_id"
    ).fetchall()
    assert links == [("学",)]


def test_common_word_still_links_to_every_seeded_kanji():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama(), _gaku()])

    load_words(
        conn,
        [Word(surface="山学", reading_kana="やまがく", en_glosses=["common"])],
        advanced_literals={"学"},
    )

    links = {row[0] for row in conn.execute(
        "SELECT k.literal FROM word_kanji wk JOIN kanji k ON k.id = wk.kanji_id")}
    assert links == {"山", "学"}


def test_load_sentences_caps_per_kanji_and_prefers_short():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山

    load_sentences(conn, [
        Sentence(ja_text="山。", translations={"en": "Mountain."}),          # shortest
        Sentence(ja_text="山が高い。", translations={"en": "The mountain is high."}),
        Sentence(ja_text="あの山はとても高いです。", translations={"en": "long"}),
    ], per_kanji_cap=1)

    rows = conn.execute(
        "SELECT s.text_ja FROM sentence s "
        "JOIN sentence_kanji sk ON sk.sentence_id = s.id "
        "JOIN kanji k ON sk.kanji_id = k.id WHERE k.literal = '山'").fetchall()
    assert rows == [("山。",)]                                   # only the shortest, cap honored
    assert conn.execute("SELECT COUNT(*) FROM sentence").fetchone()[0] == 1
    tr = conn.execute("SELECT lang, text FROM sentence_translation").fetchone()
    assert tr == ("en", "Mountain.")


def test_load_sentences_skips_sentence_without_joyo_kanji():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_sentences(conn, [Sentence(ja_text="これはペンです。", translations={"en": "This is a pen."})])
    assert conn.execute("SELECT COUNT(*) FROM sentence").fetchone()[0] == 0


def test_load_sentences_links_words_by_shared_kanji_and_surface():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山
    load_words(conn, [
        Word(surface="山", reading_kana="やま", en_glosses=["mountain"]),
        Word(surface="富士山", reading_kana="ふじさん", en_glosses=["Mt. Fuji"]),  # shares 山, in text
        Word(surface="山道", reading_kana="やまみち", en_glosses=["mountain path"]),  # shares 山, NOT in text
    ])
    load_sentences(conn, [Sentence(ja_text="富士山は高い。", translations={"en": "Fuji is high."})])
    load_sentence_words(conn)

    linked = conn.execute(
        "SELECT w.surface FROM sentence_word sw JOIN word w ON w.id = sw.word_id "
        "ORDER BY w.surface").fetchall()
    # both surfaces present as substrings link; 山道 (absent from text) does not
    assert linked == [("富士山",), ("山",)]


def test_load_sentences_word_link_respects_cap_and_requires_substring():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_words(conn, [
        Word(surface="山", reading_kana="やま", en_glosses=["mountain"]),
        Word(surface="登山", reading_kana="とざん", en_glosses=["climbing"]),  # shares 山, never in text
    ])
    load_sentences(conn, [
        Sentence(ja_text="山。", translations={"en": "1"}),
        Sentence(ja_text="山が。", translations={"en": "2"}),
        Sentence(ja_text="山だ。", translations={"en": "3"}),
    ], per_kanji_cap=5)
    load_sentence_words(conn, per_word_cap=2)

    yama = conn.execute(
        "SELECT COUNT(*) FROM sentence_word sw JOIN word w ON w.id = sw.word_id "
        "WHERE w.surface = '山'").fetchone()[0]
    tozan = conn.execute(
        "SELECT COUNT(*) FROM sentence_word sw JOIN word w ON w.id = sw.word_id "
        "WHERE w.surface = '登山'").fetchone()[0]
    assert yama == 2   # substring in all 3, capped at 2 (shortest first)
    assert tozan == 0  # shares 山 but surface never appears


def test_load_sentence_glosses_attaches_ko_zh_by_text():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_sentences(conn, [Sentence(ja_text="山。", translations={"en": "Mountain."})])

    load_sentence_glosses(conn, [("山。", "산.", "山。"), ("知らない文。", "무시됨", None)])

    rows = dict(conn.execute("SELECT lang, text FROM sentence_translation").fetchall())
    assert rows == {"en": "Mountain.", "ko": "산.", "zh": "山。"}


def test_load_sentence_glosses_does_not_overwrite_existing_lang():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    # Tatoeba already supplied a ko translation for this sentence.
    load_sentences(conn, [Sentence(ja_text="山。", translations={"ko": "기존 번역"})])

    load_sentence_glosses(conn, [("山。", "새 번역", "山。")])

    ko = conn.execute(
        "SELECT text FROM sentence_translation WHERE lang = 'ko'").fetchall()
    assert ko == [("기존 번역",)]  # existing ko kept, not duplicated
    zh = conn.execute(
        "SELECT text FROM sentence_translation WHERE lang = 'zh'").fetchone()
    assert zh == ("山。",)  # zh newly added


def test_load_relations_links_stored_words_only():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])
    load_words(conn, [
        Word(surface="山", reading_kana="やま", en_glosses=["mountain"]),
        Word(surface="学校", reading_kana="がっこう", en_glosses=["school"]),
    ])

    load_relations(conn, [
        Relation(source_surface="山", target_surface="学校", type="related"),
        Relation(source_surface="山", target_surface="未登録語", type="antonym"),  # target not stored
    ])

    rows = conn.execute(
        "SELECT a.surface, b.surface, r.type FROM relation r "
        "JOIN word a ON r.word_id_a = a.id JOIN word b ON r.word_id_b = b.id"
    ).fetchall()
    assert rows == [("山", "学校", "related")]   # the unstored-target relation is skipped


def test_load_relations_dedupes_via_unique():
    conn = init_db(":memory:")
    load_words(conn, [
        Word(surface="山", reading_kana="やま", en_glosses=[]),
        Word(surface="学校", reading_kana="がっこう", en_glosses=[]),
    ])
    rel = Relation(source_surface="山", target_surface="学校", type="related")
    load_relations(conn, [rel, rel])  # duplicate
    assert conn.execute("SELECT COUNT(*) FROM relation").fetchone()[0] == 1


def test_load_word_ko_glosses_inserts_ko_word_gloss():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山
    load_words(conn, [Word(surface="山", reading_kana="やま", en_glosses=["mountain"])])
    word_id = conn.execute("SELECT id FROM word WHERE surface = '山'").fetchone()[0]

    load_word_ko_glosses(conn, [(word_id, "산")])

    ko = conn.execute(
        "SELECT lang, text FROM word_gloss WHERE word_id = ? AND lang = 'ko'",
        (word_id,),
    ).fetchone()
    assert ko == ("ko", "산")
    # the original English gloss is untouched
    en = conn.execute(
        "SELECT text FROM word_gloss WHERE word_id = ? AND lang = 'en'",
        (word_id,),
    ).fetchone()
    assert en == ("mountain",)


def test_load_word_jazh_glosses_inserts_ja_and_zh_word_glosses():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山
    load_words(conn, [Word(surface="山", reading_kana="やま", en_glosses=["mountain"])])
    word_id = conn.execute("SELECT id FROM word WHERE surface = '山'").fetchone()[0]

    load_word_jazh_glosses(conn, [(word_id, "やま", "山")])

    rows = conn.execute(
        "SELECT lang, text FROM word_gloss WHERE word_id = ? AND lang IN ('ja', 'zh') "
        "ORDER BY lang",
        (word_id,),
    ).fetchall()
    assert rows == [("ja", "やま"), ("zh", "山")]


def test_load_word_jazh_glosses_with_only_zh_inserts_only_zh():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山
    load_words(conn, [Word(surface="山", reading_kana="やま", en_glosses=["mountain"])])
    word_id = conn.execute("SELECT id FROM word WHERE surface = '山'").fetchone()[0]

    load_word_jazh_glosses(conn, [(word_id, None, "山")])

    rows = conn.execute(
        "SELECT lang, text FROM word_gloss WHERE word_id = ? AND lang IN ('ja', 'zh') "
        "ORDER BY lang",
        (word_id,),
    ).fetchall()
    assert rows == [("zh", "山")]


def test_load_word_jazh_glosses_with_only_ja_inserts_only_ja():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山
    load_words(conn, [Word(surface="山", reading_kana="やま", en_glosses=["mountain"])])
    word_id = conn.execute("SELECT id FROM word WHERE surface = '山'").fetchone()[0]

    load_word_jazh_glosses(conn, [(word_id, "やま", None)])

    rows = conn.execute(
        "SELECT lang, text FROM word_gloss WHERE word_id = ? AND lang IN ('ja', 'zh') "
        "ORDER BY lang",
        (word_id,),
    ).fetchall()
    assert rows == [("ja", "やま")]


def test_load_llm_glosses_inserts_native_glosses_with_source():
    conn = init_db(":memory:")
    load_kanji(conn, [_yama()])  # 山, with an EN gloss (source NULL)

    load_llm_glosses(conn, [
        LlmGloss(literal="山", ko="메 산", ja="やま。", zh="山。"),
        LlmGloss(literal="未", ko="아닐 미"),  # not a stored kanji → skipped
    ])

    rows = conn.execute(
        "SELECT g.lang, g.text, g.source FROM gloss g "
        "JOIN kanji k ON g.kanji_id = k.id "
        "WHERE k.literal = '山' AND g.source = 'llm' ORDER BY g.lang").fetchall()
    assert rows == [("ja", "やま。", "llm"), ("ko", "메 산", "llm"), ("zh", "山。", "llm")]

    # the original English gloss is untouched (source NULL)
    en = conn.execute(
        "SELECT text, source FROM gloss g JOIN kanji k ON g.kanji_id = k.id "
        "WHERE k.literal = '山' AND g.lang = 'en'").fetchone()
    assert en == ("mountain", None)

    # the unstored literal produced no rows
    assert conn.execute("SELECT COUNT(*) FROM gloss WHERE lang='ko'").fetchone()[0] == 1


def _compat(literal: str, codepoint: int, stroke_count: int):
    """A CJK Compatibility Ideograph entry (U+F900–FAFF)."""
    return Kanji(literal=literal, codepoint=codepoint, stroke_count=stroke_count,
                 grade=None, freq_rank=None, radical=113, jlpt_level=None,
                 readings=[Reading("on", "シン")], glosses=[Gloss("en", "god")])


def test_compat_ideograph_borrows_unified_strokes_when_counts_agree():
    # 神 U+FA19 is canonically equivalent to 神 U+795E; when the unified glyph has
    # the same number of strokes it is the same shape, so the paths carry over.
    conn = init_db(":memory:")
    load_kanji(conn, [_compat("神", 0xFA19, 9)])

    load_stroke_order(conn, {0x795E: [f"d{i}" for i in range(1, 10)]})

    assert conn.execute("SELECT COUNT(*) FROM stroke_order").fetchone()[0] == 9
    assert conn.execute(
        "SELECT has_verified_stroke_order FROM kanji WHERE literal = '神'"
    ).fetchone() == (1,)


def test_compat_ideograph_refuses_unified_strokes_when_counts_differ():
    # 隆 U+F9DC is the 17-stroke printed form; the unified 隆 U+9686 has 11. The
    # shapes genuinely differ, so borrowing would teach the wrong stroke order.
    conn = init_db(":memory:")
    load_kanji(conn, [_compat("隆", 0xF9DC, 17)])

    load_stroke_order(conn, {0x9686: [f"d{i}" for i in range(1, 12)]})

    assert conn.execute("SELECT COUNT(*) FROM stroke_order").fetchone()[0] == 0
    assert conn.execute(
        "SELECT has_verified_stroke_order FROM kanji WHERE literal = '隆'"
    ).fetchone() == (0,)
