#!/bin/bash
# Launch script for Hishell Qt on the Anbernic RG DS Plus (stock Buildroot OS).
#
# The bundle is self-contained: it ships its own Qt 6.8, Kirigami 6 and the
# libstdc++ those libraries were built against. Only the GPU/Wayland core
# libraries are taken from the system.
#
# DEBUGGING: this script logs everything it can to <bundle>/hishell.log and
# also mirrors it on the screen via weston's debug log. Set HISHELL_DEBUG=1 in
# the environment (or edit DEBUG below) to add Qt plugin/QML tracing.

HERE="$(cd "$(dirname "$0")" || exit; pwd)"
LOG="$HERE/hishell.log"
DEBUG="${HISHELL_DEBUG:-0}"

# Log to both the file and the device console so it survives a crash.
exec > >(tee -a "$LOG" /dev/console) 2>&1
echo "========================================================="
echo "hishell: launch at $(date)  HERE=$HERE  DEBUG=$DEBUG"
echo "hishell: uname: $(uname -a)"
echo "hishell: pwd: $(pwd)"

# --- environment snapshot -------------------------------------------------
echo "hishell: WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-}(unset)"
echo "hishell: XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-}(unset)"
for d in /var/run /run /tmp; do
	echo "hishell: ls $d: $(ls -la "$d" 2>/dev/null | grep -iE 'wayland|\.lock' | tr '\n' ' ')"
done

# Bundled libraries first, so the shipped libstdc++/Qt win over the older
# system versions.
export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-/usr/lib:/lib}"

export QT_PLUGIN_PATH="$HERE/qtplugins"
export QML2_IMPORT_PATH="$HERE/qml"
export QT_QPA_PLATFORM=wayland
export QT_QPA_SYSTEM_ICON_THEME=breeze
export XDG_DATA_DIRS="$HERE/share:${XDG_DATA_DIRS:-/usr/share}"

# The panels are 1024x768, which makes the stock sizes too small to hit reliably
# with a finger. Scale the whole UI up; tune with HISHELL_SCALE (1.25, 1.5, 2...).
export QT_SCALE_FACTOR="${HISHELL_SCALE:-1.5}"

# Weston environment used by the stock OS (see /etc/profile.d/myenv.sh).
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/var/run}"

# Place the window on the bottom (touch) panel. weston puts new toplevels at the
# virtual-desktop origin, which is the top panel (DSI-1) by default. Moving the
# outputs so the bottom panel (DSI-2) sits at the origin makes the window open
# there; the top panel keeps its own area at x=1024. The touch controller is also
# associated with DSI-1 by default, so it has to be pointed at DSI-2 as well.
# This is weston's dynamic output config (WESTON_DRM_CONFIG), which the stock
# compositor watches.
DRM_CONF="${WESTON_DRM_CONFIG:-/tmp/.weston_drm.conf}"
ORIG_DRM_CONF=""

place_on_bottom_screen() {
	[ -d "$(dirname "$DRM_CONF")" ] || return 0
	# Remember the stock layout so it can be put back when the app exits;
	# leaving the outputs swapped confuses the stock menu.
	ORIG_DRM_CONF="$(cat "$DRM_CONF" 2>/dev/null)"
	{
		echo 'output:DSI-2:pos=0,0'
		echo 'output:DSI-1:pos=1024,0'
		echo 'output:DSI-2:input=gt9xx*'
	} > "$DRM_CONF" 2>/dev/null || true
	# Give the compositor a moment to apply the new layout before we map.
	sleep 1
}

restore_screen_layout() {
	[ -d "$(dirname "$DRM_CONF")" ] || return 0
	printf '%s' "$ORIG_DRM_CONF" > "$DRM_CONF" 2>/dev/null || true
}
trap restore_screen_layout EXIT

# Only rearrange when both panels are present; otherwise leave the layout alone.
if [ -e /sys/class/drm/card0-DSI-1 ] && [ -e /sys/class/drm/card0-DSI-2 ]; then
	place_on_bottom_screen
fi

# The stock menu turns the touch panel OFF while handing over to the app (the
# tpctrl flag flips to 1 just before the app starts), so turn it back on.
# tpctrl is an enable flag: 0 = panel on, 1 = panel off.
if [ -e /sys/class/anbernic_misc/tpctrl ]; then
	echo 0 > /sys/class/anbernic_misc/tpctrl 2>/dev/null || true
fi

# Qt Quick uses the Mali GPU through the wayland-egl client buffer integration
# (qtplugins/wayland-graphics-integration-client). If that ever fails on a
# device, set QT_QUICK_BACKEND=software in the environment to fall back to the
# raster renderer.

# The app reads the global config from $HOME/.config/hishell/folder.cfg. HOME is
# inherited from the launcher (usually /).
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME:-/}/.config}"

if [ "$DEBUG" = "1" ]; then
	export QT_DEBUG_PLUGINS=1
	export QT_LOGGING_RULES="qt.qml.binding.removal.info=true;qt.qml.typeresolution=true;qt.gui.icon.loader=true;qt.qpa.*=true"
fi

# --- verify the shipped binary really runs here ---------------------------
echo "hishell: ldd check (what the loader will pick):"
ldd "$HERE/hishell-qt" 2>&1 | sed 's/^/hishell:   /' | grep -iE "not found|libstdc|libQt6Core|libEGL|libwayland" || true

# --- pick a usable Wayland socket -----------------------------------------
sock_ok() { [ -n "$1" ] && [ -n "$2" ] && [ -S "$1/$2" ]; }

found=""
for rt in "$XDG_RUNTIME_DIR" /var/run /run /tmp; do
	for name in "$WAYLAND_DISPLAY" wayland-0 wayland-1; do
		if sock_ok "$rt" "$name"; then
			export XDG_RUNTIME_DIR="$rt"
			export WAYLAND_DISPLAY="$name"
			found="yes"
			break 2
		fi
	done
done

if [ -n "$found" ]; then
	echo "hishell: using WAYLAND_DISPLAY=$WAYLAND_DISPLAY XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
else
	echo "hishell: WARNING no wayland socket found, falling back to platform=offscreen"
	echo "hishell: (search output above; sockets may live elsewhere on this OS)"
	export QT_QPA_PLATFORM=offscreen
fi

cd "$HERE" || exit 1
echo "hishell: exec ./hishell-qt ${1:-/userdata}"
./hishell-qt "${1:-/userdata}"
rc=$?
echo "hishell: app exited with status $rc"
exit $rc
