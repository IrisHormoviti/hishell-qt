#!/bin/bash
# Collects a self-contained aarch64 deployment bundle for hishell-qt
# from this Debian trixie sysroot. Run inside the chroot.
#
# The binary comes from the host cross-build (scripts/build.sh), staged at
# /build/hishell/target/aarch64-unknown-linux-gnu/<profile>/hishell-qt; falls
# back to the in-chroot path for the slow build.
set -eo pipefail

PROFILE="${1:-debug}"
BUNDLE=/build/bundle
QT=/usr/lib/aarch64-linux-gnu/qt6
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/lib" "$BUNDLE/qtplugins" "$BUNDLE/qml" "$BUNDLE/share/icons" "$BUNDLE/config"

# --- main binary ---
BIN=/build/hishell/target/aarch64-unknown-linux-gnu/$PROFILE/hishell-qt
[ -f "$BIN" ] || BIN=/build/hishell/target/$PROFILE/hishell-qt
cp "$BIN" "$BUNDLE/"

# --- app config (default.cfg is read relative to the working directory) ---
cp /build/hishell/config/default.cfg "$BUNDLE/config/default.cfg"

# --- Qt plugins ---
mkdir -p "$BUNDLE/qtplugins/platforms" "$BUNDLE/qtplugins/imageformats" \
         "$BUNDLE/qtplugins/iconengines" "$BUNDLE/qtplugins/wayland-shell-integration" \
         "$BUNDLE/qtplugins/tls" "$BUNDLE/qtplugins/networkinformation"
cp "$QT/plugins/platforms/libqwayland-egl.so"   "$BUNDLE/qtplugins/platforms/"
cp "$QT/plugins/platforms/libqwayland-generic.so" "$BUNDLE/qtplugins/platforms/"
cp "$QT/plugins/platforms/libqoffscreen.so"     "$BUNDLE/qtplugins/platforms/"
cp "$QT/plugins/platforms/libqminimal.so"       "$BUNDLE/qtplugins/platforms/"
cp "$QT/plugins/imageformats/"*.so              "$BUNDLE/qtplugins/imageformats/"
cp "$QT/plugins/iconengines/"*.so               "$BUNDLE/qtplugins/iconengines/"
cp "$QT/plugins/wayland-shell-integration/libxdg-shell.so" \
   "$QT/plugins/wayland-shell-integration/libfullscreen-shell-v1.so" \
   "$QT/plugins/wayland-shell-integration/libwl-shell-plugin.so" \
   "$QT/plugins/wayland-shell-integration/libqt-shell.so" \
   "$BUNDLE/qtplugins/wayland-shell-integration/"
cp "$QT/plugins/tls/"*.so                       "$BUNDLE/qtplugins/tls/"
cp "$QT/plugins/networkinformation/"*.so        "$BUNDLE/qtplugins/networkinformation/"

# --- QML modules ---
cp -r "$QT/qml/QtQuick" "$BUNDLE/qml/"
cp -r "$QT/qml/QtQml"   "$BUNDLE/qml/"
cp -r "$QT/qml/org"     "$BUNDLE/qml/"
[ -d "$QT/qml/Qt" ] && cp -r "$QT/qml/Qt" "$BUNDLE/qml/"

# --- icon theme (Qt resolves "breeze" via QT_QPA_SYSTEM_ICON_THEME) ---
cp -r /usr/share/icons/breeze "$BUNDLE/share/icons/"

# --- shared library closure ---
# System libraries that stay on the device: glibc family, the Mali/DRM GPU
# stack and the Wayland core libs (same 1.23.1 version on the target).
EXCLUDE='^(ld-linux-aarch64\.so\.1|libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|libresolv\.so\.2|libnsl\.so\.1|libutil\.so\.1|libEGL\.so\.1|libGLESv2\.so\.2|libGLESv1_CM\.so\.1|libmali.*|libdrm\.so\.2|libgbm\.so\.1|libvulkan.*|libwayland-client\.so\.0|libwayland-egl\.so\.1|libwayland-server\.so\.0|libwayland-cursor\.so\.0)$'

declare -A SEEN
add_lib() {
	local so="$1" base
	base=$(basename "$so")
	[[ "$base" =~ $EXCLUDE ]] && return 0
	[[ -n "${SEEN[$base]:-}" ]] && return 0
	SEEN[$base]=1
	cp -L "$so" "$BUNDLE/lib/$base"
	echo "  + $base"
}

# repeat passes until no new dependencies appear
# (process substitution is avoided: /dev/fd may be missing in a minimal chroot)
while :; do
	before=${#SEEN[@]}
	find "$BUNDLE" -type f \( -name "*.so*" -o -name "hishell-qt" \) > /tmp/.bundle-files
	while read -r f; do
		ldd "$f" 2>/dev/null | awk '/=>/ && $3 != "" {print $3}' > /tmp/.bundle-deps
		while read -r dep; do
			[ -n "$dep" ] && [ -f "$dep" ] && add_lib "$dep"
		done < /tmp/.bundle-deps
	done < /tmp/.bundle-files
	after=${#SEEN[@]}
	[ "$before" = "$after" ] && break
done

echo "== bundle summary =="
du -sh "$BUNDLE"
echo "libs: $(ls "$BUNDLE/lib" | wc -l)"
echo "files: $(find "$BUNDLE" -type f | wc -l)"
