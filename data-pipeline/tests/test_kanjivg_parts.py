from kanjipipe.ingest.kanjivg_parts import parse_kanjivg_parts

SAMPLE = """<?xml version="1.0" encoding="UTF-8"?>
<kanjivg xmlns:kvg="http://kanjivg.tagaini.net">
  <kanji id="kvg:kanji_06d77">
    <g kvg:element="海">
      <g kvg:element="氵" kvg:radical="general"><path d="M1 1"/></g>
      <g kvg:element="毎"><g kvg:element="丿"><path d="M2 2"/></g><g kvg:element="毋"><path d="M3 3"/></g></g>
    </g>
  </kanji>
  <kanji id="kvg:kanji_0805e">
    <g kvg:element="聞">
      <g kvg:element="門" kvg:radical="nelson"><path d="M1 1"/></g>
      <g kvg:element="耳" kvg:radical="tradit"><path d="M2 2"/></g>
    </g>
  </kanji>
  <kanji id="kvg:kanji_04e00">
    <g kvg:element="一"><path d="M1 1"/></g>
  </kanji>
</kanjivg>
"""


def test_radical_form_and_parts(tmp_path):
    path = tmp_path / "kvg.xml"
    path.write_text(SAMPLE, encoding="utf-8")
    parts = parse_kanjivg_parts(path)
    assert parts[ord("海")] == ("氵", ["毎", "丿", "毋"])
    # 漢検 follows the traditional classification: 聞 is under 耳, not 門.
    assert parts[ord("聞")] == ("耳", ["門"])
    # A kanji that is itself a radical has no separate radical group.
    assert ord("一") not in parts
