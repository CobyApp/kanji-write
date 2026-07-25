# Kanken Advanced Levels Data Design

Date: 2026-07-25

## Goal

Add `準1級` and `1級` to Kanken study with the same core experience as the
existing levels: level selection, kanji browsing, readings and meanings, study
sessions, writing support where verified stroke data exists, and exam-backed
practice where the current question sources can support it.

The implementation must also make Kanken data reproducible. The current bundled
database contains a manually added `kanken_level` column and curated tables that
the checked-in data pipeline cannot rebuild.

## Sources and Licensing

- Use `mimneko/kanji-data` as the Kanken allocation source. Its repository is
  CC0-1.0 and includes `準1級`, `1/準1級`, and `1級` classifications.
- Use KANJIDIC2 for Unicode literals, readings, English meanings, radicals, and
  stroke counts.
- Use KanjiVG for verified stroke-order paths.
- Use JMdict for words associated with the new kanji.
- Use GlyphWiki glyph data for non-Unicode or image-only variants when a
  matching freely reusable glyph can be verified.
- Do not copy or bundle images from Kanjipedia. Those images use the licensed
  Motoya Kanken font and are not covered by the CC0 dataset license.

Source versions or commit hashes must be recorded by the fetch/build process so
that a database can be reproduced later.

## Inventory and Level Membership

The allocation source currently contains three advanced categories:

- `準1級`: advanced characters assigned to pre-1
- `1級`: advanced characters assigned to level 1
- `1/準1級`: variants that belong to both examinations

The pinned upstream CSV currently contains 4,177 advanced rows: 3,806 Unicode
text rows and 371 image-only variants. The build must use the pinned CSV row
counts and hash rather than the repository README because those counts differ.

Level membership must be modeled separately from the kanji record. A join table
allows a character or variant to belong to both `準1級` and `1級` without
duplicating its study and review identity.

Existing 10級–2級 assignments will be migrated into the same membership model.
The existing `kanji.kanken_level` column remains as the item's introduction
level for backward-compatible reads. For `1/準1級` items its value is `準1級`.
The membership table is the source of truth for filtering, counts, and study
scope.

## Data Model

### Kanji identity

Unicode characters continue to use their literal and code point as stable
identity. Image-only variants use a separate variant record linked to their
canonical parent character.

Each displayable study item has:

- a stable database ID
- an optional Unicode literal and code point
- an optional glyph asset identifier
- a canonical parent kanji ID for inherited readings and meanings
- variant metadata such as standard, old form, or other variant

At least one of Unicode literal or glyph asset must exist.

### Kanken membership

Add a normalized membership table containing:

- study item ID
- level label
- source classification

`1/準1級` source rows produce two memberships: `準1級` and `1級`.

### Glyph assets

Freely reusable variant glyphs are stored as local SVG assets with source and
license metadata. They are rendered through a shared glyph view so list,
detail, card, and quiz screens do not need separate fallback logic.

Glyph assets are not treated as stroke-order data. A static outline cannot be
used to invent stroke order.

Image-only variants cannot be selected automatically. The allocation source,
Kanjipedia, and GlyphWiki share no authoritative variant identifier. The
pipeline may generate candidates, but it only accepts a pinned manifest whose
GlyphWiki name, revision, SHA-256, match basis, and verification status have
been reviewed.

## Staged Delivery

The first delivery includes all 3,806 Unicode advanced rows, normalized shared
membership, glyph-backed data structures, candidate-generation tooling, and
strict manifest validation. It does not expose an image-only variant until its
open glyph mapping has been verified.

The second delivery incrementally adds the 371 image-only variants from a
reviewed manifest. This staging prevents unverified look-alike glyphs from
being taught while allowing accurate advanced-level study to ship first.

## Pipeline

1. Fetch or accept pinned Kanken allocation data.
2. Parse and validate level labels and variant relationships.
3. Select all existing jōyō kanji plus the required advanced Kanken inventory
   instead of filtering exclusively by KANJIDIC2 grade.
4. Merge KANJIDIC2, KanjiVG, JMdict, gloss, sentence, and question sources.
5. Resolve image-only variants to verified open glyph assets and canonical
   parents.
6. Load kanji, variants, Kanken memberships, glyph assets, curated Kanken
   datasets, and existing JLPT data into a newly created SQLite database.
7. Run coverage and integrity gates.
8. Replace the bundled database only after all gates pass.

The schema must include the currently manual `kanken_level` functionality,
`yojijukugo`, and `taigirui` data so a clean pipeline run preserves existing
features.

## App Behavior

`ExamType.kanken.levels` adds `準1級` and `1級` after `2級`. All visible labels
remain Japanese.

Level filtering, study ordering, remaining counts, and completion advancement
use Kanken memberships. A shared item can appear in either advanced level, but
review history remains attached to one stable item ID and is not duplicated.

Unicode and glyph-backed items share the same list and detail layouts. Glyph
assets replace text only for items that cannot be rendered accurately as
Unicode.

Writing behavior is capability-based:

- verified KanjiVG paths: animation, tracing, and existing writing practice
- static open glyph only: display, readings, meanings, cards, and non-writing
  quizzes; show a Japanese message that stroke order is unavailable

The advanced exam hub receives explicit `準1級` and `1級` section definitions.
Sections without reliable question data remain visible as `準備中`; they must
not synthesize unverified questions.

## Validation and Error Handling

The pipeline fails before replacing the bundled database when:

- a source level label is unknown
- a membership points to a missing study item
- a shared source row does not produce both memberships
- a Unicode item lacks required reading or English meaning data
- a glyph-backed variant lacks a verified asset, canonical parent, or license
  record
- IDs or memberships are duplicated unexpectedly
- existing 10級–2級 counts regress

Missing stroke order is allowed only when recorded as an explicit capability
gap. The app must render a deterministic unavailable state instead of opening
an empty writing session.

## Testing

Pipeline tests cover:

- parsing all advanced source classifications
- conversion of `1/準1級` into two memberships
- advanced inventory selection beyond jōyō grades
- canonical-parent inheritance for glyph-backed variants
- glyph license metadata
- schema parity for Kanken memberships, `yojijukugo`, and `taigirui`
- coverage gates and atomic database replacement

App tests cover:

- Kanken level order through `1級`
- filtering and study ordering for both new levels
- shared item visibility with a single review identity
- Unicode and SVG glyph rendering paths
- writing availability based on verified stroke data
- advanced exam-section definitions
- live bundled-database reads and non-zero advanced-level counts

## Scope Boundaries

This work adds advanced kanji inventory and makes the Kanken build reproducible.
It does not claim complete real-exam question coverage for every advanced
section. New curated idiom, antonym, synonym, error-correction, and historical
question banks are separate content projects.

It also does not copy restricted Kanjipedia images or infer stroke order from a
static glyph.

## Success Criteria

- Users can select `準1級` and `1級` anywhere Kanken levels are selected.
- Both levels contain all validated Unicode study items from the pinned
  allocation source in the first delivery.
- Shared variants appear in both levels without duplicate review records.
- No image-only variant is exposed without a verified open glyph asset.
- The candidate report accounts for all 371 image-only rows, and the second
  delivery can add verified rows without changing the database schema or app.
- Writing is available only when verified stroke paths exist.
- A clean pipeline build reproduces all existing JLPT and Kanken data and the
  bundled database passes pipeline and app integration tests.
