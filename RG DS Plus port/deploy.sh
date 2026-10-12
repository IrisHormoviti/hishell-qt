#!/bin/bash
# Copy the freshly built aarch64 binary to an RG DS Plus over SSH.
#
# Usage:  ./deploy.sh [device]        (default root@192.168.31.28)
# Env:    HISHELL_DEVICE  same as the argument
#         HISHELL_PROFILE  debug|release  (default debug)
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." || exit; pwd)"
DEVICE="${1:-${HISHELL_DEVICE:-root@192.168.31.28}}"
PROFILE="${HISHELL_PROFILE:-debug}"
BIN="$REPO/target/aarch64-unknown-linux-gnu/$PROFILE/hishell-qt"
REMOTE="${HISHELL_REMOTE_BUNDLE:-/opt/hishell}"

[ -f "$BIN" ] || { echo "not built: $BIN (run scripts/build.sh)" >&2; exit 1; }

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
	"$BIN" "$DEVICE:$REMOTE/hishell-qt.new"
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$DEVICE" \
	"mv $REMOTE/hishell-qt.new $REMOTE/hishell-qt && chmod +x $REMOTE/hishell-qt && echo deployed $(stat -c%s $REMOTE/hishell-qt) bytes"
