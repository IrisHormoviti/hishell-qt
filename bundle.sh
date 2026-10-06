#!/usr/bin/env bash
set -e

# Bundle script for HiShell Qt
# Creates portable folder releases for x86_64 and aarch64 architectures

TARGET_ARCH="${1:-x86_64}"

case "$TARGET_ARCH" in
	x86_64|amd64)
		RUST_TARGET="x86_64-unknown-linux-gnu"
		ARCH_NAME="x86_64"
		LIB_SEARCH_PREFIX="/usr/lib"
		QT_PLUGIN_SEARCH_PREFIX="/usr/lib/qt6/plugins"
		QML_SEARCH_PREFIX="/usr/lib/qt6/qml"
		;;
	aarch64|arm64)
		RUST_TARGET="aarch64-unknown-linux-gnu"
		ARCH_NAME="aarch64"
		LIB_SEARCH_PREFIX="${SYSROOT_AARCH64:-/usr/aarch64-linux-gnu}/lib"
		QT_PLUGIN_SEARCH_PREFIX="${SYSROOT_AARCH64:-/usr/aarch64-linux-gnu}/lib/qt6/plugins"
		QML_SEARCH_PREFIX="${SYSROOT_AARCH64:-/usr/aarch64-linux-gnu}/lib/qt6/qml"
		;;
	*)
		echo "Usage: $0 [x86_64|aarch64]"
		exit 1
		;;
esac

DIST_DIR="dist/hishell-qt-${ARCH_NAME}"

echo "=================================================="
echo " Building HiShell Qt Bundle ($ARCH_NAME)"
echo " Output directory: $DIST_DIR"
echo "=================================================="

TARGET_DIR="${CARGO_TARGET_DIR:-target/user_build}"

# 1. Build release binary with Cargo
# For aarch64 cross-compilation: the cc crate looks for CXXFLAGS_aarch64_unknown_linux_gnu
# to find system headers (GL/gl.h) not in the cross-compiler's default sysroot.
if [ "$RUST_TARGET" = "aarch64-unknown-linux-gnu" ]; then
	export CXXFLAGS_aarch64_unknown_linux_gnu="-I/usr/include"
fi
cargo build --release --target "$RUST_TARGET" --target-dir "$TARGET_DIR"

mkdir -p "$DIST_DIR/lib" "$DIST_DIR/qtplugins" "$DIST_DIR/qml"

# Copy main binary
cp "$TARGET_DIR/$RUST_TARGET/release/hishell-qt" "$DIST_DIR/"

# 2. Copy dependent shared libraries (.so)
echo "Collecting dynamic dependencies for $ARCH_NAME..."

# Helper function to copy dependencies recursively
copy_deps() {
	local bin="$1"
	local search_dir="$2"
	if [ -f "$bin" ]; then
		for lib_path in $(readelf -d "$bin" 2>/dev/null | grep NEEDED | sed -e 's/.*\[//' -e 's/\]//'); do
			# Skip low-level system glibc and graphics driver libs (EGL, GL, DRM, X11 driver libs)
			case "$lib_path" in
				libc.so*|libm.so*|libpthread.so*|libdl.so*|librt.so*|ld-linux*|libgcc_s.so*|libGL.so*|libEGL.so*|libGLX.so*|libOpenGL.so*|libGLdispatch.so*|libdrm.so*|libgbm.so*)
					continue
					;;
			esac
			if [ ! -f "$DIST_DIR/lib/$lib_path" ]; then
				if [ -f "$search_dir/$lib_path" ]; then
					cp -L "$search_dir/$lib_path" "$DIST_DIR/lib/$lib_path" 2>/dev/null || true
				elif [ -f "/usr/lib/$lib_path" ]; then
					cp -L "/usr/lib/$lib_path" "$DIST_DIR/lib/$lib_path" 2>/dev/null || true
				fi
			fi
		done
	fi
}

copy_deps "$DIST_DIR/hishell-qt" "$LIB_SEARCH_PREFIX"

# 3. Copy Qt Plugins (Platforms, Graphics, Wayland, Image formats, etc.)
if [ -d "$QT_PLUGIN_SEARCH_PREFIX" ]; then
	echo "Copying Qt plugins from $QT_PLUGIN_SEARCH_PREFIX..."
	cp -rL "$QT_PLUGIN_SEARCH_PREFIX"/* "$DIST_DIR/qtplugins/" 2>/dev/null || true
fi

# 4. Copy QML imports
if [ -d "$QML_SEARCH_PREFIX" ]; then
	echo "Copying QML imports from $QML_SEARCH_PREFIX..."
	mkdir -p "$DIST_DIR/qml/org"
	[ -d "$QML_SEARCH_PREFIX/org/kde" ] && cp -rL "$QML_SEARCH_PREFIX/org/kde" "$DIST_DIR/qml/org/" 2>/dev/null || true
	[ -d "$QML_SEARCH_PREFIX/QtQuick" ] && cp -rL "$QML_SEARCH_PREFIX/QtQuick" "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_SEARCH_PREFIX/QtQml" ] && cp -rL "$QML_SEARCH_PREFIX/QtQml" "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_SEARCH_PREFIX/Qt" ] && cp -rL "$QML_SEARCH_PREFIX/Qt" "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_SEARCH_PREFIX/QtCore" ] && cp -rL "$QML_SEARCH_PREFIX/QtCore" "$DIST_DIR/qml/" 2>/dev/null || true
	[ -d "$QML_SEARCH_PREFIX/QtGui" ] && cp -rL "$QML_SEARCH_PREFIX/QtGui" "$DIST_DIR/qml/" 2>/dev/null || true
fi

# Also collect dynamic libraries required by the copied plugins
for plugin in $(find "$DIST_DIR/qtplugins" "$DIST_DIR/qml" -name "*.so" 2>/dev/null); do
	copy_deps "$plugin" "$LIB_SEARCH_PREFIX"
done

# 5. Create launcher script
cat << 'EOF' > "$DIST_DIR/run.sh"
#!/usr/bin/env bash
HERE="$(dirname "$(realpath "$0")")"

export LD_LIBRARY_PATH="$HERE/lib:$LD_LIBRARY_PATH"
export QT_PLUGIN_PATH="$HERE/qtplugins"
export QML2_IMPORT_PATH="$HERE/qml"

exec "$HERE/hishell-qt" "$@"
EOF

chmod +x "$DIST_DIR/run.sh" "$DIST_DIR/hishell-qt"

echo "Success! Bundle created at: $DIST_DIR"
echo "Run using: $DIST_DIR/run.sh"
