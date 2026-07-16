#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${TMPDIR:-/tmp}/moonrider-test-audio-command-queue"

cc -std=c11 -Wall -Wextra -Werror -pedantic \
  -I"$ROOT/native/audio-mixer" \
  "$ROOT/tests/test-audio-command-queue.c" \
  "$ROOT/native/audio-mixer/audio_command_queue.c" \
  -lm -o "$OUT"
"$OUT"

cc -std=c11 -Wall -Wextra -Werror -pedantic \
  -fsanitize=address,undefined -fno-omit-frame-pointer \
  -I"$ROOT/native/audio-mixer" \
  "$ROOT/tests/test-audio-command-queue.c" \
  "$ROOT/native/audio-mixer/audio_command_queue.c" \
  -lm -o "$OUT-asan"
ASAN_OPTIONS=detect_leaks=1 "$OUT-asan"
