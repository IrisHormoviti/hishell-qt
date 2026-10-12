#!/bin/bash
# Diagnostic for Hishell Qt on the Anbernic RG DS Plus.
#
# Run this from the stock OS (over SSH, or by pointing Hishell.sh at it) and it
# writes a report to <bundle>/hishell-report.txt describing exactly why the app
# does or does not come up. Nothing here changes the system.

HERE="$(cd "$(dirname "$0")" || exit; pwd)"
REPORT="$HERE/hishell-report.txt"

{
	echo "hishell diagnostic $(date)"
	echo "========================================================="
	echo "uname: $(uname -a)"
	echo "board: $(head -n1 /mnt/vendor/oem/board.ini 2>/dev/null)"
	echo "os:    $(head -n1 /etc/os-release 2>/dev/null)"
	echo
	echo "--- weston ---"
	pgrep -a weston
	for d in /var/run /run /tmp; do
		echo "sockets in $d: $(ls -la "$d" 2>/dev/null | grep -i wayland | tr '\n' ' ')"
	done
	echo "WESTON_DRM_CONFIG=${WESTON_DRM_CONFIG:-unset}"
	echo
	echo "--- weston log (tail) ---"
	tail -n 40 /var/log/weston.log 2>/dev/null || echo "(no /var/log/weston.log)"
	echo
	echo "--- DRM outputs / connectors ---"
	for c in /sys/class/drm/*/status; do
		[ -e "$c" ] || continue
		echo "$(dirname "$c"): $(cat "$c") $(cat "$(dirname "$c")/modes" 2>/dev/null | head -1)"
	done
	echo
	echo "--- dynamic drm config ---"
	cat /tmp/.weston_drm.conf 2>/dev/null || echo "(none)"
	echo
	echo "--- GPU / EGL ---"
	ls -la /usr/lib/libEGL.so.1 /usr/lib/libGLESv2.so.2 /usr/lib/libmali.so.1 2>/dev/null
	echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-unset}"
	echo
	echo "--- bundled app loader resolution ---"
	LD_LIBRARY_PATH="$HERE/lib" ldd "$HERE/hishell-qt" 2>&1 | grep -iE "not found|libstdc|libQt6Core|libKF6Service|libEGL|libwayland"
	echo
	echo "--- direct run: WAYLAND + QPA tracing (5s) ---"
	export XDG_DATA_DIRS="$HERE/share:/usr/share"
	export QT_PLUGIN_PATH="$HERE/qtplugins"
	export QML2_IMPORT_PATH="$HERE/qml"
	export QT_QPA_SYSTEM_ICON_THEME=breeze
	export QT_LOGGING_RULES="qt.qpa.*=true;qt.gui.icon.loader=true"
	export QT_QPA_PLATFORM=wayland
	export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"
	export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
	timeout 5 "$HERE/hishell-qt" /userdata 2>&1 | head -n 120
	echo "exit: $?"
	echo
	echo "--- direct run on offscreen backend (isolates compositor/EGL) ---"
	QT_QPA_PLATFORM=offscreen timeout 5 "$HERE/hishell-qt" /userdata 2>&1 | head -n 60
	echo "exit: $?"
} > "$REPORT" 2>&1

echo "report written to $REPORT"
