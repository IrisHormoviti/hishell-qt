#!/usr/bin/env bash
# Headless smoke interaction test for the qtbridge frontend.
#
# Exercises startup, session persistence, image thumbnails, and a descriptor
# generator end to end. Run with HISHELL_QT_BIN pointing at the built binary.
set -euo pipefail

BIN="${HISHELL_QT_BIN:?set HISHELL_QT_BIN to the built hishell-qt binary}"
ROOT="$(mktemp -d /tmp/hishell-smoke-XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/dir" "$ROOT/data/hishell/descriptor-generators" "$ROOT/cache" "$ROOT/config"

# A thumbnail fixture. Fall back to any PNG on the host.
PNG="$(find /usr/share/icons -name '*.png' -type f 2>/dev/null | head -1 || true)"
if [ -n "$PNG" ]; then
	cp "$PNG" "$ROOT/dir/photo.png"
fi

# A descriptor generator for text files.
printf 'hello\n' > "$ROOT/dir/note.txt"
cat > "$ROOT/gen.sh" <<'GEN'
#!/bin/sh
printf '[Desktop Entry]\nType=File\nPath=%s\nName=Generated Title\nIcon=application-x-test\n' "$1" > "$2"
GEN
chmod +x "$ROOT/gen.sh"
cat > "$ROOT/data/hishell/descriptor-generators/test.descriptor-generator" <<GEN
[Descriptor Generator Entry]
Exec=$ROOT/gen.sh %i %o
MimeType=text/plain;
Icon=text-x-generic
GEN

set +e
XDG_DATA_HOME="$ROOT/data" \
XDG_DATA_DIRS="$ROOT/data:/usr/share" \
XDG_CACHE_HOME="$ROOT/cache" \
XDG_CONFIG_HOME="$ROOT/config" \
QT_QPA_PLATFORM=offscreen \
timeout 6 "$BIN" "$ROOT/dir" >"$ROOT/run.log" 2>&1
status=$?
set -e
# The app runs until the timeout.
if [ "$status" -ne 124 ]; then
	cat "$ROOT/run.log"
	echo "smoke: app exited with $status" >&2
	exit 1
fi

test -f "$ROOT/config/hishell/session.json"
grep -q "$ROOT/dir" "$ROOT/config/hishell/session.json"

if [ -n "$PNG" ]; then
	find "$ROOT/cache/hishell/thumbnails" -name '*.png' -type f | grep -q .
fi

find "$ROOT/cache/hishell/descriptors" -name '*.desktop' -type f | grep -q .
grep -q 'Generated Title' "$ROOT"/cache/hishell/descriptors/*.desktop

echo "smoke: session, thumbnail, and descriptor generator ok"
