#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND="$ROOT/native/audio-mixer/miniaudio_backend.c"

if grep -Fq 'MA_SOUND_FLAG_ASYNC' "$BACKEND"; then
  echo 'async sound initialization is forbidden in the owner backend' >&2
  exit 1
fi

python3 - "$BACKEND" <<'PY'
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
assert re.search(r'#define\s+MUOS_MAX_VOICES\s+(?:9[6-9]|1[0-9]{2,})', s), 'retirement headroom missing'
assert re.search(r'\bint\s+retiring\s*;', s), 'voice retirement state missing'
assert re.search(r'\buint64_t\s+retire_after_ns\s*;', s), 'retirement grace deadline missing'
assert s.count('ma_sound_uninit(') == 1, 'ma_sound_uninit must have one controlled call site'

def body(name):
    m = re.search(r'\b(?:static\s+)?(?:int|void)\s+' + name + r'\s*\([^)]*\)\s*\{', s)
    assert m, f'missing {name}'
    start = m.end(); depth = 1; i = start
    while depth and i < len(s):
        depth += (s[i] == '{') - (s[i] == '}')
        i += 1
    assert depth == 0, f'unbalanced {name}'
    return s[start:i-1]

for name in ('core_stop', 'init_voice', 'reap_finished_voices'):
    b = body(name)
    assert 'retire_voice' in b, f'{name} must retire, not uninit immediately'
    assert 'ma_sound_uninit' not in b, f'{name} uninitializes synchronously'

assert 'ma_sound_stop' in body('retire_voice')
assert 'retire_after_ns' in body('retire_voice')
assert 'destroy_voice' in body('reap_retired_voices')
assert 'destroy_voice' in body('core_shutdown')
PY

printf 'test-audio-lifecycle-contract: OK\n'
