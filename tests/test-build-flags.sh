#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

[ "$("$ROOT/scripts/build-flags.sh" baseline)" = '-O2' ]
[ "$("$ROOT/scripts/build-flags.sh" cortex-a53)" = '-O2 -mcpu=cortex-a53 -mtune=cortex-a53' ]
[ "$("$ROOT/scripts/build-flags.sh" cortex-a53-o3)" = '-O3 -mcpu=cortex-a53 -mtune=cortex-a53' ]
if "$ROOT/scripts/build-flags.sh" invalid >/dev/null 2>&1; then
    echo 'FAIL: invalid profile accepted' >&2
    exit 1
fi

echo 'test-build-flags: OK'
