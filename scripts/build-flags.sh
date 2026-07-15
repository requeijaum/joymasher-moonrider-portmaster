#!/bin/sh
set -eu
case "${1:-baseline}" in
    baseline) printf '%s\n' '-O2' ;;
    cortex-a53) printf '%s\n' '-O2 -mcpu=cortex-a53 -mtune=cortex-a53' ;;
    cortex-a53-o3) printf '%s\n' '-O3 -mcpu=cortex-a53 -mtune=cortex-a53' ;;
    *) echo "unknown build profile: $1" >&2; exit 2 ;;
esac
