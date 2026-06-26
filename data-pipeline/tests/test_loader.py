# tests/test_loader.py
from kanjipipe.db import init_db
from kanjipipe.loader import load_kanji, load_relations, load_sentences, load_stroke_order, load_words
from kanjipipe.models import Gloss, Kanji, Reading, Relation, Sentence, Word


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
