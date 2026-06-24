#!/usr/bin/env bash
# Download raw open datasets into data-pipeline/sources/ (gitignored).
# KANJIDIC2: EDRDG, CC BY-SA 4.0. JLPT N5-N1 list: bundled separately.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources

echo "Fetching KANJIDIC2..."
curl -fsSL "https://www.edrdg.org/kanjidic/kanjidic2.xml.gz" -o sources/kanjidic2.xml.gz
gunzip -f sources/kanjidic2.xml.gz   # -> sources/kanjidic2.xml

echo "Fetching KanjiVG..."
curl -fsSL "https://github.com/KanjiVG/kanjivg/releases/download/r20240807/kanjivg-20240807.xml.gz" -o sources/kanjivg.xml.gz
gunzip -f sources/kanjivg.xml.gz   # -> sources/kanjivg.xml

# Modern JLPT N5-N1 mapping. The JLPT does not publish an official kanji list,
# so we derive {literal: "N5".."N1"} from the community davidluzgouveia/kanji-data
# `jlpt_new` field (5=N5 ... 1=N1). KANJIDIC2's own <jlpt> is the obsolete
# pre-2010 4-level scale and is intentionally not used.
echo "Fetching JLPT N5-N1 mapping..."
curl -fsSL "https://raw.githubusercontent.com/davidluzgouveia/kanji-data/master/kanji.json" -o sources/kanji-data.json
python3 - <<'PY'
import json
data = json.load(open("sources/kanji-data.json", encoding="utf-8"))
mapping = {ch: f"N{e['jlpt_new']}" for ch, e in data.items() if e.get("jlpt_new")}
json.dump(mapping, open("sources/jlpt.json", "w", encoding="utf-8"), ensure_ascii=False)
print(f"  jlpt.json: {len(mapping)} entries")
PY

echo "Fetching JMdict (English)..."
# EDRDG's FTP server does not offer HTTPS; http is the only protocol available here.
curl -fsSL "http://ftp.edrdg.org/pub/Nihongo/JMdict_e.gz" -o sources/jmdict.xml.gz
gunzip -f sources/jmdict.xml.gz   # -> sources/jmdict.xml

echo "Fetching Tatoeba sentences + links..."
curl -fsSL "https://downloads.tatoeba.org/exports/sentences.tar.bz2" -o sources/sentences.tar.bz2
curl -fsSL "https://downloads.tatoeba.org/exports/links.tar.bz2" -o sources/links.tar.bz2
tar -xjf sources/sentences.tar.bz2 -C sources   # -> sources/sentences.csv
tar -xjf sources/links.tar.bz2 -C sources       # -> sources/links.csv

echo "Done. Now build with: python -m kanjipipe.build_db --out out/kanji.sqlite"
