# kanjipipe/build_db.py
import argparse
import os
from pathlib import Path

from kanjipipe.db import init_db
from kanjipipe.filters import filter_joyo
from kanjipipe.ingest.jlpt import merge_jlpt
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2
from kanjipipe.ingest.jmdict import parse_jmdict
from kanjipipe.ingest.kanjivg import parse_kanjivg
from kanjipipe.ingest.tatoeba import parse_tatoeba
from kanjipipe.loader import load_kanji, load_sentences, load_stroke_order, load_words
from kanjipipe.validate import assert_core_gates


def build(
    kanjidic2_path: str | Path,
    jlpt_path: str | Path,
    kanjivg_path: str | Path,
    jmdict_path: str | Path,
    sentences_path: str | Path,
    links_path: str | Path,
    out_path: str,
) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    kanji = filter_joyo(kanji)
    merge_jlpt(kanji, jlpt_path)
    strokes = parse_kanjivg(kanjivg_path)
    words = parse_jmdict(jmdict_path)
    sentences = parse_tatoeba(sentences_path, links_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    try:
        load_kanji(conn, kanji)
        load_stroke_order(conn, strokes)
        load_words(conn, words)
        load_sentences(conn, sentences)
        report = assert_core_gates(conn)  # raises if a gate fails
    finally:
        conn.close()  # always release the handle, even on gate failure
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Build kanji.sqlite")
    parser.add_argument("--kanjidic2", default="sources/kanjidic2.xml")
    parser.add_argument("--jlpt", default="sources/jlpt.json")
    parser.add_argument("--kanjivg", default="sources/kanjivg.xml")
    parser.add_argument("--jmdict", default="sources/jmdict.xml")
    parser.add_argument("--sentences", default="sources/sentences.csv")
    parser.add_argument("--links", default="sources/links.csv")
    parser.add_argument("--out", default="out/kanji.sqlite")
    args = parser.parse_args()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    report = build(args.kanjidic2, args.jlpt, args.kanjivg, args.jmdict,
                   args.sentences, args.links, args.out)
    print(f"built {args.out}: {report}")


if __name__ == "__main__":
    main()
