#!/usr/bin/env python3
"""Patch WPE 2.42's compiled injected-bundle directory without shifting ELF data."""

from __future__ import annotations

import hashlib
import os
import pathlib
import sys
from typing import NoReturn

OLD = b"/usr/lib/aarch64-linux-gnu/wpe-webkit-1.1/injected-bundle/"


def fail(message: str) -> NoReturn:
    raise SystemExit(message)


def main() -> None:
    if len(sys.argv) != 3:
        fail(f"usage: {sys.argv[0]} LIBWPEWEBKIT NEW_DIRECTORY_WITH_TRAILING_SLASH")

    binary = pathlib.Path(sys.argv[1])
    new_text = sys.argv[2]
    if not new_text.startswith("/") or not new_text.endswith("/"):
        fail("new directory must be an absolute path ending in '/'")

    try:
        new = new_text.encode("ascii")
    except UnicodeEncodeError:
        fail("new directory must contain ASCII characters only")

    if b"\0" in new:
        fail("new directory must not contain NUL")
    if len(new) > len(OLD):
        fail(f"new directory is too long: {len(new)} > {len(OLD)} bytes")

    original = binary.read_bytes()
    count = original.count(OLD)
    if count != 1:
        fail(f"expected exactly one compiled bundle path, found {count}")

    replacement = new + b"\0" * (len(OLD) - len(new))
    patched = original.replace(OLD, replacement, 1)
    if len(patched) != len(original):
        fail("internal error: ELF size changed")

    mode = binary.stat().st_mode
    temporary = binary.with_name(f".{binary.name}.tmp.{os.getpid()}")
    temporary.write_bytes(patched)
    os.chmod(temporary, mode)
    os.replace(temporary, binary)

    print(f"before_sha256={hashlib.sha256(original).hexdigest()}")
    print(f"after_sha256={hashlib.sha256(patched).hexdigest()}")
    print(f"bundle_directory={new_text}")


if __name__ == "__main__":
    main()
