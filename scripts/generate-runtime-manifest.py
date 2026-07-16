#!/usr/bin/env python3
"""Generate the complete SHA-256 inventory required for a Moonrider runtime."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("runtime", type=Path)
    args = parser.parse_args()
    runtime = args.runtime.resolve()
    if not runtime.is_dir():
        raise SystemExit(f"runtime directory not found: {runtime}")

    manifest = runtime / "RUNTIME-MANIFEST.sha256"
    files: list[Path] = []
    for path in runtime.rglob("*"):
        if path == manifest:
            continue
        if path.is_symlink():
            raise SystemExit(f"unsupported runtime entry: {path.relative_to(runtime)}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise SystemExit(f"unsupported runtime entry: {path.relative_to(runtime)}")
        files.append(path)

    lines = [
        f"{hashlib.sha256(path.read_bytes()).hexdigest()}  "
        f"{path.relative_to(runtime).as_posix()}"
        for path in sorted(files)
    ]
    manifest.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print(f"Wrote {manifest} ({len(lines)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
