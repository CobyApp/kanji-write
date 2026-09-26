import sqlite3

from kanjipipe.db import init_db
from kanjipipe.ingest.jlpt_vocab import parse_jlpt_vocab
from kanjipipe.loader import load_word_jlpt_levels


def _write(tmp_path, level, rows):
    lines = ["expression,reading,meaning,tags,guid"]
    lines += [f"{e},{r},x,,g" for e, r in rows]
    (tmp_path / f"{level}.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")


def test_easiest_level_wins(tmp_path):
    _write(tmp_path, "n5", [("学校", "がっこう")])
    _write(tmp_path, "n4", [("学校", "がっこう"), ("会議", "かいぎ")])
    for level in ("n3", "n2", "n1"):
        _write(tmp_path, level, [])
    mapping = parse_jlpt_vocab(tmp_path)
    assert mapping[("学校", "がっこう")] == "N5"
    assert mapping[("会議", "かいぎ")] == "N4"


def test_loader_matches_pair_then_unique_surface():
    conn = init_db(":memory:")
    conn.executemany(
        "INSERT INTO word (surface, reading_kana, is_common) VALUES (?, ?, 1)",
        [("学校", "がっこう"), ("生物", "せいぶつ"), ("生物", "なまもの"), ("会議", "かいぎ")])
    tagged = load_word_jlpt_levels(conn, {
        ("学校", "がっこう"): "N5",
        ("生物", "いきもの"): "N3",   # surface is ambiguous → left untagged
        ("会議", "かいぎ "): "N4",    # reading mismatch, unique surface → tagged
    })
    levels = dict(conn.execute("SELECT surface || reading_kana, jlpt_level FROM word"))
    assert tagged == 2
    assert levels["学校がっこう"] == "N5"
    assert levels["生物せいぶつ"] is None and levels["生物なまもの"] is None
    assert levels["会議かいぎ"] == "N4"
