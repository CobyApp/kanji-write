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
| Practice questions | 20,041 |
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
cd app && tuist generate --no-open
```

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

## Licence

The source in this repository is not currently released under an open licence.
The bundled dictionary data stays under the licences listed above.
