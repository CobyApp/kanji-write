# kanjipipe/validate.py
import sqlite3


def coverage_report(conn: sqlite3.Connection) -> dict[str, int]:
    def scalar(sql: str) -> int:
        return conn.execute(sql).fetchone()[0]

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
    }


def assert_core_gates(conn: sqlite3.Connection) -> dict[str, int]:
    report = coverage_report(conn)
    problems: list[str] = []
    if report["total"] == 0:
        problems.append("no kanji loaded")
    if report["missing_reading"]:
        problems.append(f"{report['missing_reading']} kanji missing readings")
    if report["missing_en"]:
        problems.append(f"{report['missing_en']} kanji missing EN meaning")
    if report["missing_grade"]:
        problems.append(f"{report['missing_grade']} kanji missing grade")
    if report["missing_stroke_order"]:
        problems.append(
            f"{report['missing_stroke_order']} kanji missing stroke order")
    if problems:
        raise ValueError("coverage gate failed: " + "; ".join(problems))
    return report
