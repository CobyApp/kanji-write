# kanjipipe/build_db.py
import argparse
import os
from pathlib import Path

from kanjipipe.db import init_db
from kanjipipe.filters import filter_joyo
from kanjipipe.ingest.jlpt import merge_jlpt
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2
from kanjipipe.ingest.jmdict import parse_jmdict
from kanjipipe.ingest.jmdict_relations import parse_jmdict_relations
from kanjipipe.ingest.kanjivg import parse_kanjivg
from kanjipipe.ingest.llm_glosses import parse_llm_glosses
from kanjipipe.ingest.sentence_glosses import parse_sentence_glosses
from kanjipipe.ingest.tatoeba import parse_tatoeba
from kanjipipe.ingest.word_glosses import parse_word_glosses, parse_word_jazh
from kanjipipe.loader import (
    load_kanji, load_llm_glosses, load_relations, load_sentence_glosses,
    load_sentences, load_stroke_order, load_word_jazh_glosses,
    load_word_ko_glosses, load_words)
from kanjipipe.validate import assert_core_gates


def build(
    kanjidic2_path: str | Path,
    jlpt_path: str | Path,
    kanjivg_path: str | Path,
    jmdict_path: str | Path,
    sentences_path: str | Path,
    links_path: str | Path,
    out_path: str,
    llm_glosses_path: str | Path | None = None,
    word_ko_path: str | Path | None = None,
    word_jazh_path: str | Path | None = None,
    sentence_glosses_path: str | Path | None = None,
) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    kanji = filter_joyo(kanji)
    merge_jlpt(kanji, jlpt_path)
    strokes = parse_kanjivg(kanjivg_path)
    words = parse_jmdict(jmdict_path)
    relations = parse_jmdict_relations(jmdict_path)
    sentences = parse_tatoeba(sentences_path, links_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    try:
        load_kanji(conn, kanji)
        if llm_glosses_path is not None and os.path.exists(llm_glosses_path):
            load_llm_glosses(conn, parse_llm_glosses(llm_glosses_path))
        load_stroke_order(conn, strokes)
        load_words(conn, words)
        load_relations(conn, relations)
        if word_ko_path is not None and os.path.exists(word_ko_path):
            load_word_ko_glosses(conn, parse_word_glosses(word_ko_path))
        if word_jazh_path is not None and os.path.exists(word_jazh_path):
            load_word_jazh_glosses(conn, parse_word_jazh(word_jazh_path))
        load_sentences(conn, sentences)
        if sentence_glosses_path is not None and os.path.exists(sentence_glosses_path):
            load_sentence_glosses(conn, parse_sentence_glosses(sentence_glosses_path))
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
    parser.add_argument("--llm-glosses", default="sources/llm_glosses.jsonl")
    parser.add_argument("--word-ko", default="sources/word_glosses_ko.jsonl")
    parser.add_argument("--word-jazh", default="sources/word_glosses_jazh.jsonl")
    parser.add_argument("--sentence-glosses", default="sources/sentence_glosses.jsonl")
    parser.add_argument("--out", default="out/kanji.sqlite")
    args = parser.parse_args()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    report = build(args.kanjidic2, args.jlpt, args.kanjivg, args.jmdict,
                   args.sentences, args.links, args.out,
                   llm_glosses_path=args.llm_glosses,
                   word_ko_path=args.word_ko,
                   word_jazh_path=args.word_jazh,
                   sentence_glosses_path=args.sentence_glosses)
    print(f"built {args.out}: {report}")


if __name__ == "__main__":
    main()
