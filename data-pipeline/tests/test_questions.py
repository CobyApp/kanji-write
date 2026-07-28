# tests/test_questions.py
"""Generation rules for the 準1級/1級 exam bank.

These kanji are rare, so questions are derived mechanically from real JMdict
vocabulary rather than authored. That only works if the generator refuses to
emit anything it cannot prove is unambiguous, which is what these tests pin.
"""
import pytest

from kanjipipe.questions import (
    WordRow,
    build_orthography_question,
    build_reading_question,
    perturb_reading,
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
