#!/bin/bash
# Anbernic RG DS Plus (stock Buildroot OS) launcher for Hishell Qt.
#
# This is the file the stock dmenu launcher executes when the "Hishell" icon is
# tapped; it is auto-generated from the per-language names in
# /mnt/mod/ctrl/configs/apps.tsv (see /mnt/mod/ctrl/sw). It lives in
# /mnt/mmc/Roms/APPS/ Hishell.sh.
#
# The bundle itself sits on the rootfs at /opt/hishell.

export HOME=/

# The bundle lives on the rootfs (/opt) rather than the vendor partition, which
# is only ~1 GB and nearly full on this device.
HISHELL_DIR=/opt/hishell

# The app reads its global config from $HOME/.config/hishell/folder.cfg and its
# built-in defaults from ./config/default.cfg relative to the bundle root.
# HOME is / here (same as wiliwili's launcher), so install the device config on
# first run instead of relying on a manual copy.
CFG_DIR="/.config/hishell"
mkdir -p "$CFG_DIR"
if [ ! -f "$CFG_DIR/folder.cfg" ] && [ -f "$HISHELL_DIR/config/folder.cfg" ]; then
	cp "$HISHELL_DIR/config/folder.cfg" "$CFG_DIR/folder.cfg"
fi

# The RG DS Plus has two panels. Hishell opens on the bottom (touch) screen.
# weston exposes them as separate Wayland outputs; the app is pinned there by
# the compositor's output layout. See README-device.md for the pinning options.

# Touch panel control: /sys/class/anbernic_misc/tpctrl is an ENABLE flag for the
# gt9xx controller. The stock OS leaves it at 0 (enabled); writing 1 turns the
# panel OFF, which is why touch used to be dead. Do not write to it here.

cd "$HISHELL_DIR" || exit 1

# Keep a log next to the bundle for debugging.
exec "$HISHELL_DIR/run.sh" "${1:-/userdata}" > "$HISHELL_DIR/hishell.log" 2>&1
