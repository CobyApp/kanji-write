# 마이칸지 · マイカンジ · MyKanji

A study app for the Japanese Kanji Aptitude Test (漢検), built for iPhone and
iPad. You write each character by hand on the screen and compare it against the
answer, rather than reading it and moving on.

- **Support** — https://cobyapp.github.io/kanji-write/
- **Privacy Policy** — https://cobyapp.github.io/kanji-write/privacy.html

## What ships in the app

Every number below comes from the built database, not from an estimate:

| | |
|---|---|
| Kanji | 6,053 across all twelve 漢検 levels (10級…1級, including 準2級 / 準1級) |
| Words | 43,138 |
| Four-character idioms (四字熟語) | 398 |
| Example sentences | 6,602 |
| Stroke-order records | 71,836 |
| Practice questions | 22,237 — every 10級〜2級 kanji has 読み and 書き取り items |
| JLPT vocabulary levels | 6,129 words tagged N5〜N1 |
| Languages | Korean, Japanese, English, Simplified Chinese — including every gloss and sentence translation |

Everything is bundled, so the app runs with no network and no account. Study
history stays on the device.

## Repository layout

```
app/            iOS + watchOS + widget app (Tuist, SwiftUI, TCA, GRDB, PencilKit)
data-pipeline/  Python pipeline that builds the shipped SQLite database
docs/           the published support and privacy pages, plus design notes
```

### app/

A Tuist project split into feature modules — `AppFeature`, `Practice`,
`WritingCanvas`, `KanjiDetail`, `Review`, `TestMode`, `Worksheet`, `Reminders`,
`DictionaryClient`, `DesignSystem`, `SharedModels` — with an embedded watchOS
app and a home-screen widget. Each feature module has its own test target.

Tuist generates the Xcode project, so it is not checked in. After changing
`Project.swift` or adding source files:

```bash
app/Scripts/generate.sh
```

The script wraps `tuist install` + `tuist generate` and lifts the deployment
targets of Tuist's generated package resource bundles, which Xcode 27 would
otherwise reject.

### data-pipeline/

`kanjipipe` ingests the open dictionary sources, filters them to the 漢検
curriculum, generates practice questions, and writes `out/kanji.sqlite`. Build
gates in `kanjipipe/validate.py` refuse to emit a database with starved exam
sections, misaligned glosses, or a level whose kanji count contradicts the
official 漢検 counts.

```bash
cd data-pipeline
python -m kanjipipe.build_db     # writes out/kanji.sqlite
pytest                           # pipeline tests
```

EDRDG and Tatoeba publish only a mutable "latest" snapshot, so once they move
on the pinned from-scratch build cannot be reproduced. Content this repository
owns — the question banks, 四字熟語, 対義語・類義語 and JLPT word levels — can be
reloaded into the shipped database in place, with the same content gates:

```bash
python scripts/refresh_db.py                 # updates the app's kanji.sqlite
python scripts/check_question_batch.py FILE  # structure of an authored batch
python scripts/check_ambiguity.py FILE       # distractors that are also right
```

## Data sources

The dictionary content is openly licensed, and the app credits each source on
its support page.

| Source | Used for | Licence |
|---|---|---|
| [KANJIDIC2](https://www.edrdg.org/wiki/index.php/KANJIDIC_Project) · [JMdict](https://www.edrdg.org/jmdict/j_jmdict.html) | readings, meanings, vocabulary | [EDRDG](https://www.edrdg.org/edrdg/licence.html) (CC BY-SA 4.0) |
| [KanjiVG](https://kanjivg.tagaini.net/) | stroke order | CC BY-SA 3.0 |
| [Tatoeba](https://tatoeba.org/) | example sentences | CC BY 2.0 FR |
| [Unihan](https://www.unicode.org/charts/unihan.html) | character metadata | [Unicode](https://www.unicode.org/license.txt) |
| [GlyphWiki](https://glyphwiki.org/) | 旧字 outlines | CC BY-SA 3.0 |
| [open-anki-jlpt-decks](https://github.com/jamsinclair/open-anki-jlpt-decks) | JLPT vocabulary levels | MIT |

## Licence

The source in this repository is not currently released under an open licence.
The bundled dictionary data stays under the licences listed above.
