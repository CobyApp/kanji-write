# kanjipipe/validate.py
import csv
import json
import re
import sqlite3
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

from kanjipipe.ingest.kanken import memberships_for
from kanjipipe.models import GlyphAsset, KankenAllocation


ALLOWED_GLYPH_MATCH_BASES = {
    "unicode_exact",
    "ivs_exact",
    "collection_id_exact",
    "manual_visual_verified",
}
_SHA256_PATTERN = re.compile(r"[0-9a-f]{64}")
_PINNED_REVISION_PATTERN = re.compile(r"[1-9][0-9]*")


@dataclass(frozen=True)
class KankenCountPolicy:
    legacy_memberships: dict[str, int]
    unicode_advanced: int
    image_pending: int
    # What the allocation source says. "1/準1級" counts toward both levels
    # there, so 397 kanji are shared — that is a fact about the source and is
    # still worth guarding.
    advanced_memberships: dict[str, int]
    shared_advanced: int
    stored_unicode_advanced: int
    # What we actually store. A kanji belongs to exactly one 級 — the level it
    # is introduced at — so nothing is shared and 1級 holds only its own.
    stored_advanced_memberships: dict[str, int]
    stored_shared_advanced: int = 0
    # Only a build with the whole inventory can be judged on whether each
    # playable 大問 has data; a three-kanji fixture would fail every one.
    check_playable_sections: bool = False


PRODUCTION_KANKEN_COUNT_POLICY = KankenCountPolicy(
    legacy_memberships={
        "10級": 80,
        "9級": 160,
        "8級": 200,
        "7級": 202,
        "6級": 193,
        "5級": 191,
        "4級": 313,
        "3級": 284,
        "準2級": 328,
        "2級": 185,
    },
    unicode_advanced=3806,
    image_pending=371,
    # 缶・芸・欠・弁・予・余 have a second, unrelated 1級 allocation on top of
    # their jōyō one. They are stored at their jōyō level, so the advanced
    # inventory is 1248 + 2552 and does not include them.
    stored_unicode_advanced=3800,
    advanced_memberships={"準1級": 1248, "1級": 2955},
    shared_advanced=397,
    stored_advanced_memberships={"準1級": 1248, "1級": 2552},
    check_playable_sections=True,
)


def _is_https_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc)


def parse_verified_glyph_manifest(path: str | Path) -> list[GlyphAsset]:
    with Path(path).open(encoding="utf-8-sig", newline="") as source:
        reader = csv.DictReader(source)
        required = {
            "ce_id",
            "canonical_literal",
            "glyph_name",
            "match_basis",
            "verification_status",
            "provider",
            "revision",
            "sha256",
            "source_url",
            "license_url",
            "local_svg_name",
        }
        if reader.fieldnames is None or not required.issubset(reader.fieldnames):
            raise ValueError("invalid verified glyph manifest columns")

        assets: list[GlyphAsset] = []
        seen_ce_ids: set[str] = set()
        for row_number, raw_row in enumerate(reader, start=2):
            row = {key: (value or "").strip() for key, value in raw_row.items()}
            if row["verification_status"] != "verified":
                raise ValueError(
                    f"unverified glyph mapping at row {row_number}"
                )
            if row["match_basis"] not in ALLOWED_GLYPH_MATCH_BASES:
                raise ValueError(f"invalid match_basis at row {row_number}")
            if not row["revision"] or not row["sha256"]:
                raise ValueError(
                    f"verified glyph mapping requires revision and sha256 at row {row_number}"
                )
            if not _PINNED_REVISION_PATTERN.fullmatch(row["revision"]):
                raise ValueError(
                    f"verified glyph mapping requires numeric revision at row {row_number}"
                )
            if not _SHA256_PATTERN.fullmatch(row["sha256"]):
                raise ValueError(
                    f"verified glyph mapping requires revision and sha256 at row {row_number}"
                )
            if not _is_https_url(row["source_url"]) or not _is_https_url(
                row["license_url"]
            ):
                raise ValueError(
                    "verified glyph mapping requires HTTPS source and license "
                    f"URLs at row {row_number}"
                )
            if not row["canonical_literal"]:
                raise ValueError(
                    f"verified glyph mapping requires canonical parent at row {row_number}"
                )
            if row["provider"] != "glyphwiki":
                raise ValueError(f"unsupported glyph provider at row {row_number}")
            if not row["ce_id"] or not row["glyph_name"] or not row["local_svg_name"]:
                raise ValueError(f"incomplete verified glyph mapping at row {row_number}")
            if row["ce_id"] in seen_ce_ids:
                raise ValueError(f"duplicate glyph CE ID: {row['ce_id']}")
            seen_ce_ids.add(row["ce_id"])

            assets.append(
                GlyphAsset(
                    ce_id=row["ce_id"],
                    canonical_literal=row["canonical_literal"],
                    glyph_name=row["glyph_name"],
                    match_basis=row["match_basis"],
                    provider=row["provider"],
                    revision=row["revision"],
                    sha256=row["sha256"],
                    source_url=row["source_url"],
                    license_url=row["license_url"],
                    local_svg_name=row["local_svg_name"],
                )
            )
    return assets


_ADVANCED_MEMBERSHIP = (
    "EXISTS (SELECT 1 FROM kanken_membership km "
    "WHERE km.kanji_id = k.id "
    "AND km.level_label IN ('準1級', '1級'))"
)
_LEGACY_KANKEN_MEMBERSHIP = (
    "EXISTS (SELECT 1 FROM kanken_membership km "
    "WHERE km.kanji_id = k.id "
    "AND km.level_label NOT IN ('準1級', '1級'))"
)
_JOYO_RECORD = "k.grade IN (1, 2, 3, 4, 5, 6, 8)"
_ADVANCED_SOURCE_LEVELS = {"準1級", "1/準1級", "1級"}


_UNDERLINE = re.compile(r"</?u>")
# Kinds whose options are kanji the learner must supply, so showing the answer
# anywhere in the prompt gives it away.
_WRITE_KINDS = (
    "orthography", "context", "doonkun", "shikibetsu",
    # Derived and authored sections whose options are the answer itself, so the
    # prompt must never contain it.
    "sanji", "kyotsu", "hantai", "taigi", "kousei", "tsukuri", "goselect",
    "kotowaza", "jukujikun", "hyogai",
)


# What the app marks playable, mirrored from ExamType.kankenSections. A bank
# section names its `kind`; the two table-backed ones name their table.
_PLAYABLE: dict[str, tuple[tuple[str, str], ...]] = {
    "10級": (("読み", "reading"), ("書き取り", "orthography"), ("反対のことば", "hantai")),
    "9級": (("読み", "reading"), ("書き取り", "orthography"), ("反対のことば", "hantai")),
    "8級": (("読み", "reading"), ("書き取り", "orthography"), ("対義語", "taigi"),
            ("同音異字", "doonkun")),
    "7級": (("読み", "reading"), ("書き取り", "orthography"), ("対義語", "taigi"),
            ("同音異字", "doonkun"), ("三字熟語", "sanji")),
    "6級": (("読み", "reading"), ("書き取り", "orthography"),
            ("同音・同訓異字", "doonkun"), ("熟語作り", "tsukuri"),
            ("対義語・類義語", "table:taigirui")),
    "5級": (("読み", "reading"), ("書き取り", "orthography"), ("熟語の構成", "kousei"),
            ("同音・同訓異字", "doonkun"), ("四字熟語", "table:yojijukugo"),
            ("対義語・類義語", "table:taigirui")),
    "4級": (("読み", "reading"), ("書き取り", "orthography"), ("熟語の構成", "kousei"),
            ("同音・同訓異字", "doonkun"), ("漢字識別", "shikibetsu"),
            ("誤字訂正", "goji"), ("四字熟語", "table:yojijukugo"),
            ("対義語・類義語", "table:taigirui")),
    "3級": (("読み", "reading"), ("書き取り", "orthography"), ("熟語の構成", "kousei"),
            ("同音・同訓異字", "doonkun"), ("漢字識別", "shikibetsu"),
            ("誤字訂正", "goji"), ("四字熟語", "table:yojijukugo"),
            ("対義語・類義語", "table:taigirui")),
    "準2級": (("読み", "reading"), ("書き取り", "orthography"), ("熟語の構成", "kousei"),
              ("同音・同訓異字", "doonkun"), ("誤字訂正", "goji"),
              ("四字熟語", "table:yojijukugo"), ("対義語・類義語", "table:taigirui")),
    "2級": (("読み", "reading"), ("書き取り", "orthography"), ("熟語の構成", "kousei"),
            ("同音・同訓異字", "doonkun"), ("誤字訂正", "goji"),
            ("四字熟語", "table:yojijukugo"), ("対義語・類義語", "table:taigirui")),
    "準1級": (("読み", "reading"), ("書き取り", "orthography"), ("表外の読み", "hyogai"),
              ("共通の漢字", "kyotsu"), ("誤字訂正", "goji"), ("故事・諺", "kotowaza"),
              ("四字熟語", "table:yojijukugo"), ("対義語・類義語", "table:taigirui")),
    "1級": (("読み", "reading"), ("書き取り", "orthography"), ("語選択", "goselect"),
            ("熟字訓・当て字", "jukujikun"), ("故事・諺", "kotowaza"),
            ("四字熟語", "table:yojijukugo"), ("対義語・類義語", "table:taigirui")),
}
# Below this a 20-question run repeats itself noticeably.
_MIN_PER_SECTION = 15


def starved_sections(conn: sqlite3.Connection) -> list[str]:
    """Playable 大問 with nothing, or too little, behind them."""
    bank: dict[tuple[str, str], int] = {}
    for level, kind, count in conn.execute(
        "SELECT km.level_label, q.kind, COUNT(*) FROM jlpt_question q "
        "JOIN kanken_membership km ON km.kanji_id = q.kanji_id GROUP BY 1, 2"
    ):
        bank[(level, kind)] = count
    tables: dict[tuple[str, str], int] = {}
    for table in ("yojijukugo", "taigirui"):
        for level, count in conn.execute(
            f"SELECT kanken_level, COUNT(*) FROM {table} GROUP BY 1"
        ):
            tables[(level, table)] = count

    starved: list[str] = []
    for level, sections in _PLAYABLE.items():
        for title, source in sections:
            if source.startswith("table:"):
                count = tables.get((level, source.removeprefix("table:")), 0)
            else:
                count = bank.get((level, source), 0)
            if count == 0:
                starved.append(f"{level} {title} is empty")
            elif count < _MIN_PER_SECTION:
                starved.append(f"{level} {title} has only {count}")
    return starved


def question_defects(conn: sqlite3.Connection) -> dict[str, list[str]]:
    """Structural faults in the question bank, grouped by kind of fault.

    The two content rules are asymmetric, which is easy to get backwards:

    * A 読み question must *show* its kanji — you cannot ask how 極 is read in a
      sentence that spells it ごく. Testing instead whether the kana answer
      appears in the prompt is useless here: 敵/てき occurs inside 戦ってきた by
      coincidence, and eleven such false positives drown the real faults.
    * A 書き取り / 文脈 question must *hide* its kanji, since the options are
      kanji and the prompt would otherwise contain the answer (「紅葉して木の
      （　）が…」 with 葉 as the answer).
    """
    defects: dict[str, list[str]] = {}

    def note(name: str, case: str) -> None:
        defects.setdefault(name, []).append(case)

    def q_explanations(raw: str | None) -> dict[str, str]:
        try:
            parsed = json.loads(raw or "{}")
        except ValueError:
            return {}
        return parsed if isinstance(parsed, dict) else {}

    rows = conn.execute(
        "SELECT q.id, k.literal, q.level, q.kind, q.prompt, q.options, q.answer, "
        "q.focus, q.explanations FROM jlpt_question q JOIN kanji k ON k.id = q.kanji_id")
    for (qid, literal, level, kind, prompt, options_json, answer, focus,
         row_explanations) in rows:
        clean = _UNDERLINE.sub("", prompt)
        where = f"[{qid}] {kind}/{level} 「{literal}」 {clean[:36]}"
        try:
            options = json.loads(options_json)
        except (TypeError, ValueError):
            note("unparseable options", where)
            continue
        if len(options) < 4:
            note("fewer than four options", where)
        if len(set(options)) != len(options):
            note("duplicate options", where)
        if any(not str(o).strip() for o in options):
            note("blank option", where)
        if not isinstance(answer, int) or not 0 <= answer < len(options):
            note("answer out of range", where)
            continue
        if focus and focus not in clean:
            note("focus not in prompt", where)
        # The app offers ko/ja/zh/en. A question missing one of them drops the
        # reader into a different language for that explanation alone.
        explanations = q_explanations(row_explanations)
        for lang in ("ko", "ja", "zh", "en"):
            if not explanations.get(lang, "").strip():
                note(f"missing {lang} explanation", where)
        if kind == "reading" and literal not in clean:
            note("reading question does not show its kanji", f"{where} → {literal}")
        if kind in _WRITE_KINDS and str(options[answer]) in clean:
            note("answer kanji visible in prompt", f"{where} → {options[answer]}")
    return defects


def coverage_report(
    conn: sqlite3.Connection,
    *,
    kanken_image_pending: int = 0,
    missing_advanced_inventory: int = 0,
) -> dict[str, int]:
    def scalar(sql: str, params: tuple[object, ...] = ()) -> int:
        return conn.execute(sql, params).fetchone()[0]

    return {
        "total": scalar("SELECT COUNT(*) FROM kanji"),
        "missing_reading": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM reading r WHERE r.kanji_id = k.id)"),
        "missing_en": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM gloss g WHERE g.kanji_id = k.id AND g.lang = 'en')"),
        "missing_grade": scalar(
            "SELECT COUNT(*) FROM kanji WHERE grade IS NULL"),
        "missing_stroke_order": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM stroke_order s WHERE s.kanji_id = k.id)"),
        "stroke_capability_mismatch": scalar(
            "SELECT COUNT(*) FROM kanji k "
            "WHERE k.has_verified_stroke_order != EXISTS "
            "(SELECT 1 FROM stroke_order s WHERE s.kanji_id = k.id)"
        ),
        "kanji_without_words": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM word_kanji wk WHERE wk.kanji_id = k.id)"),
        "kanji_without_sentences": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM sentence_kanji sk WHERE sk.kanji_id = k.id)"),
        # Proxy: presence of a Korean (ko) gloss stands in for "has a native gloss".
        "kanji_without_native_gloss": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE NOT EXISTS "
            "(SELECT 1 FROM gloss g WHERE g.kanji_id = k.id AND g.lang = 'ko')"),
        "kanken_unicode_advanced": scalar(
            "SELECT COUNT(DISTINCT k.id) FROM kanji k WHERE "
            + _ADVANCED_MEMBERSHIP
        ),
        "kanken_image_pending": kanken_image_pending,
        "kanken_pre1_memberships": scalar(
            "SELECT COUNT(*) FROM kanken_membership "
            "WHERE level_label = '準1級'"
        ),
        "kanken_level1_memberships": scalar(
            "SELECT COUNT(*) FROM kanken_membership "
            "WHERE level_label = '1級'"
        ),
        "kanken_shared_advanced": scalar(
            "SELECT COUNT(*) FROM ("
            "SELECT kanji_id FROM kanken_membership "
            "WHERE level_label IN ('準1級', '1級') "
            "GROUP BY kanji_id HAVING COUNT(DISTINCT level_label) = 2)"
        ),
        "missing_advanced_inventory": missing_advanced_inventory,
        "missing_kanken_membership": scalar(
            "SELECT COUNT(*) FROM kanji k "
            "WHERE k.kanken_level IN ('準1級', '1級') AND NOT "
            + _ADVANCED_MEMBERSHIP
        ),
        "missing_advanced_reading": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE "
            + _ADVANCED_MEMBERSHIP
            + " AND NOT EXISTS (SELECT 1 FROM reading r "
            "WHERE r.kanji_id = k.id AND r.lang_axis IN ('on', 'kun'))"
        ),
        "missing_advanced_meaning": scalar(
            "SELECT COUNT(*) FROM kanji k WHERE "
            + _ADVANCED_MEMBERSHIP
            + " AND NOT EXISTS (SELECT 1 FROM gloss g "
            "WHERE g.kanji_id = k.id AND g.lang = 'en')"
        ),
    }


def assert_core_gates(
    conn: sqlite3.Connection,
    *,
    kanken_allocations: list[KankenAllocation] | None = None,
    kanken_count_policy: KankenCountPolicy | None = None,
    missing_advanced_inventory: int = 0,
) -> dict[str, int]:
    if (kanken_allocations is None) != (kanken_count_policy is None):
        raise ValueError(
            "kanken_allocations and kanken_count_policy must be provided together"
        )

    image_pending = 0
    parsed_unicode_advanced = 0
    parsed_memberships: dict[str, int] = {}
    parsed_advanced_literals: dict[str, set[str]] = {
        "準1級": set(),
        "1級": set(),
    }
    if kanken_allocations is not None:
        parsed_unicode_advanced = len({
            allocation.literal
            for allocation in kanken_allocations
            if allocation.source_level in _ADVANCED_SOURCE_LEVELS
            and allocation.literal is not None
        })
        image_pending = sum(
            allocation.source_level in _ADVANCED_SOURCE_LEVELS
            and allocation.literal is None
            for allocation in kanken_allocations
        )
        for allocation in kanken_allocations:
            if (
                allocation.source_level in _ADVANCED_SOURCE_LEVELS
                and allocation.literal is not None
            ):
                for level in memberships_for(allocation.source_level):
                    parsed_advanced_literals[level].add(allocation.literal)
            if allocation.source_level in kanken_count_policy.legacy_memberships:
                for level in memberships_for(allocation.source_level):
                    parsed_memberships[level] = (
                        parsed_memberships.get(level, 0) + 1
                    )

    report = coverage_report(
        conn,
        kanken_image_pending=image_pending,
        missing_advanced_inventory=missing_advanced_inventory,
    )

    def scalar(sql: str, params: tuple[object, ...] = ()) -> int:
        return conn.execute(sql, params).fetchone()[0]

    missing_required_grade = scalar(
        "SELECT COUNT(*) FROM kanji k WHERE k.grade IS NULL AND (NOT "
        + _ADVANCED_MEMBERSHIP
        + " OR "
        + _LEGACY_KANKEN_MEMBERSHIP
        + ")"
    )
    missing_required_stroke_order = scalar(
        "SELECT COUNT(*) FROM kanji k WHERE (NOT "
        + _ADVANCED_MEMBERSHIP
        + " OR "
        + _JOYO_RECORD
        + " OR "
        + _LEGACY_KANKEN_MEMBERSHIP
        + ") AND NOT EXISTS "
        "(SELECT 1 FROM stroke_order s WHERE s.kanji_id = k.id)"
    )
    missing_required_native_gloss = scalar(
        "SELECT COUNT(*) FROM kanji k WHERE (NOT "
        + _ADVANCED_MEMBERSHIP
        + " OR "
        + _JOYO_RECORD
        + " OR "
        + _LEGACY_KANKEN_MEMBERSHIP
        + ") AND NOT EXISTS "
        "(SELECT 1 FROM gloss g WHERE g.kanji_id = k.id AND g.lang = 'ko')"
    )

    problems: list[str] = []
    if kanken_count_policy is not None:
        if parsed_unicode_advanced != kanken_count_policy.unicode_advanced:
            problems.append(
                "kanken_unicode_advanced expected "
                f"{kanken_count_policy.unicode_advanced}, "
                f"got {parsed_unicode_advanced}"
            )
        if report["kanken_unicode_advanced"] != (
            kanken_count_policy.stored_unicode_advanced
        ):
            problems.append(
                "loaded kanken_unicode_advanced expected "
                f"{kanken_count_policy.stored_unicode_advanced}, "
                f"got {report['kanken_unicode_advanced']}"
            )
        if image_pending != kanken_count_policy.image_pending:
            problems.append(
                "kanken_image_pending expected "
                f"{kanken_count_policy.image_pending}, got {image_pending}"
            )
        report_keys = {
            "準1級": "kanken_pre1_memberships",
            "1級": "kanken_level1_memberships",
        }
        for level, expected in kanken_count_policy.advanced_memberships.items():
            parsed = len(parsed_advanced_literals[level])
            if parsed != expected:
                problems.append(
                    f"parsed {level} memberships expected {expected}, got {parsed}"
                )
        for level, expected in (
            kanken_count_policy.stored_advanced_memberships.items()
        ):
            loaded = report[report_keys[level]]
            if loaded != expected:
                problems.append(
                    f"loaded {level} memberships expected {expected}, got {loaded}"
                )
        parsed_shared = len(
            parsed_advanced_literals["準1級"]
            & parsed_advanced_literals["1級"]
        )
        if parsed_shared != kanken_count_policy.shared_advanced:
            problems.append(
                "parsed shared advanced memberships expected "
                f"{kanken_count_policy.shared_advanced}, got {parsed_shared}"
            )
        if kanken_count_policy.check_playable_sections:
            starved = starved_sections(conn)
            report["starved_sections"] = len(starved)
            if starved:
                problems.append(
                    "playable sections with no data — " + "; ".join(starved))

        if report["kanken_shared_advanced"] != (
            kanken_count_policy.stored_shared_advanced
        ):
            problems.append(
                "loaded shared advanced memberships expected "
                f"{kanken_count_policy.stored_shared_advanced}, "
                f"got {report['kanken_shared_advanced']}"
            )
        for level, expected in kanken_count_policy.legacy_memberships.items():
            parsed = parsed_memberships.get(level, 0)
            if parsed != expected:
                problems.append(
                    f"parsed {level} memberships expected {expected}, got {parsed}"
                )
            loaded = scalar(
                "SELECT COUNT(*) FROM kanken_membership WHERE level_label = ?",
                (level,),
            )
            if loaded != expected:
                problems.append(
                    f"{level} memberships expected {expected}, got {loaded}"
                )
    if report["total"] == 0:
        problems.append("no kanji loaded")
    if report["missing_reading"]:
        problems.append(f"{report['missing_reading']} kanji missing readings")
    if report["missing_en"]:
        problems.append(f"{report['missing_en']} kanji missing EN meaning")
    if missing_required_grade:
        problems.append(f"{missing_required_grade} kanji missing grade")
    if missing_required_stroke_order:
        problems.append(
            f"{missing_required_stroke_order} kanji missing stroke order")
    if missing_required_native_gloss:
        problems.append(
            f"{missing_required_native_gloss} kanji missing native (ko) gloss")
    if report["missing_kanken_membership"]:
        problems.append(
            f"{report['missing_kanken_membership']} kanji missing Kanken membership")
    if report["missing_advanced_inventory"]:
        problems.append(
            f"{report['missing_advanced_inventory']} advanced kanji missing inventory")
    if report["stroke_capability_mismatch"]:
        problems.append(
            f"{report['stroke_capability_mismatch']} kanji stroke capability mismatch")
    if report["missing_advanced_reading"]:
        problems.append(
            f"{report['missing_advanced_reading']} advanced kanji missing Japanese reading")
    if report["missing_advanced_meaning"]:
        problems.append(
            f"{report['missing_advanced_meaning']} advanced kanji missing meaning")
    # word_glosses_{ko,jazh}.jsonl address words by autoincrement id, and were
    # written against the common-word set alone. If an uncommon word carries one
    # of those glosses, ids have shifted and every gloss after the shift now
    # names the wrong word — a silent, repo-wide corruption of the 단어사전.
    misaligned = conn.execute(
        "SELECT COUNT(*) FROM word w JOIN word_gloss g ON g.word_id = w.id "
        "WHERE w.is_common = 0 AND g.lang IN ('ko', 'ja', 'zh')"
    ).fetchone()[0]
    report["misaligned_word_glosses"] = misaligned
    if misaligned:
        problems.append(
            f"{misaligned} uncommon words carry a curated gloss — word ids have "
            "shifted, so the gloss files no longer line up")

    defects = question_defects(conn)
    report["question_defects"] = sum(len(v) for v in defects.values())
    if defects:
        detail = "; ".join(
            f"{name}: {len(cases)} (e.g. {cases[0]})"
            for name, cases in sorted(defects.items())
        )
        problems.append(f"question bank defects — {detail}")

    if problems:
        raise ValueError("coverage gate failed: " + "; ".join(problems))
    return report
