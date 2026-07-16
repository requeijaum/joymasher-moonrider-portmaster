#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/moonrider-test-audio-worker"
SOURCES=(
  "$ROOT/tests/test-audio-worker.c"
  "$ROOT/native/audio-mixer/audio_worker.c"
  "$ROOT/native/audio-mixer/audio_command_queue.c"
)

cc -std=c11 -Wall -Wextra -Werror -pedantic -pthread \
  -I"$ROOT/native/audio-mixer" "${SOURCES[@]}" -o "$OUT"
"$OUT"

cc -std=c11 -Wall -Wextra -Werror -pedantic -pthread \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$ROOT/native/audio-mixer" "${SOURCES[@]}" -o "$OUT-asan"
ASAN_OPTIONS=detect_leaks=1 "$OUT-asan"
