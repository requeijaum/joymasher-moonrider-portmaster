#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE="$ROOT/native/audio-mixer/muos_audio_mixer.c"
BACKEND="$ROOT/native/audio-mixer/miniaudio_backend.c"
BUILD="$ROOT/scripts/build-launcher-backend.sh"

[ -s "$BACKEND" ]
grep -Fq '#include "audio_worker.h"' "$SERVICE"
grep -Fq 'muos_audio_worker_enqueue' "$SERVICE"
grep -Fq 'muos_audio_worker_stop' "$SERVICE"
grep -Fq 'muos_mixer_get_stats' "$SERVICE"

if grep -Eq 'miniaudio\.h|MINIAUDIO_IMPLEMENTATION|\bma_[A-Za-z0-9_]+' "$SERVICE"; then
  echo 'WebKit-facing mixer service must not contain miniaudio lifecycle calls' >&2
  exit 1
fi

grep -Fq 'for unit in audio_command_queue audio_worker muos_audio_mixer miniaudio_backend' "$BUILD"
grep -Fq '"audio-mixer/${unit}.c"' "$BUILD"

python3 - "$SERVICE" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
for name in ('muos_mixer_play', 'muos_mixer_play_pair', 'muos_mixer_stop',
             'muos_mixer_volume', 'muos_mixer_pause', 'muos_mixer_stop_all'):
    m = re.search(r'\b(?:int|void)\s+' + name + r'\s*\([^)]*\)\s*\{', s)
    assert m, f'missing {name}'
    body = s[m.end():s.find('\n}', m.end())]
    assert ('muos_audio_worker_enqueue' in body or 'enqueue_command' in body), f'{name} is not enqueue-only'
    assert 'pthread_join' not in body and 'pthread_cond_wait' not in body, f'{name} waits'
PY

printf 'test-audio-service-contract: OK\n'
