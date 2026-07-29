DDL = """
CREATE TABLE kanji (
    id           INTEGER PRIMARY KEY,
    literal      TEXT    NOT NULL UNIQUE,
    codepoint    INTEGER NOT NULL,
    stroke_count INTEGER NOT NULL,
    grade        INTEGER,
    jlpt_level   TEXT,
    kanken_level TEXT,
    has_verified_stroke_order INTEGER NOT NULL DEFAULT 0
        CHECK(has_verified_stroke_order IN (0, 1)),
    freq_rank    INTEGER,
    radical      INTEGER
);

CREATE TABLE kanken_membership (
    kanji_id              INTEGER NOT NULL REFERENCES kanji(id),
    level_label           TEXT NOT NULL,
    source_classification TEXT NOT NULL,
    UNIQUE(kanji_id, level_label)
);

CREATE INDEX idx_kanken_membership_level
    ON kanken_membership(level_label, kanji_id);

CREATE TABLE glyph_asset (
    id             INTEGER PRIMARY KEY,
    provider       TEXT NOT NULL,
    glyph_name     TEXT NOT NULL,
    revision       TEXT NOT NULL,
    sha256         TEXT NOT NULL,
    source_url     TEXT NOT NULL,
    license_url    TEXT NOT NULL,
    local_svg_name TEXT NOT NULL,
    UNIQUE(provider, glyph_name, revision),
    UNIQUE(sha256),
    UNIQUE(local_svg_name)
);

CREATE TABLE kanji_variant (
    id                 INTEGER PRIMARY KEY,
    canonical_kanji_id INTEGER NOT NULL REFERENCES kanji(id),
    glyph_asset_id     INTEGER REFERENCES glyph_asset(id),
    source_ct_id       TEXT NOT NULL,
    source_ce_id       TEXT NOT NULL UNIQUE,
    variant_kind       TEXT NOT NULL,
    literal            TEXT,
    codepoint          INTEGER,
    CHECK(literal IS NOT NULL OR glyph_asset_id IS NOT NULL)
);

CREATE INDEX idx_kanji_variant_canonical
    ON kanji_variant(canonical_kanji_id);

CREATE TABLE reading (
    id        INTEGER PRIMARY KEY,
    kanji_id  INTEGER NOT NULL REFERENCES kanji(id),
    lang_axis TEXT    NOT NULL,   -- 'on' | 'kun' | 'pinyin' | 'eum'
    value     TEXT    NOT NULL,
    is_common INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE gloss (
    id       INTEGER PRIMARY KEY,
    kanji_id INTEGER NOT NULL REFERENCES kanji(id),
    lang     TEXT    NOT NULL,    -- 'ko' | 'ja' | 'zh' | 'en'
    text     TEXT    NOT NULL,
    source   TEXT                 -- NULL = KANJIDIC2 (English); 'llm' = generated native gloss
);

CREATE INDEX idx_reading_kanji ON reading(kanji_id);
CREATE INDEX idx_gloss_kanji   ON gloss(kanji_id);

CREATE TABLE stroke_order (
    id        INTEGER PRIMARY KEY,
    kanji_id  INTEGER NOT NULL REFERENCES kanji(id),
    ordinal   INTEGER NOT NULL,
    path_d    TEXT    NOT NULL,
    UNIQUE(kanji_id, ordinal)
);

CREATE INDEX idx_stroke_order_kanji ON stroke_order(kanji_id);

CREATE TABLE word (
    id           INTEGER PRIMARY KEY,
    surface      TEXT NOT NULL,
    reading_kana TEXT NOT NULL,
    is_common    INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE word_kanji (
    word_id  INTEGER NOT NULL REFERENCES word(id),
    kanji_id INTEGER NOT NULL REFERENCES kanji(id),
    UNIQUE(word_id, kanji_id)
);

CREATE TABLE word_gloss (
    id      INTEGER PRIMARY KEY,
    word_id INTEGER NOT NULL REFERENCES word(id),
    lang    TEXT NOT NULL,
    text    TEXT NOT NULL
);

CREATE INDEX idx_word_kanji_kanji ON word_kanji(kanji_id);
CREATE INDEX idx_word_gloss_word ON word_gloss(word_id);

CREATE TABLE sentence (
    id      INTEGER PRIMARY KEY,
    text_ja TEXT NOT NULL
);

CREATE TABLE sentence_translation (
    id          INTEGER PRIMARY KEY,
    sentence_id INTEGER NOT NULL REFERENCES sentence(id),
    lang        TEXT NOT NULL,
    text        TEXT NOT NULL
);

CREATE TABLE sentence_kanji (
    sentence_id INTEGER NOT NULL REFERENCES sentence(id),
    kanji_id    INTEGER NOT NULL REFERENCES kanji(id),
    UNIQUE(sentence_id, kanji_id)
);

CREATE TABLE sentence_word (
    sentence_id INTEGER NOT NULL REFERENCES sentence(id),
    word_id     INTEGER NOT NULL REFERENCES word(id),
    UNIQUE(sentence_id, word_id)
);

CREATE INDEX idx_sentence_translation_sentence ON sentence_translation(sentence_id);
CREATE INDEX idx_sentence_kanji_kanji ON sentence_kanji(kanji_id);
CREATE INDEX idx_sentence_word_word ON sentence_word(word_id);

CREATE TABLE relation (
    id        INTEGER PRIMARY KEY,
    word_id_a INTEGER NOT NULL REFERENCES word(id),
    word_id_b INTEGER NOT NULL REFERENCES word(id),
    type      TEXT NOT NULL,
    UNIQUE(word_id_a, word_id_b, type)
);

CREATE INDEX idx_relation_a ON relation(word_id_a);
CREATE INDEX idx_relation_b ON relation(word_id_b);

CREATE TABLE yojijukugo (
    id           INTEGER PRIMARY KEY,
    yoji         TEXT NOT NULL UNIQUE,
    reading      TEXT NOT NULL,
    meaning_ja   TEXT,
    meaning_ko   TEXT,
    meaning_zh   TEXT,
    meaning_en   TEXT,
    kanken_level TEXT NOT NULL
);

CREATE INDEX idx_yojijukugo_level ON yojijukugo(kanken_level);

CREATE TABLE taigirui (
    id             INTEGER PRIMARY KEY,
    word           TEXT NOT NULL,
    word_reading   TEXT NOT NULL,
    answer         TEXT NOT NULL,
    answer_reading TEXT NOT NULL,
    relation       TEXT NOT NULL CHECK(relation IN ('対義', '類義')),
    kanken_level   TEXT NOT NULL,
    UNIQUE(word, answer, relation)
);

CREATE INDEX idx_taigirui_level ON taigirui(kanken_level);

CREATE TABLE jlpt_question (
    id          INTEGER PRIMARY KEY,
    kanji_id    INTEGER NOT NULL REFERENCES kanji(id),
    level       TEXT    NOT NULL,   -- 'N5'..'N1' (denormalized from kanji)
    kind        TEXT    NOT NULL,   -- 'reading' | 'orthography' | 'context'
    prompt      TEXT    NOT NULL,   -- the JLPT-style Japanese stem
    options     TEXT    NOT NULL,   -- JSON array of option strings
    answer      INTEGER NOT NULL,   -- 0-based index of the correct option
    explanations TEXT,              -- JSON object of 해설 by lang (ko/ja/zh/en)
    focus       TEXT,               -- substring of prompt to underline (target word)
    UNIQUE(kanji_id, kind, prompt)
);

CREATE INDEX idx_jlpt_question_kanji ON jlpt_question(kanji_id);
"""
