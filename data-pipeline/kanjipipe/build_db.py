# kanjipipe/build_db.py
import argparse
import os
from pathlib import Path

from kanjipipe.db import init_db
from kanjipipe.filters import (
    ADVANCED_KANKEN_LEVELS,
    advanced_coverage,
    select_study_inventory,
)
from kanjipipe.ingest.jlpt import merge_jlpt
from kanjipipe.ingest.kanken import (
    VALID_LEVELS,
    memberships_for,
    parse_kanken_allocations,
)
from kanjipipe.ingest.kanken_supplement import (
    DEFAULT_SUPPLEMENT_PATH,
    parse_kanken_supplement,
)
from kanjipipe.ingest.kanjidic2 import parse_kanjidic2
from kanjipipe.ingest.jmdict import parse_jmdict
from kanjipipe.ingest.jmdict_relations import parse_jmdict_relations
from kanjipipe.ingest.kanjivg import parse_kanjivg
from kanjipipe.ingest.jlpt_questions import parse_jlpt_questions
from kanjipipe.ingest.llm_glosses import parse_llm_glosses
from kanjipipe.ingest.sentence_glosses import parse_sentence_glosses
from kanjipipe.ingest.tatoeba import parse_tatoeba
from kanjipipe.ingest.unihan import parse_unihan
from kanjipipe.ingest.word_glosses import parse_word_glosses, parse_word_jazh
from kanjipipe.loader import (
    load_jlpt_questions, load_kanji, load_kanken_memberships, load_llm_glosses,
    load_relations, load_sentence_glosses, load_sentence_words, load_sentences,
    load_stroke_order, load_taigirui, load_word_jazh_glosses,
    load_word_ko_glosses, load_words, load_yojijukugo)
from kanjipipe.validate import (
    PRODUCTION_KANKEN_COUNT_POLICY,
    KankenCountPolicy,
    assert_core_gates,
)

RESOURCE_DIR = (
    Path(__file__).resolve().parents[2]
    / "app/Sources/DictionaryClient/Resources"
)


def build(
    kanjidic2_path: str | Path,
    jlpt_path: str | Path,
    kanjivg_path: str | Path,
    jmdict_path: str | Path,
    sentences_path: str | Path,
    links_path: str | Path,
    out_path: str,
    kanken_path: str | Path = "sources/kanken.csv",
    llm_glosses_path: str | Path | None = None,
    word_ko_path: str | Path | None = None,
    word_jazh_path: str | Path | None = None,
    sentence_glosses_path: str | Path | None = None,
    jlpt_questions_path: str | Path | None = None,
    advanced_questions_path: str | Path | None = None,
    yojijukugo_path: str | Path | None = RESOURCE_DIR / "yojijukugo.source.json",
    taigirui_path: str | Path | None = RESOURCE_DIR / "taigirui.source.json",
    unihan_path: str | Path | None = "sources/Unihan.zip",
    kanken_supplement_path: str | Path = DEFAULT_SUPPLEMENT_PATH,
    kanken_count_policy: KankenCountPolicy = PRODUCTION_KANKEN_COUNT_POLICY,
) -> dict[str, int]:
    kanji = parse_kanjidic2(kanjidic2_path)
    allocations = parse_kanken_allocations(kanken_path)
    for source_level in sorted({row.source_level for row in allocations}):
        if source_level not in VALID_LEVELS and source_level != "配当外":
            memberships_for(source_level)
    unihan = parse_unihan(unihan_path) if unihan_path is not None else {}
    supplements = parse_kanken_supplement(kanken_supplement_path)
    kanji = select_study_inventory(
        kanji,
        allocations,
        unihan=unihan,
        supplements=supplements,
    )
    inventory_report = advanced_coverage(kanji, allocations)
    if any(inventory_report.values()):
        raise ValueError(
            "advanced metadata coverage failed: "
            + ", ".join(
                f"{key}={value}"
                for key, value in inventory_report.items()
                if value
            )
        )
    supported_allocations = [
        allocation
        for allocation in allocations
        if allocation.source_level in VALID_LEVELS
    ]
    merge_jlpt(kanji, jlpt_path)
    strokes = parse_kanjivg(kanjivg_path)
    # 準1級/1級 kanji are rare enough that common-only JMdict leaves most of them
    # with no vocabulary at all, and therefore no 読み/書き exam material. Widen
    # the filter for exactly those kanji — every other level stays common-only.
    # The level lives on the allocations, not on the Kanji rows — `kanken_level`
    # is only filled in later by load_kanken_memberships.
    inventory_literals = {entry.literal for entry in kanji}
    advanced_literals = frozenset(
        allocation.literal for allocation in allocations
        if allocation.source_level in ADVANCED_KANKEN_LEVELS
        and allocation.literal in inventory_literals
    )
    words = parse_jmdict(jmdict_path, extra_literals=advanced_literals)
    relations = parse_jmdict_relations(jmdict_path)
    sentences = parse_tatoeba(sentences_path, links_path)

    if os.path.exists(out_path):
        os.remove(out_path)  # rebuild from scratch; DB is a generated artifact
    conn = init_db(out_path)
    try:
        load_kanji(conn, kanji)
        load_kanken_memberships(conn, supported_allocations)
        if llm_glosses_path is not None and os.path.exists(llm_glosses_path):
            load_llm_glosses(conn, parse_llm_glosses(llm_glosses_path))
        load_stroke_order(conn, strokes)
        load_words(conn, words, advanced_literals=advanced_literals)
        load_relations(conn, relations)
        if word_ko_path is not None and os.path.exists(word_ko_path):
            load_word_ko_glosses(conn, parse_word_glosses(word_ko_path))
        if word_jazh_path is not None and os.path.exists(word_jazh_path):
            load_word_jazh_glosses(conn, parse_word_jazh(word_jazh_path))
        load_sentences(conn, sentences)
        load_sentence_words(conn)  # link sentences to the words they contain
        if sentence_glosses_path is not None and os.path.exists(sentence_glosses_path):
            load_sentence_glosses(conn, parse_sentence_glosses(sentence_glosses_path))
        if jlpt_questions_path is not None and os.path.exists(jlpt_questions_path):
            load_jlpt_questions(conn, parse_jlpt_questions(jlpt_questions_path))
        # The 準1級/1級 bank is generated from this same database by
        # scripts/generate_advanced_questions.py, then read back on the next
        # build. Same table, same shape — only the provenance differs.
        if (advanced_questions_path is not None
                and os.path.exists(advanced_questions_path)):
            load_jlpt_questions(conn, parse_jlpt_questions(advanced_questions_path))
        if yojijukugo_path is not None:
            load_yojijukugo(conn, yojijukugo_path)
        if taigirui_path is not None:
            load_taigirui(conn, taigirui_path)
        report = assert_core_gates(
            conn,
            kanken_allocations=allocations,
            kanken_count_policy=kanken_count_policy,
            missing_advanced_inventory=inventory_report[
                "missing_advanced_inventory"
            ],
        )  # raises if a gate fails
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
    parser.add_argument("--jlpt-questions", default="sources/jlpt_questions.jsonl")
    parser.add_argument("--advanced-questions",
                        default="sources/kanken_advanced_questions.jsonl")
    parser.add_argument("--kanken", default="sources/kanken.csv")
    parser.add_argument("--unihan", default="sources/Unihan.zip")
    parser.add_argument(
        "--kanken-supplement",
        default=str(DEFAULT_SUPPLEMENT_PATH),
    )
    parser.add_argument(
        "--yojijukugo",
        default=str(RESOURCE_DIR / "yojijukugo.source.json"),
    )
    parser.add_argument(
        "--taigirui",
        default=str(RESOURCE_DIR / "taigirui.source.json"),
    )
    parser.add_argument("--out", default="out/kanji.sqlite")
    args = parser.parse_args()
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    report = build(args.kanjidic2, args.jlpt, args.kanjivg, args.jmdict,
                   args.sentences, args.links, args.out,
                   kanken_path=args.kanken,
                   llm_glosses_path=args.llm_glosses,
                   word_ko_path=args.word_ko,
                   word_jazh_path=args.word_jazh,
                   sentence_glosses_path=args.sentence_glosses,
                   jlpt_questions_path=args.jlpt_questions,
                   advanced_questions_path=args.advanced_questions,
                   yojijukugo_path=args.yojijukugo,
                   taigirui_path=args.taigirui,
                   unihan_path=args.unihan,
                   kanken_supplement_path=args.kanken_supplement)
    print(f"built {args.out}: {report}")


if __name__ == "__main__":
    main()
