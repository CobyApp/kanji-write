"""The radical reference ships complete: all 214 Kangxi radicals, each with a
glyph, a Japanese 部首名, and a meaning in every language."""
import json
from pathlib import Path

from kanjipipe.db import init_db
from kanjipipe.loader import load_radical_reference
from kanjipipe.validate import radical_reference_defects

SOURCE = (Path(__file__).resolve().parents[2]
          / "app/Sources/DictionaryClient/Resources/radical_reference.source.json")


def _loaded(tmp_path):
    con = init_db(str(tmp_path / "t.sqlite"))
    load_radical_reference(con, SOURCE)
    return con


def test_source_has_all_214_radicals():
    data = json.loads(SOURCE.read_text("utf-8"))
    assert len(data) == 214
    assert sorted(r["number"] for r in data) == list(range(1, 215))


def test_loaded_reference_has_no_defects(tmp_path):
    con = _loaded(tmp_path)
    assert radical_reference_defects(con) == []


def test_gate_flags_a_missing_radical(tmp_path):
    con = _loaded(tmp_path)
    con.execute("DELETE FROM radical_reference WHERE number = 140")
    con.commit()
    problems = radical_reference_defects(con)
    assert any("140" in p and "missing" in p for p in problems)


def test_gate_flags_a_blank_translation(tmp_path):
    con = _loaded(tmp_path)
    con.execute("UPDATE radical_reference SET meaning_ko = '' WHERE number = 1")
    con.commit()
    problems = radical_reference_defects(con)
    assert any("1:" in p and "meaning_ko" in p for p in problems)
