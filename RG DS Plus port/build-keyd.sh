#!/bin/bash
# Build rgkeyd (global volume/power/back hotkeys) for the RG DS Plus.
# Static aarch64, so it needs nothing from the app bundle.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" || exit; pwd)"
CC="${CROSS_CC:-aarch64-linux-gnu-gcc}"

command -v "$CC" >/dev/null 2>&1 || { echo "missing tool: $CC" >&2; exit 1; }

"$CC" -O2 -static -Wall -Wextra -o "$HERE/rgkeyd" "$HERE/rgkeyd.c"

echo "built: $HERE/rgkeyd"
file "$HERE/rgkeyd"
