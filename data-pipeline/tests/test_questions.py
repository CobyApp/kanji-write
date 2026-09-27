# tests/test_questions.py
"""Generation rules for the 準1級/1級 exam bank.

These kanji are rare, so questions are derived mechanically from real JMdict
vocabulary rather than authored. That only works if the generator refuses to
emit anything it cannot prove is unambiguous, which is what these tests pin.
"""
import pytest

from kanjipipe.questions import (
    WordRow,
    align_reading,
    build_orthography_question,
    build_reading_question,
    fits_kana_frame,
    kanji_reading_table,
    load_jmdict_lexicon,
    perturb_reading,
    reading_distractors,
    reading_infos,
    surface_shape_ok,
    target_frame,
)


def _rng(seed: int = 7):
    import random
    return random.Random(seed)


# ── reading (読み) ──────────────────────────────────────────────────────────

def test_reading_question_asks_for_the_word_and_marks_it_underlined():
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    q = build_reading_question(
        word, literal="顰", level="1級",
        other_readings=["ちょうしょう", "けんお", "ぶじょく"],
        forbidden={"ひんしゅく"}, rng=_rng())

    assert q is not None
    assert q["kind"] == "reading"
    assert q["prompt"] == "<u>顰蹙</u>"
    assert q["literal"] == "顰"
    assert q["options"][q["answer"]] == "ひんしゅく"
    assert len(q["options"]) == 4
    assert len(set(q["options"])) == 4


def test_reading_question_never_offers_another_valid_reading_of_the_same_word():
    # 遉 is read both さすが and みはり; offering both makes two options correct.
    word = WordRow(surface="流石", reading="さすが", en="as expected")
    q = build_reading_question(
        word, literal="石", level="1級",
        other_readings=["りゅうせき", "みはり", "ながれいし"],
        forbidden={"さすが", "りゅうせき"}, rng=_rng())

    assert q is not None
    assert "りゅうせき" not in q["options"]


def test_reading_question_needs_a_compound_not_a_bare_kanji():
    # 漢検 大問1 always asks for the reading of a 熟語 (or a kanji plus its
    # okurigana). A bare 兌 against く/と/ぶ/だ is a one-mora coin flip.
    word = WordRow(surface="兌", reading="と", en="exchange")
    assert build_reading_question(
        word, literal="兌", level="1級",
        other_readings=["く", "ぶ", "だ"], forbidden={"と"}, rng=_rng()) is None


def test_reading_question_rejects_an_over_long_surface():
    # 皇學館大学 is a university, not vocabulary the paper tests.
    word = WordRow(surface="皇學館大学", reading="こうがっかんだいがく", en="Kogakkan University")
    assert build_reading_question(
        word, literal="學", level="1級",
        other_readings=["かいじょうじえいたい", "とうようひなこうもり", "かくせんあんざんがん"],
        forbidden={"こうがっかんだいがく"}, rng=_rng()) is None


def test_reading_question_dropped_when_distractors_run_out():
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    assert build_reading_question(
        word, literal="顰", level="1級", other_readings=[],
        forbidden={"ひんしゅく"}, rng=_rng()) is None


def test_reading_distractors_are_never_the_answer_itself():
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    q = build_reading_question(
        word, literal="顰", level="1級",
        other_readings=["ひんしゅく", "ひんしゅく", "けんお", "ぶじょく", "そしり"],
        forbidden={"ひんしゅく"}, rng=_rng())
    assert q["options"].count("ひんしゅく") == 1


@pytest.mark.parametrize("reading", ["ひんしゅく", "さすが", "こうてい"])
def test_perturbations_are_kana_and_differ_from_the_source(reading):
    for variant in perturb_reading(reading):
        assert variant != reading
        assert all("ぁ" <= ch <= "ゟ" for ch in variant), variant


# ── orthography (書き取り) ──────────────────────────────────────────────────

def test_orthography_blanks_the_target_kanji_and_shows_the_reading():
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    q = build_orthography_question(
        word, literal="顰", level="1級",
        candidates=["嚬", "瞋", "顳", "蹙"],
        real_surfaces={"顰蹙"}, rng=_rng())

    assert q is not None
    assert q["kind"] == "orthography"
    assert "ひんしゅく" in q["prompt"]
    assert "□蹙" in q["prompt"]
    assert "顰蹙" not in q["prompt"]          # the answer must not be shown
    assert q["options"][q["answer"]] == "顰"
    assert len(q["options"]) == 4


def test_orthography_rejects_a_distractor_that_also_spells_a_real_word():
    # If 嚬蹙 is itself a word, then 嚬 is a defensible answer too.
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    q = build_orthography_question(
        word, literal="顰", level="1級",
        candidates=["嚬", "瞋", "顳", "矚"],
        real_surfaces={"顰蹙", "嚬蹙"}, rng=_rng())

    assert q is not None
    assert "嚬" not in q["options"]


def test_orthography_dropped_when_too_few_safe_distractors():
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    assert build_orthography_question(
        word, literal="顰", level="1級", candidates=["嚬"],
        real_surfaces={"顰蹙", "嚬蹙"}, rng=_rng()) is None


def test_orthography_skips_reduplicated_words():
    # 侃侃諤諤: blanking one 侃 leaves the other one printed in the prompt, so
    # the answer is on screen before the learner picks anything.
    word = WordRow(surface="侃侃諤諤", reading="かんかんがくがく", en="heated debate")
    assert build_orthography_question(
        word, literal="侃", level="1級", candidates=["佞", "俑", "偃"],
        real_surfaces={"侃侃諤諤"}, rng=_rng()) is None


def test_orthography_rejects_an_over_long_surface():
    word = WordRow(surface="皇學館大学", reading="こうがっかんだいがく", en="Kogakkan University")
    assert build_orthography_question(
        word, literal="學", level="1級", candidates=["斈", "壆", "覺"],
        real_surfaces={"皇學館大学"}, rng=_rng()) is None


def test_orthography_skips_single_character_words():
    # Nothing is left to pin the answer once the only kanji is blanked out.
    word = WordRow(surface="顰", reading="しかめ", en="frown")
    assert build_orthography_question(
        word, literal="顰", level="1級", candidates=["嚬", "瞋", "顳"],
        real_surfaces={"顰"}, rng=_rng()) is None


def test_orthography_can_be_tagged_as_a_homophone_question():
    """同音異字 is the same blank-fill with a different candidate pool.

    The distractors are kanji that share the answer's 音読み, so the reading in
    the prompt no longer narrows it down and only the meaning does.
    """
    word = WordRow(surface="公園", reading="こうえん", en="park")
    q = build_orthography_question(
        word, literal="公", level="8級", kind="doonkun",
        candidates=["講", "耕", "鉱"],
        real_surfaces={"公園"}, rng=_rng())

    assert q is not None
    assert q["kind"] == "doonkun"
    assert q["options"][q["answer"]] == "公"
    assert "□園" in q["prompt"]


def test_orthography_defaults_to_the_writing_kind():
    word = WordRow(surface="公園", reading="こうえん", en="park")
    q = build_orthography_question(
        word, literal="公", level="8級", candidates=["講", "耕", "鉱"],
        real_surfaces={"公園"}, rng=_rng())
    assert q["kind"] == "orthography"


# ── shared invariants ───────────────────────────────────────────────────────

def test_no_question_leaks_its_answer_in_the_prompt():
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    reading_q = build_reading_question(
        word, literal="顰", level="1級",
        other_readings=["けんお", "ぶじょく", "そしり"],
        forbidden={"ひんしゅく"}, rng=_rng())
    ortho_q = build_orthography_question(
        word, literal="顰", level="1級", candidates=["嚬", "瞋", "顳"],
        real_surfaces={"顰蹙"}, rng=_rng())

    for q in (reading_q, ortho_q):
        assert q["options"][q["answer"]] not in q["prompt"]


def test_questions_carry_explanations_for_every_supported_language():
    """The app offers ko/ja/zh/en, so an explanation must exist in all four —
    a missing one silently falls back to another language mid-quiz."""
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning", ko="빈축")
    q = build_reading_question(
        word, literal="顰", level="1級",
        other_readings=["けんお", "ぶじょく", "そしり"],
        forbidden={"ひんしゅく"}, rng=_rng())
    assert set(q["explanations"]) >= {"ko", "ja", "zh", "en"}
    assert all(text.strip() for text in q["explanations"].values())


def test_generation_is_deterministic_for_a_fixed_seed():
    word = WordRow(surface="顰蹙", reading="ひんしゅく", en="frowning")
    kwargs = dict(literal="顰", level="1級",
                  other_readings=["けんお", "ぶじょく", "そしり", "ちょうしょう"],
                  forbidden={"ひんしゅく"})
    first = build_reading_question(word, rng=_rng(3), **kwargs)
    second = build_reading_question(word, rng=_rng(3), **kwargs)
    assert first == second


# ── rules from the 準1級/1級 sample reviews ─────────────────────────────────

_TABLE = kanji_reading_table([
    ("砧", "on", "チン"), ("砧", "kun", "きぬた"),
    ("声", "on", "セイ"), ("声", "on", "ショウ"), ("声", "kun", "こえ"),
    ("嬲", "on", "ジョウ"), ("嬲", "kun", "なぶ.る"),
    ("嘖", "on", "サク"), ("肋", "on", "ロク"), ("肋", "kun", "あばら"),
    ("骨", "on", "コツ"), ("骨", "kun", "ほね"),
])


def test_reading_aligns_to_characters_with_sandhi_and_okurigana():
    assert [s for s, _ in align_reading("砧声", "ちんせい", _TABLE)] == ["ちん", "せい"]
    # 促音便 and 連濁 are how readings surface inside compounds.
    assert [s for s, _ in align_reading("肋骨", "ろっこつ", _TABLE)] == ["ろっ", "こつ"]
    assert [s for s, _ in align_reading("肋骨", "あばらぼね", _TABLE)] == ["あばら", "ぼね"]
    assert [s for s, _ in align_reading("嬲る", "なぶる", _TABLE)] == ["なぶ", "る"]
    assert [s for s, _ in align_reading("嘖々", "さくさく", _TABLE)] == ["さく", "さく"]


def test_target_frame_lets_an_unknown_target_reading_take_the_remainder():
    # 砧 read irregularly: the other kanji still pins the frame.
    segs, slots = target_frame("砧声", "きんせい", "砧", _TABLE)
    assert segs == ["きん", "せい"] and slots == {0}
    # 々 repeating the target belongs to the target.
    assert target_frame("嘖々", "さくさく", "嘖", _TABLE)[1] == {0, 1}


def test_reading_distractors_only_change_the_target_slice():
    """砧声: every option must end in 声=せい, or the easy kanji alone picks
    the answer."""
    out = reading_distractors(
        ["ちん", "せい"], {0}, "砧声",
        alternatives={"frame": ["じゅう", "かん", "めい"], "own": ["きぬた"],
                      "lookalike": ["せき"], "near": ["じん"]},
        banned={"ちんせい"}, rng=_rng())
    assert len(out) == 3
    assert all(d.endswith("せい") and d != "ちんせい" for d in out)


def test_reading_distractors_keep_reduplication():
    out = reading_distractors(
        ["さく", "さく"], {0, 1}, "嘖々",
        alternatives={"frame": ["こう", "とう"], "own": [], "lookalike": ["せき"],
                      "near": ["ざく"]},
        banned={"さくさく"}, rng=_rng())
    assert all(d[:len(d) // 2] == d[len(d) // 2:] for d in out)


def test_reading_distractors_never_three_near_misses():
    assert reading_distractors(
        ["ちん", "せい"], {0}, "砧声",
        alternatives={"frame": [], "own": [], "lookalike": [],
                      "near": ["じん", "ちいん", "ちゅん"]},
        banned={"ちんせい"}, rng=_rng()) is None


def test_kana_frame_rejects_distractors_that_drop_the_okurigana():
    assert fits_kana_frame("嬲る", "なぶる", "いじる")
    assert not fits_kana_frame("嬲る", "なぶる", "かなう")
    assert not fits_kana_frame("嘖々", "さくさく", "こうぶん")
    assert fits_kana_frame("嘖々", "さくさく", "こうこう")


def test_fallback_reading_distractors_keep_the_okurigana():
    word = WordRow(surface="嬲る", reading="なぶる")
    q = build_reading_question(
        word, literal="嬲", level="1級",
        other_readings=["かなう", "うずき", "せかす", "いじる", "なじる", "ねぶる"],
        forbidden={"なぶる"}, rng=_rng())
    assert all(o.endswith("る") for o in q["options"])


def test_surface_shape_allows_only_trailing_okurigana():
    assert surface_shape_ok("嬲る")
    assert surface_shape_ok("顰蹙")
    assert not surface_shape_ok("割り鏨")
    assert not surface_shape_ok("鬼の霍乱")
    assert not surface_shape_ok("あい嚢鈔")
    assert surface_shape_ok("包み釦", allow_inner_okurigana=True)
    assert not surface_shape_ok("鬼の霍乱", allow_inner_okurigana=True)


def test_orthography_rejects_a_substitution_that_spells_any_word_with_the_reading():
    # 濯ぐ is also すすぐ in JMdict, though not a vocabulary row of its own.
    word = WordRow(surface="漱ぐ", reading="すすぐ")
    q = build_orthography_question(
        word, literal="漱", level="1級", candidates=["濯", "溯", "滌", "潸"],
        real_surfaces={"漱ぐ"}, reading_spellings={"濯ぐ": {"すすぐ"}},
        rng=_rng())
    assert "濯" not in q["options"]


def test_orthography_never_offers_compat_twins_or_characters_in_the_word():
    word = WordRow(surface="窈窕", reading="ようちょう")
    q = build_orthography_question(
        word, literal="窈", level="1級",
        candidates=["\u7a81", "\ufa55", "窕", "竇", "窄", "窗"],
        real_surfaces={"窈窕"}, rng=_rng())
    assert "\ufa55" not in q["options"]      # compatibility ideograph of 突
    assert "窕" not in q["options"]           # already printed in the word


def test_korean_particles_follow_the_final_sound():
    word = WordRow(surface="焜炉", reading="こんろ", ko="풍로")
    q = build_reading_question(
        word, literal="焜", level="1級",
        other_readings=["かいろ", "でんろ", "おろ"], forbidden={"こんろ"},
        rng=_rng())
    assert q["explanations"]["ko"].startswith("「焜炉」는 こんろ라고")
    assert "풍로" in q["explanations"]["ko"]
    word = WordRow(surface="慇懃", reading="いんぎん", ja="丁寧なこと")
    q = build_reading_question(
        word, literal="懃", level="1級",
        other_readings=["いんけん", "いんしん", "いんもん"],
        forbidden={"いんぎん"}, rng=_rng())
    assert q["explanations"]["ko"].startswith("「慇懃」은 いんぎん이라고")
    assert "丁寧なこと" in q["explanations"]["ja"]


_JMDICT = """<JMdict>
<entry>
<ent_seq>1585320</ent_seq>
<k_ele>
<keb>肋骨</keb>
</k_ele>
<r_ele>
<reb>あばらぼね</reb>
</r_ele>
<r_ele>
<reb>ろっこつ</reb>
</r_ele>
<sense>
<pos>&n;</pos>
<gloss>rib</gloss>
<gloss xml:lang="dut">rib</gloss>
</sense>
</entry>
<entry>
<ent_seq>2007780</ent_seq>
<k_ele>
<keb>搦み</keb>
</k_ele>
<r_ele>
<reb>がらみ</reb>
</r_ele>
<sense>
<pos>&suf;</pos>
<misc>&uk;</misc>
<gloss>about</gloss>
</sense>
</entry>
<entry>
<ent_seq>9</ent_seq>
<k_ele>
<keb>山一證券</keb>
</k_ele>
<r_ele>
<reb>やまいちしょうけん</reb>
</r_ele>
<sense>
<misc>&company;</misc>
<gloss>Yamaichi Securities</gloss>
</sense>
</entry>
</JMdict>
"""


def test_jmdict_lexicon_keeps_every_reading_and_the_tags(tmp_path):
    path = tmp_path / "jmdict.xml"
    path.write_text(_JMDICT, encoding="utf-8")
    lex = load_jmdict_lexicon(path)
    assert lex.all_readings("肋骨") == {"あばらぼね", "ろっこつ"}
    [suffix] = reading_infos(lex, "搦み")
    assert suffix.affix_only
    [company] = reading_infos(lex, "山一證券")
    assert "company" in company.misc
    assert reading_infos(lex, "肋骨")[0].en_gloss == "rib"
