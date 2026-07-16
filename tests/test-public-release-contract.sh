#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"

require_file() {
  [ -s "$1" ] || { echo "missing required public-release file: $1" >&2; exit 1; }
}

require_file LICENSE
require_file THIRD_PARTY_NOTICES.md
require_file CONTRIBUTING.md
require_file SECURITY.md
require_file CODE_OF_CONDUCT.md
require_file KNOWN_ISSUES.md
require_file .github/workflows/ci.yml
require_file .github/workflows/release.yml
require_file .github/ISSUE_TEMPLATE/bug_report.yml
require_file .github/ISSUE_TEMPLATE/config.yml
require_file scripts/verify-public-release.sh
require_file scripts/make-source-preview.sh
require_file scripts/audit-runtime-release.py
require_file scripts/scan-public-secrets.py
require_file tests/test-source-preview-package.sh
require_file tests/test-public-secret-scan.sh
require_file tests/test-runtime-release-audit.sh
require_file reports/RUNTIME-REDISTRIBUTION-AUDIT-20260715.md
require_file docs/releases/v0.1.0-alpha.1.md
require_file docs/releases/v0.1.0-alpha.2.md

 grep -q 'Apache License' LICENSE
 grep -q 'Version 2.0' LICENSE
 grep -q 'WPE WebKit' THIRD_PARTY_NOTICES.md
 grep -q 'GStreamer' THIRD_PARTY_NOTICES.md
 grep -q 'miniaudio' THIRD_PARTY_NOTICES.md
 grep -q 'runtime-fixes/libGL.so.1' THIRD_PARTY_NOTICES.md
 grep -q 'It is.*not' THIRD_PARTY_NOTICES.md
 grep -q 'third-party WPE runtime' THIRD_PARTY_NOTICES.md
 grep -q '23 fps' KNOWN_ISSUES.md
 grep -q '7.*13 fps' KNOWN_ISSUES.md
 grep -q '1.79 s' KNOWN_ISSUES.md
 grep -q 'Development preview' README.md

# Public docs must not contain private LAN endpoints or machine-specific backup paths.
if git grep -nE '192\.168\.1\.[0-9]+|/home/[^ /]+|/media/[^ /]+' -- \
  README.md CONTRIBUTING.md SECURITY.md KNOWN_ISSUES.md THIRD_PARTY_NOTICES.md TODO.md docs reports scripts; then
  echo 'private infrastructure leaked into public documentation' >&2
  exit 1
fi

# Commercial game payloads must never be tracked.
if git ls-files | grep -Ei '\.(ogg|mp3|wav|flac|m4a|aac|mp4|webm|png|jpe?g|webp|asar|exe)$'; then
  echo 'copyrighted/binary game payload extension is tracked' >&2
  exit 1
fi

# Runtime and shims must agree on the canonical game directory.
if git grep -n 'moonrider-game' -- shims runtime-fixes; then
  echo 'legacy moonrider-game path remains in runtime source' >&2
  exit 1
fi

# Third-party runtime binaries stay out of moonrider/runtime in source previews.
# The project-built GLX stub is separately covered and tracked under runtime-fixes/.
if git ls-files moonrider/runtime | grep -v '^moonrider/runtime/README.md$'; then
  echo 'runtime binary unexpectedly tracked in source tree' >&2
  exit 1
fi

echo 'test-public-release-contract: OK'
