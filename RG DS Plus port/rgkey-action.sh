#!/bin/bash
# Actions for rgkeyd, the global hotkey daemon on the Anbernic RG DS Plus.
#
# The stock launcher (dmenu.bin) handles the volume, power and back keys itself
# while its menu is on screen, so every action here is skipped then; the daemon
# only takes over while another app is foregrounded.

menu_running() {
	local c
	for c in dmenu.bin muos2.bin muos3.bin vp.dge charg.dge; do
		pgrep -x "$c" >/dev/null 2>&1 && return 0
	done
	return 1
}

kill_tree() {
	local pid="$1" sig="$2" child
	for child in $(pgrep -P "$pid" 2>/dev/null); do
		kill_tree "$child" "$sig"
	done
	kill -"$sig" "$pid" 2>/dev/null
}

# Close the foreground app: everything the launcher started for it lives under
# `sh /tmp/.next`, a child of dmenu_ln. Killing it makes dmenu_ln return and the
# launcher menu come back.
close_app() {
	local ln root
	ln=$(pgrep -x dmenu_ln | head -n1)
	[ -n "$ln" ] || return 0

	root=$(pgrep -P "$ln" | head -n1)
	[ -n "$root" ] || return 0

	case "$(cat "/proc/$root/comm" 2>/dev/null)" in
		dmenu.bin|muos2.bin|muos3.bin|vp.dge|charg.dge) return 0 ;;
	esac

	kill_tree "$root" TERM
	sleep 1
	kill_tree "$root" KILL
}

menu_running && exit 0

case "${1:-}" in
	vol-up)     pactl set-sink-volume @DEFAULT_SINK@ +5% ;;
	vol-down)   pactl set-sink-volume @DEFAULT_SINK@ -5% ;;
	mute)       pactl set-sink-mute @DEFAULT_SINK@ toggle ;;
	power)      /mnt/vendor/ctrl/pwr_new.sh ;;
	lid-close)  /mnt/vendor/ctrl/pwr_new.sh ;;
	back-close) close_app ;;
esac
