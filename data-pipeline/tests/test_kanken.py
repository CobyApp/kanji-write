from pathlib import Path
import hashlib
import subprocess
import sys

import pytest

from kanjipipe.ingest.kanken import memberships_for, parse_kanken_allocations
from kanjipipe.models import KankenAllocation


FIX = Path(__file__).parent / "fixtures"


def test_parse_kanken_allocations_handles_unicode_and_image_rows():
    rows = parse_kanken_allocations(FIX / "kanken_sample.csv")

    assert rows[0] == KankenAllocation(
        ct_id="CT-000002",
        ce_id="CE-000003",
        literal="亞",
        variant_kind="旧字",
        source_level="1/準1級",
    )
    assert rows[1] == KankenAllocation(
        ct_id="CT-000010",
        ce_id="CE-000013",
        literal=None,
        variant_kind="旧字でない異体字",
        source_level="1級",
    )


def test_shared_level_expands_to_two_memberships():
    assert memberships_for("1/準1級") == ("準1級", "1級")


def test_unknown_level_fails():
    with pytest.raises(ValueError, match="unknown Kanken level"):
        memberships_for("特級")


def test_fetch_script_pins_unihan_and_keeps_license_notice():
    pipeline = Path(__file__).parents[1]
    script = (pipeline / "scripts/fetch_sources.sh").read_text(encoding="utf-8")

    assert "https://www.unicode.org/Public/17.0.0/ucd/Unihan.zip" in script
    assert (
        "f7a48b2b545acfaa77b2d607ae28747404ce02baefee16396c5d2d7a8ef34b5e"
        in script
    )
    assert (pipeline / "UNICODE-LICENSE-3.txt").exists()


def test_sha256_verifier_fails_closed_on_mismatch(tmp_path):
    pipeline = Path(__file__).parents[1]
    verifier = pipeline / "scripts/verify_sha256.py"
    source = tmp_path / "source.bin"
    source.write_bytes(b"pinned source")
    digest = hashlib.sha256(source.read_bytes()).hexdigest()

    matched = subprocess.run(
        [sys.executable, verifier, digest, source],
        capture_output=True,
        text=True,
    )
    mismatched = subprocess.run(
        [sys.executable, verifier, "0" * 64, source],
        capture_output=True,
        text=True,
    )

    assert matched.returncode == 0
    assert mismatched.returncode != 0
    assert "SHA-256 mismatch" in mismatched.stderr


def test_sha256_verifier_is_in_repository_change_set():
    pipeline = Path(__file__).parents[1]
    verifier = pipeline / "scripts/verify_sha256.py"
    repository = pipeline.parent
    relative_path = verifier.relative_to(repository)

    result = subprocess.run(
        [
            "git",
            "-C",
            repository,
            "ls-files",
            "--error-unmatch",
            str(relative_path),
        ],
        capture_output=True,
        text=True,
    )

    assert verifier.is_file()
    assert result.returncode == 0, (
        "verify_sha256.py must be version-controlled so fetch_sources.sh "
        "works in a clean checkout"
    )


def test_fetch_script_pins_and_verifies_every_build_input():
    pipeline = Path(__file__).parents[1]
    script = (pipeline / "scripts/fetch_sources.sh").read_text(encoding="utf-8")

    assert "/kanji-data/master/" not in script
    assert "JLPT_COMMIT=" in script
    for pin_name in (
        "KANJIDIC2",
        "KANJIVG",
        "KANKEN",
        "UNIHAN",
        "JLPT_SOURCE",
        "JLPT_OUTPUT",
        "JMDICT",
        "TATOEBA_SENTENCES_ARCHIVE",
        "TATOEBA_SENTENCES",
        "TATOEBA_LINKS_ARCHIVE",
        "TATOEBA_LINKS",
        "LLM_GLOSSES",
        "WORD_GLOSSES_KO",
        "WORD_GLOSSES_JAZH",
        "SENTENCE_GLOSSES",
        "JLPT_QUESTIONS",
        "KANKEN_SUPPLEMENT",
        "YOJIJUKUGO",
        "TAIGIRUI",
    ):
        assert f"{pin_name}_SHA256=" in script
        assert f'verify_sha256 "${{{pin_name}_SHA256}}"' in script
