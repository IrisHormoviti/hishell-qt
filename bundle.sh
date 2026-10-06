#!/usr/bin/env bash
set -e

# Bundle script for HiShell Qt
# Creates portable folder releases for x86_64 and aarch64 architectures

TARGET_ARCH="${1:-x86_64}"

case "$TARGET_ARCH" in
	x86_64|amd64)
		RUST_TARGET="x86_64-unknown-linux-gnu"
		ARCH_NAME="x86_64"
		;;
	aarch64|arm64)
		RUST_TARGET="aarch64-unknown-linux-gnu"
		ARCH_NAME="aarch64"
		;;
	*)
		echo "Usage: $0 [x86_64|aarch64]"
		exit 1
		;;
esac

# Auto-detect Qt paths using qmake6 or pkg-config, fall back to common locations
detect_qt_path() {
	local var="$1"
	local qmake_key="$2"
	local fallbacks=("${@:3}")
	local result
	result=$(qmake6 -query "$qmake_key" 2>/dev/null) && [ -d "$result" ] && { echo "$result"; return; }
	result=$(qmake -query "$qmake_key" 2>/dev/null) && [ -d "$result" ] && { echo "$result"; return; }
	for fb in "${fallbacks[@]}"; do
		[ -d "$fb" ] && { echo "$fb"; return; }
	done
	echo ""
}

QT_PLUGIN_DIR=$(detect_qt_path _ QT_INSTALL_PLUGINS \
	/usr/lib/qt6/plugins \
	/usr/lib/x86_64-linux-gnu/qt6/plugins \
	/usr/lib/aarch64-linux-gnu/qt6/plugins)

QML_DIR=$(detect_qt_path _ QT_INSTALL_QML \
	/usr/lib/qt6/qml \
	/usr/lib/x86_64-linux-gnu/qt6/qml \
	/usr/lib/aarch64-linux-gnu/qt6/qml)

echo "Qt plugins: ${QT_PLUGIN_DIR:-not found}"
echo "Qt QML:     ${QML_DIR:-not found}"

DIST_DIR="dist/hishell-qt-${ARCH_NAME}"

echo "=================================================="
echo " Building HiShell Qt Bundle ($ARCH_NAME)"
echo " Output directory: $DIST_DIR"
echo "=================================================="

TARGET_DIR="${CARGO_TARGET_DIR:-target/user_build}"

# 1. Build release binary with Cargo
if [ "$RUST_TARGET" = "aarch64-unknown-linux-gnu" ]; then
	export CXXFLAGS_aarch64_unknown_linux_gnu="-I/usr/include"
fi
cargo build --release --target "$RUST_TARGET" --target-dir "$TARGET_DIR"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/lib" "$DIST_DIR/qtplugins" "$DIST_DIR/qml"

cp "$TARGET_DIR/$RUST_TARGET/release/hishell-qt" "$DIST_DIR/"

# KService helper, used to rebuild the service database on systems without Plasma
if [ -x /usr/bin/kbuildsycoca6 ]; then
	cp /usr/bin/kbuildsycoca6 "$DIST_DIR/"
fi

# 2. Copy shared library dependencies using ldd (resolves full paths regardless of multiarch layout)
echo "Collecting dynamic dependencies for $ARCH_NAME..."

copy_deps() {
	local bin="$1"
	[ -f "$bin" ] || return
	ldd "$bin" 2>/dev/null | grep "=>" | awk '{print $3}' | while read -r lib_path; do
		[ -f "$lib_path" ] || continue
		local lib_name
		lib_name=$(basename "$lib_path")
		# Skip system libs that must stay on the host
		case "$lib_name" in
			libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|ld-linux*|\
			libgcc_s.so*|libGL.so*|libEGL.so*|libGLX.so*|libOpenGL.so*|\
			libGLdispatch.so*|libdrm.so*|libgbm.so*)
				continue ;;
		esac
		[ -f "$DIST_DIR/lib/$lib_name" ] && continue
		cp -L "$lib_path" "$DIST_DIR/lib/$lib_name"
	done
}

copy_deps "$DIST_DIR/hishell-qt"
[ -f "$DIST_DIR/kbuildsycoca6" ] && copy_deps "$DIST_DIR/kbuildsycoca6"

# 3. Copy Qt plugins
if [ -n "$QT_PLUGIN_DIR" ]; then
	echo "Copying Qt plugins from $QT_PLUGIN_DIR..."
	cp -rL "$QT_PLUGIN_DIR"/* "$DIST_DIR/qtplugins/" 2>/dev/null || true
else
	echo "WARNING: Qt plugin directory not found, skipping"
fi

# 4. Copy QML imports
if [ -n "$QML_DIR" ]; then
	echo "Copying QML imports from $QML_DIR..."
	mkdir -p "$DIST_DIR/qml/org"
	[ -d "$QML_DIR/org/kde" ]  && cp -rL "$QML_DIR/org/kde"  "$DIST_DIR/qml/org/" 2>/dev/null || true
	[ -d "$QML_DIR/QtQuick" ]  && cp -rL "$QML_DIR/QtQuick"  "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_DIR/QtQml" ]    && cp -rL "$QML_DIR/QtQml"    "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_DIR/Qt" ]       && cp -rL "$QML_DIR/Qt"       "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_DIR/QtCore" ]   && cp -rL "$QML_DIR/QtCore"   "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_DIR/QtGui" ]    && cp -rL "$QML_DIR/QtGui"    "$DIST_DIR/qml/" 2>/dev/null || true
else
	echo "WARNING: QML directory not found, skipping"
fi

# 5. Collect libs needed by plugins/QML modules
for plugin in $(find "$DIST_DIR/qtplugins" "$DIST_DIR/qml" -name "*.so" 2>/dev/null); do
	copy_deps "$plugin"
done

# 6. Create launcher script
cat << 'EOF' > "$DIST_DIR/run.sh"
#!/usr/bin/env bash
HERE="$(dirname "$(realpath "$0")")"

export LD_LIBRARY_PATH="$HERE/lib:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$HERE/qtplugins"
export QML2_IMPORT_PATH="$HERE/qml"
export PATH="$HERE:$PATH"

exec "$HERE/hishell-qt" "$@"
EOF

chmod +x "$DIST_DIR/run.sh" "$DIST_DIR/hishell-qt"

echo "=================================================="
echo "Bundle contents:"
du -sh "$DIST_DIR"/lib "$DIST_DIR"/qtplugins "$DIST_DIR"/qml 2>/dev/null || true
echo "Success! Bundle created at: $DIST_DIR"
echo "Run using: $DIST_DIR/run.sh"
