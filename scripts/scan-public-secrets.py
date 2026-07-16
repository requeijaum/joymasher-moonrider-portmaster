#!/usr/bin/env python3
"""Scan tracked public-tree text for likely static credentials and private keys."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATIC_ASSIGNMENT = re.compile(
    r"""(?ix)
    \b(?:password|passwd|sshpass|api[_-]?key|client[_-]?secret|secret|access[_-]?token|token)\b
    \s*[:=]\s*
    (?P<quote>["'])
    (?P<value>[A-Za-z0-9_./+=:@-]{6,})
    (?P=quote)
    """
)
PRIVATE_KEY = re.compile(r"-----BEGIN (?:RSA|OPENSSH|EC|DSA) PRIVATE KEY-----")


def tracked_files() -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "-z"], cwd=ROOT, check=True, capture_output=True
    )
    return [ROOT / item.decode("utf-8", "surrogateescape") for item in result.stdout.split(b"\0") if item]


def scan(path: Path) -> list[tuple[int, str]]:
    data = path.read_bytes()
    if b"\0" in data[:8192]:
        return []
    text = data.decode("utf-8", "replace")
    findings: list[tuple[int, str]] = []
    for number, line in enumerate(text.splitlines(), 1):
        if STATIC_ASSIGNMENT.search(line) or PRIVATE_KEY.search(line):
            findings.append((number, line.strip()))
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    args = parser.parse_args()
    paths = args.paths or tracked_files()
    found = False
    for path in paths:
        candidate = path if path.is_absolute() else ROOT / path
        try:
            findings = scan(candidate)
        except OSError as error:
            print(f"secret scan could not read {candidate}: {error}", file=sys.stderr)
            return 2
        for line_number, line in findings:
            try:
                display = candidate.relative_to(ROOT)
            except ValueError:
                display = candidate
            print(f"{display}:{line_number}:{line}")
            found = True
    if found:
        print("Potential hard-coded secret detected.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
