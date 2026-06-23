# kanjipipe/build_db.py
import argparse
import os
from pathlib import Path

from kanjipipe.db import init_db
from kanjipipe.filters import filter_joyo
from kanjipipe.ingest.jlpt import merge_jlpt
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2
from kanjipipe.loader import load_kanji
from kanjipipe.validate import assert_core_gates


def build(kanjidic2_path, jlpt_path, out_path: str) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    kanji = filter_joyo(kanji)
    merge_jlpt(kanji, jlpt_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    load_kanji(conn, kanji)
    report = assert_core_gates(conn)
    conn.close()
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description="Build kanji.sqlite")
    parser.add_argument("--kanjidic2", default="sources/kanjidic2.xml")
    parser.add_argument("--jlpt", default="sources/jlpt.json")
    parser.add_argument("--out", default="out/kanji.sqlite")
    args = parser.parse_args()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    report = build(args.kanjidic2, args.jlpt, args.out)
    print(f"built {args.out}: {report}")


if __name__ == "__main__":
    main()
