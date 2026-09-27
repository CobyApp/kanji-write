#!/usr/bin/env bash
# Fetch and verify every input used by the reproducible SQLite build.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/kanji-sources.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

verify_sha256() {
  python3 scripts/verify_sha256.py "$1" "$2"
}

fetch_verified() {
  local label="$1"
  local url="$2"
  local expected_sha256="$3"
  local output="$4"
  echo "Fetching ${label}..."
  curl -fsSL "$url" -o "$output"
  verify_sha256 "$expected_sha256" "$output"
}

# EDRDG KANJIDIC2, CC BY-SA 4.0 with additional KANJIDIC conditions.
# EDRDG does not publish immutable snapshot URLs, so the archive and expanded
# build input are both pinned and a changed upstream snapshot fails closed.
KANJIDIC2_URL="https://www.edrdg.org/kanjidic/kanjidic2.xml.gz"
KANJIDIC2_ARCHIVE_SHA256="25828a7bcd86c6334d29474aad421935d7ff278e1dbcc1c37e3f7e5116727f34"
KANJIDIC2_SHA256="6123866ad52f8b050e7dcb5d4723f5790db66306c02ad0ad6ac87f4f6030ab58"
fetch_verified "KANJIDIC2" "$KANJIDIC2_URL" "$KANJIDIC2_ARCHIVE_SHA256" \
  "$tmp_dir/kanjidic2.xml.gz"
gzip -dc "$tmp_dir/kanjidic2.xml.gz" > "$tmp_dir/kanjidic2.xml"
verify_sha256 "${KANJIDIC2_SHA256}" "$tmp_dir/kanjidic2.xml"
mv "$tmp_dir/kanjidic2.xml" sources/kanjidic2.xml

# KanjiVG release r20240807, CC BY-SA 3.0.
KANJIVG_RELEASE="r20240807"
KANJIVG_URL="https://github.com/KanjiVG/kanjivg/releases/download/${KANJIVG_RELEASE}/kanjivg-20240807.xml.gz"
KANJIVG_ARCHIVE_SHA256="a609387140f2eb42d845e6b10aa361366dda89cf5fba6f06138c4afed0056864"
KANJIVG_SHA256="5353265989dabca7061d5bd6fc51aa9473c2e5f8b6bb9d196b817183c92d96a8"
fetch_verified "KanjiVG ${KANJIVG_RELEASE}" "$KANJIVG_URL" \
  "$KANJIVG_ARCHIVE_SHA256" "$tmp_dir/kanjivg.xml.gz"
gzip -dc "$tmp_dir/kanjivg.xml.gz" > "$tmp_dir/kanjivg.xml"
verify_sha256 "${KANJIVG_SHA256}" "$tmp_dir/kanjivg.xml"
mv "$tmp_dir/kanjivg.xml" sources/kanjivg.xml

# mimneko/kanji-data exact Git commit. Upstream repository provenance is
# recorded in docs; the CSV is used only after exact-byte verification.
KANKEN_COMMIT="0be3577f7939ec85d2b4e373a7a94262e7449e13"
KANKEN_SHA256="e3a3bade7bb738f6e25d2ff14ea4118ed3b18d9cd32f49dd6a90f5eb6d8ef84f"
KANKEN_URL="https://raw.githubusercontent.com/mimneko/kanji-data/${KANKEN_COMMIT}/%E6%BC%A2%E6%A4%9C%E6%BC%A2%E5%AD%97%E8%BE%9E%E5%85%B8%E6%BC%A2%E5%AD%97.csv"
fetch_verified "Kanken allocations" "$KANKEN_URL" "$KANKEN_SHA256" \
  "$tmp_dir/kanken.csv"
verify_sha256 "${KANKEN_SHA256}" "$tmp_dir/kanken.csv"
mv "$tmp_dir/kanken.csv" sources/kanken.csv

# Unicode 17.0.0 Unihan, Unicode License v3.
UNIHAN_URL="https://www.unicode.org/Public/17.0.0/ucd/Unihan.zip"
UNIHAN_SHA256="f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e"
fetch_verified "Unicode 17.0.0 Unihan" "$UNIHAN_URL" "$UNIHAN_SHA256" \
  "$tmp_dir/Unihan.zip"
verify_sha256 "${UNIHAN_SHA256}" "$tmp_dir/Unihan.zip"
mv "$tmp_dir/Unihan.zip" sources/Unihan.zip

# Modern JLPT N5-N1 mapping derived from davidluzgouveia/kanji-data (MIT).
# KANJIDIC2's <jlpt> is the obsolete pre-2010 4-level scale.
JLPT_COMMIT="00fd7079c3890f430759536f91aa5e854ec0ca4f"
JLPT_SOURCE_URL="https://raw.githubusercontent.com/davidluzgouveia/kanji-data/${JLPT_COMMIT}/kanji.json"
JLPT_SOURCE_SHA256="561b72ea9df703c58fae0c68585812e172aaa7611d2fcee6719d55fd2dfd4fa4"
JLPT_OUTPUT_SHA256="ef8eeccd25b7d2d564ae10c510a94efd5153356e81aa4b9fac4c7091f3733a70"
fetch_verified "JLPT source at ${JLPT_COMMIT}" "$JLPT_SOURCE_URL" \
  "$JLPT_SOURCE_SHA256" "$tmp_dir/kanji-data.json"
verify_sha256 "${JLPT_SOURCE_SHA256}" "$tmp_dir/kanji-data.json"
python3 - "$tmp_dir/kanji-data.json" "$tmp_dir/jlpt.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)
mapping = {
    character: f"N{entry['jlpt_new']}"
    for character, entry in data.items()
    if entry.get("jlpt_new")
}
with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(mapping, output, ensure_ascii=False)
print(f"  jlpt.json: {len(mapping)} entries")
PY
verify_sha256 "${JLPT_OUTPUT_SHA256}" "$tmp_dir/jlpt.json"
mv "$tmp_dir/kanji-data.json" sources/kanji-data.json
mv "$tmp_dir/jlpt.json" sources/jlpt.json

# EDRDG JMdict English, CC BY-SA 4.0. The publisher exposes a mutable HTTP
# endpoint only; pinning both archive and XML prevents silent snapshot drift.
JMDICT_URL="http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz"
JMDICT_ARCHIVE_SHA256="74692e3a803d854e632718b28dda601328e0145276861888c4442301a2a7a44a"
JMDICT_SHA256="b3128bef5795f1baffd46ad24c07b7a6124ca7d47b3105ba104f3e1cafedcba0"
fetch_verified "JMdict English" "$JMDICT_URL" "$JMDICT_ARCHIVE_SHA256" \
  "$tmp_dir/jmdict.xml.gz"
gzip -dc "$tmp_dir/jmdict.xml.gz" > "$tmp_dir/jmdict.xml"
verify_sha256 "${JMDICT_SHA256}" "$tmp_dir/jmdict.xml"
mv "$tmp_dir/jmdict.xml" sources/jmdict.xml

# Tatoeba sentence corpus and links, CC BY 2.0 FR (some sentences CC0).
# Weekly export URLs are mutable, so archives and extracted build inputs are
# exact-byte pinned.
TATOEBA_SENTENCES_URL="https://downloads.tatoeba.org/exports/sentences.tar.bz2"
TATOEBA_SENTENCES_ARCHIVE_SHA256="771d92ee730d083650f1513ae413b2062d8f4d58ed1f87864bb461d1787e1e3e"
TATOEBA_SENTENCES_SHA256="4631dea8a1dddb666081957bf5425d6ded95003d17adda1d475ef41d43973cdd"
TATOEBA_LINKS_URL="https://downloads.tatoeba.org/exports/links.tar.bz2"
TATOEBA_LINKS_ARCHIVE_SHA256="69abec53fe090d0fcd3c20dd0bb441768697668346a66b14bc07d029dc2c88e2"
TATOEBA_LINKS_SHA256="a3b435a8e168088b103ebc15fe25a209fa35a1560569ac39ad02b438f4980655"
fetch_verified "Tatoeba sentences" "$TATOEBA_SENTENCES_URL" \
  "$TATOEBA_SENTENCES_ARCHIVE_SHA256" "$tmp_dir/sentences.tar.bz2"
fetch_verified "Tatoeba links" "$TATOEBA_LINKS_URL" \
  "$TATOEBA_LINKS_ARCHIVE_SHA256" "$tmp_dir/links.tar.bz2"
verify_sha256 "${TATOEBA_SENTENCES_ARCHIVE_SHA256}" \
  "$tmp_dir/sentences.tar.bz2"
verify_sha256 "${TATOEBA_LINKS_ARCHIVE_SHA256}" "$tmp_dir/links.tar.bz2"
mkdir "$tmp_dir/sentences" "$tmp_dir/links"
tar -xjf "$tmp_dir/sentences.tar.bz2" -C "$tmp_dir/sentences"
tar -xjf "$tmp_dir/links.tar.bz2" -C "$tmp_dir/links"
verify_sha256 "${TATOEBA_SENTENCES_SHA256}" "$tmp_dir/sentences/sentences.csv"
verify_sha256 "${TATOEBA_LINKS_SHA256}" "$tmp_dir/links/links.csv"
mv "$tmp_dir/sentences/sentences.csv" sources/sentences.csv
mv "$tmp_dir/links/links.csv" sources/links.csv

# Project-controlled local build inputs. Verify before announcing success so
# accidental edits cannot silently alter a production database build.
LLM_GLOSSES_SHA256="18f15009ae9df61a3e2b6e5fd81b9b1fdee633a07f16818e6c9389625490d8b0"
WORD_GLOSSES_KO_SHA256="fa8517fe61f1bce7019f9f7337c3df504147ad5503084f6680641c71cde7c122"
WORD_GLOSSES_JAZH_SHA256="a4b094f051b53067e13f7f8d967f6cde5cb8865ee02327bee275fc00aa8bccb1"
SENTENCE_GLOSSES_SHA256="1fbe37c3ef6ec0666854d5b9788bb6401c1909e9c73fdc25c8161f4487b38a71"
JLPT_QUESTIONS_SHA256="1d6cbcd8cab70ec27a6f27a7253232d18ad4f9bc5c1469f4cbe43fa59a651c0a"
KANKEN_SUPPLEMENT_SHA256="8952a58aea939cd26fe6d2ae7898471586dcaafec2026aa765162de6e9f8b259"
YOJIJUKUGO_SHA256="58738cc209b1a11440b31c92a37217c22fcd4bdf875d12e6ca7bc17823314cd8"
TAIGIRUI_SHA256="34f8be5c9e9c0fb6bfe144981eb33cb803ec533ecd6a75e51da8b4a47fdf525c"
verify_sha256 "${LLM_GLOSSES_SHA256}" sources/llm_glosses.jsonl
verify_sha256 "${WORD_GLOSSES_KO_SHA256}" sources/word_glosses_ko.jsonl
verify_sha256 "${WORD_GLOSSES_JAZH_SHA256}" sources/word_glosses_jazh.jsonl
verify_sha256 "${SENTENCE_GLOSSES_SHA256}" sources/sentence_glosses.jsonl
verify_sha256 "${JLPT_QUESTIONS_SHA256}" sources/jlpt_questions.jsonl
verify_sha256 "${KANKEN_SUPPLEMENT_SHA256}" kanjipipe/kanken_metadata_supplement.json
verify_sha256 "${YOJIJUKUGO_SHA256}" \
  ../app/Sources/DictionaryClient/Resources/yojijukugo.source.json
verify_sha256 "${TAIGIRUI_SHA256}" \
  ../app/Sources/DictionaryClient/Resources/taigirui.source.json

# JLPT vocabulary lists: jamsinclair/open-anki-jlpt-decks at commit
# 1ad66734417aca9dbcca6b2d5ee440cb13ab3ba0 (MIT, derived from tanos.co.uk).
# Checked in under sources/jlpt_vocab/ and verified like the other local inputs.
verify_sha256 "120911636c019899552aa6d7bd64b036ecef4bedfe272a744f75735c46aae5cd" sources/jlpt_vocab/n1.csv
verify_sha256 "2d0f1ddd6222881cd9fc2ca701db74300af99b3f1f84d5ac3c18411c20f0c055" sources/jlpt_vocab/n2.csv
verify_sha256 "ba071571d344e60b0e1fd11cd2e98a6aaa04515361653ca45147129460531297" sources/jlpt_vocab/n3.csv
verify_sha256 "0e835f40a8d2a1f191d7aa499076002756fa099b95634758376f43c73793e9f6" sources/jlpt_vocab/n4.csv
verify_sha256 "f89abc86b391c4f2b551bbf8910b0de6cd600973b3a9f8d98347513921929ebe" sources/jlpt_vocab/n5.csv

echo "All source pins verified."
echo "Done. Now build with: python -m kanjipipe.build_db --out out/kanji.sqlite"
