DDL = """
CREATE TABLE kanji (
    id           INTEGER PRIMARY KEY,
    literal      TEXT    NOT NULL UNIQUE,
    codepoint    INTEGER NOT NULL,
    stroke_count INTEGER NOT NULL,
    grade        INTEGER,
    jlpt_level   TEXT,
    freq_rank    INTEGER,
    radical      INTEGER
);

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

CREATE INDEX idx_sentence_translation_sentence ON sentence_translation(sentence_id);
CREATE INDEX idx_sentence_kanji_kanji ON sentence_kanji(kanji_id);

CREATE TABLE relation (
    id        INTEGER PRIMARY KEY,
    word_id_a INTEGER NOT NULL REFERENCES word(id),
    word_id_b INTEGER NOT NULL REFERENCES word(id),
    type      TEXT NOT NULL,
    UNIQUE(word_id_a, word_id_b, type)
);

CREATE INDEX idx_relation_a ON relation(word_id_a);
CREATE INDEX idx_relation_b ON relation(word_id_b);
"""
