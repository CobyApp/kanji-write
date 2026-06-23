#!/usr/bin/env bash
# Download raw open datasets into data-pipeline/sources/ (gitignored).
# KANJIDIC2: EDRDG, CC BY-SA 4.0. JLPT N5-N1 list: bundled separately.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p sources

echo "Fetching KANJIDIC2..."
curl -fsSL "http://www.edrdg.org/kanjidic/kanjidic2.xml.gz" -o sources/kanjidic2.xml.gz
gunzip -f sources/kanjidic2.xml.gz   # -> sources/kanjidic2.xml

# NOTE: sources/jlpt.json (modern N5-N1 mapping) is provided manually — see
# docs. KANJIDIC2's own <jlpt> is the obsolete 4-level scale and is not used.
echo "Done. Place the N5-N1 mapping at sources/jlpt.json before building."
