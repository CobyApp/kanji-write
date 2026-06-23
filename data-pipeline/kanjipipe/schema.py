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
    text     TEXT    NOT NULL
);

CREATE INDEX idx_reading_kanji ON reading(kanji_id);
CREATE INDEX idx_gloss_kanji   ON gloss(kanji_id);
"""
