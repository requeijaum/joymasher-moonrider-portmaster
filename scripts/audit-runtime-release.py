#!/usr/bin/env python3
"""Fail-closed redistribution audit for a candidate Moonrider runtime ZIP."""

from __future__ import annotations

import argparse
import hashlib
import json
import posixpath
import stat
from pathlib import Path, PurePosixPath
from zipfile import BadZipFile, ZipFile

FORBIDDEN_EXTENSIONS = {
    ".asar", ".exe", ".ogg", ".mp3", ".wav", ".flac", ".m4a", ".aac",
    ".mp4", ".webm", ".png", ".jpg", ".jpeg", ".webp",
}
BINARY_EXTENSIONS = {
    ".a", ".bin", ".dll", ".dylib", ".elf", ".node", ".so",
}
MAX_ENTRIES = 20_000
MAX_ENTRY_BYTES = 1024 * 1024 * 1024
MAX_TOTAL_UNCOMPRESSED_BYTES = 4 * 1024 * 1024 * 1024
MIN_RATIO_CHECK_BYTES = 1024 * 1024
MAX_COMPRESSION_RATIO = 1000


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def is_binary_candidate(path: PurePosixPath) -> bool:
    base = path.name.lower()
    parts = {part.lower() for part in path.parts[:-1]}
    return (
        path.suffix.lower() in BINARY_EXTENSIONS
        or ".so." in base
        or bool(parts & {"bin", "sbin", "libexec"})
    )


def is_unsafe_path(name: str, path: PurePosixPath) -> bool:
    return (
        path.is_absolute()
        or ".." in path.parts
        or "\\" in name
        or name.startswith(("/", "\\"))
    )


def is_unsafe_symlink(path: PurePosixPath, target: str) -> bool:
    if not target or "\x00" in target or "\\" in target or target.startswith("/"):
        return True
    resolved = posixpath.normpath(posixpath.join(str(path.parent), target))
    return resolved == ".." or resolved.startswith("../") or resolved.startswith("/")


def audit(archive: Path) -> dict[str, object]:
    elf_names: list[str] = []
    binary_payload_names: list[str] = []
    license_names: list[str] = []
    provenance_names: list[str] = []
    forbidden_names: list[str] = []
    unsafe_paths: list[str] = []
    suspicious_compression: list[dict[str, object]] = []
    oversized_entries: list[str] = []
    encrypted_entries: list[str] = []
    duplicate_entries: list[str] = []
    unsafe_symlinks: list[dict[str, str]] = []
    seen_names: set[str] = set()
    total_uncompressed = 0
    file_count = 0

    with ZipFile(archive) as bundle:
        infos = sorted(bundle.infolist(), key=lambda item: item.filename)
        for info in infos:
            if info.is_dir():
                continue
            file_count += 1
            total_uncompressed += info.file_size
            name = info.filename
            path = PurePosixPath(name)
            lower = name.lower()
            base = path.name.lower()

            normalized_name = posixpath.normpath(name)
            if normalized_name in seen_names:
                duplicate_entries.append(name)
            seen_names.add(normalized_name)
            if is_unsafe_path(name, path):
                unsafe_paths.append(name)
            if info.flag_bits & 0x1:
                encrypted_entries.append(name)
            if info.file_size > MAX_ENTRY_BYTES:
                oversized_entries.append(name)
            if info.file_size >= MIN_RATIO_CHECK_BYTES:
                ratio = info.file_size / max(info.compress_size, 1)
                if ratio > MAX_COMPRESSION_RATIO:
                    suspicious_compression.append({
                        "path": name,
                        "uncompressed_bytes": info.file_size,
                        "compressed_bytes": info.compress_size,
                        "ratio": round(ratio, 2),
                    })

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

            binary_candidate = is_binary_candidate(path)
            is_elf = False
            is_symlink = stat.S_ISLNK((info.external_attr >> 16) & 0xFFFF)
            if not (info.flag_bits & 0x1):
                with bundle.open(info) as stream:
                    if is_symlink:
                        raw_target = stream.read(4097)
                        try:
                            target = raw_target.decode("utf-8")
                        except UnicodeDecodeError:
                            target = "<non-UTF-8>"
                        if len(raw_target) > 4096 or is_unsafe_symlink(path, target):
                            unsafe_symlinks.append({"path": name, "target": target})
                    else:
                        is_elf = stream.read(4) == b"\x7fELF"
            if is_elf:
                elf_names.append(name)
            if binary_candidate or is_elf:
                binary_payload_names.append(name)

    provenance_bases = {PurePosixPath(name).name.lower() for name in provenance_names}
    blockers: list[str] = []
    if file_count > MAX_ENTRIES:
        blockers.append("archive entry limit exceeded")
    if total_uncompressed > MAX_TOTAL_UNCOMPRESSED_BYTES:
        blockers.append("archive uncompressed size limit exceeded")
    if oversized_entries:
        blockers.append("oversized archive entry detected")
    if suspicious_compression:
        blockers.append("unsafe compression ratio detected")
    if unsafe_paths:
        blockers.append("unsafe archive path detected")
    if unsafe_symlinks:
        blockers.append("unsafe symlink target detected")
    if duplicate_entries:
        blockers.append("duplicate archive path detected")
    if encrypted_entries:
        blockers.append("encrypted archive entry detected")
    if forbidden_names:
        blockers.append("forbidden commercial/media payload detected")
    if not binary_payload_names:
        blockers.append("no runtime binary payload detected")
    if binary_payload_names and not license_names:
        blockers.append("missing license bundle")
    if binary_payload_names and "source_provenance.json" not in provenance_bases:
        blockers.append("missing source provenance")
    if binary_payload_names and "third_party_manifest.json" not in provenance_bases:
        blockers.append("missing third-party component manifest")

    return {
        "schema": 2,
        "archive": archive.name,
        "archive_sha256": sha256_file(archive),
        "entries": file_count,
        "total_uncompressed_bytes": total_uncompressed,
        "elf_files": len(elf_names),
        "elf_paths": elf_names,
        "binary_payload_files": len(binary_payload_names),
        "binary_payload_paths": binary_payload_names,
        "license_files": license_names,
        "provenance_files": provenance_names,
        "forbidden_payload": forbidden_names,
        "unsafe_paths": unsafe_paths,
        "unsafe_symlinks": unsafe_symlinks,
        "duplicate_entries": duplicate_entries,
        "encrypted_entries": encrypted_entries,
        "oversized_entries": oversized_entries,
        "suspicious_compression": suspicious_compression,
        "limits": {
            "max_entries": MAX_ENTRIES,
            "max_entry_bytes": MAX_ENTRY_BYTES,
            "max_total_uncompressed_bytes": MAX_TOTAL_UNCOMPRESSED_BYTES,
            "max_compression_ratio": MAX_COMPRESSION_RATIO,
        },
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
    except (BadZipFile, RuntimeError) as exc:
        parser.error(str(exc))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({
        "archive": report["archive"],
        "elf_files": report["elf_files"],
        "binary_payload_files": report["binary_payload_files"],
        "blockers": report["blockers"],
        "release_eligible": report["release_eligible"],
    }, sort_keys=True))
    return 0 if report["release_eligible"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
