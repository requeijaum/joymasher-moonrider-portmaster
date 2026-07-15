#!/usr/bin/env python3
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
PATCHER = ROOT / "scripts" / "patch-wpe-injected-bundle-path.py"
OLD = b"/usr/lib/aarch64-linux-gnu/wpe-webkit-1.1/injected-bundle/"
NEW = b"/mnt/mmc/w42/injected-bundle/"

with tempfile.TemporaryDirectory() as td:
    binary = pathlib.Path(td) / "libWPEWebKit.so"
    original = b"PREFIX" + OLD + b"SUFFIX"
    binary.write_bytes(original)

    subprocess.run([sys.executable, str(PATCHER), str(binary), NEW.decode()], check=True)
    patched = binary.read_bytes()
    expected_slot = NEW + b"\0" * (len(OLD) - len(NEW))

    assert len(patched) == len(original)
    assert OLD not in patched
    assert expected_slot in patched

    duplicate = pathlib.Path(td) / "duplicate.so"
    duplicate.write_bytes(OLD + OLD)
    result = subprocess.run(
        [sys.executable, str(PATCHER), str(duplicate), NEW.decode()],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert result.returncode != 0

print("test-patch-wpe-injected-bundle-path: OK")
