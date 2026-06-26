# tests/test_jmdict_relations.py
from pathlib import Path

from kanjipipe.ingest.jmdict_relations import parse_jmdict_relations

FIXTURE = Path(__file__).parent / "fixtures" / "jmdict_sample.xml"


def test_extracts_antonym_and_related_with_target_stripped():
    relations = parse_jmdict_relations(FIXTURE)
    tuples = {(r.source_surface, r.target_surface, r.type) for r in relations}
    assert ("山", "学校", "related") in tuples       # from 山's <xref>学校</xref>
    assert ("学校", "山", "antonym") in tuples        # from 学校's <ant>山・やま・1</ant>, stripped to 山


def test_entries_without_relations_produce_none():
    # Only entries 1 and 2 carry ant/xref → exactly two relations.
    assert len(parse_jmdict_relations(FIXTURE)) == 2
