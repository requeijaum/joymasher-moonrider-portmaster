#!/usr/bin/env python3
"""Fail-closed redistribution audit for a candidate Moonrider runtime ZIP."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
from zipfile import BadZipFile, ZipFile

FORBIDDEN_EXTENSIONS = {
    ".asar", ".exe", ".ogg", ".mp3", ".wav", ".mp4", ".webm",
    ".png", ".jpg", ".jpeg", ".webp",
}


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def audit(archive: Path) -> dict[str, object]:
    elf_names: list[str] = []
    license_names: list[str] = []
    provenance_names: list[str] = []
    forbidden_names: list[str] = []
    total_uncompressed = 0
    file_count = 0

    with ZipFile(archive) as bundle:
        for info in sorted(bundle.infolist(), key=lambda item: item.filename):
            if info.is_dir():
                continue
            file_count += 1
            total_uncompressed += info.file_size
            name = info.filename
            path = PurePosixPath(name)
            lower = name.lower()
            base = path.name.lower()

            if path.suffix.lower() in FORBIDDEN_EXTENSIONS:
                forbidden_names.append(name)
            if (
                "/licenses/" in f"/{lower}"
                or base.startswith("license")
                or base.startswith("copying")
                or base.startswith("notice")
            ):
                license_names.append(name)
            if base in {
                "source_provenance.json",
                "third_party_manifest.json",
                "build_provenance.json",
            }:
                provenance_names.append(name)
            with bundle.open(info) as stream:
                if stream.read(4) == b"\x7fELF":
                    elf_names.append(name)

    provenance_bases = {PurePosixPath(name).name.lower() for name in provenance_names}
    blockers: list[str] = []
    if forbidden_names:
        blockers.append("forbidden commercial/media payload detected")
    if elf_names and not license_names:
        blockers.append("missing license bundle")
    if elf_names and "source_provenance.json" not in provenance_bases:
        blockers.append("missing source provenance")
    if elf_names and "third_party_manifest.json" not in provenance_bases:
        blockers.append("missing third-party component manifest")

    return {
        "schema": 1,
        "archive": archive.name,
        "archive_sha256": sha256_file(archive),
        "entries": file_count,
        "total_uncompressed_bytes": total_uncompressed,
        "elf_files": len(elf_names),
        "elf_paths": elf_names,
        "license_files": license_names,
        "provenance_files": provenance_names,
        "forbidden_payload": forbidden_names,
        "blockers": blockers,
        "release_eligible": not blockers,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    if not args.archive.is_file():
        parser.error(f"archive not found: {args.archive}")
    try:
        report = audit(args.archive)
    except BadZipFile as exc:
        parser.error(str(exc))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "archive": report["archive"],
        "elf_files": report["elf_files"],
        "blockers": report["blockers"],
        "release_eligible": report["release_eligible"],
    }, sort_keys=True))
    return 0 if report["release_eligible"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
