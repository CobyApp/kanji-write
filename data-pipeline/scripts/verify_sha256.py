#!/usr/bin/env python3
import hashlib
import sys
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: verify_sha256.py EXPECTED_SHA256 PATH", file=sys.stderr)
        return 2

    expected, raw_path = sys.argv[1:]
    path = Path(raw_path)
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        print(
            f"SHA-256 mismatch for {path}: expected {expected}, got {actual}",
            file=sys.stderr,
        )
        return 1

    print(f"{path}: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
