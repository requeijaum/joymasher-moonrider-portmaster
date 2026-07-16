#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT=$(mktemp /tmp/moonrider-input-mailbox.XXXXXX)
trap 'rm -f "$OUT"' EXIT
cc -std=c11 -Wall -Wextra -Werror \
  -I"$ROOT/native/backend" \
  "$ROOT/tests/test-input-mailbox.c" \
  "$ROOT/native/backend/input_mailbox.c" \
  -o "$OUT"
"$OUT"
printf 'test-input-mailbox: OK\n'
