#!/usr/bin/env bash
# Scripted UI interaction test for the qtbridge frontend.
#
# Runs the built-in SelfTest.qml sequence: rename/trash/open-with dialogs,
# drag/drop copy, cross-pane hand-off, NavigationPlan transition, and gamepad
# focus movement. Run with HISHELL_QT_BIN pointing at the built binary.
set -euo pipefail

BIN="${HISHELL_QT_BIN:?set HISHELL_QT_BIN to the built hishell-qt binary}"
ROOT="$(mktemp -d /tmp/hishell-ui-test-XXXXXX)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/cache" "$ROOT/config"

set +e
output="$(
	HISHELL_SELF_TEST=1 \
	XDG_CACHE_HOME="$ROOT/cache" \
	XDG_CONFIG_HOME="$ROOT/config" \
	QT_QPA_PLATFORM=offscreen \
	timeout 20 "$BIN" 2>&1
)"
status=$?
set -e
printf '%s\n' "$output"

if [ "$status" -ne 0 ]; then
	echo "ui-test: selftest exited with $status" >&2
	exit 1
fi
if ! printf '%s\n' "$output" | grep -q 'SELFTEST RESULT passes=.* failures=0'; then
	echo "ui-test: selftest reported failures" >&2
	exit 1
fi

echo "ui-test: dialogs, drop, panes, transition, and gamepad ok"
