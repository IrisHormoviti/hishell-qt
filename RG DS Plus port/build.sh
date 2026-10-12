#!/bin/bash
# Build hishell-qt for the Anbernic RG DS Plus (aarch64) on an Arch/x86_64 host,
# without QEMU: the host's Rust toolchain cross-compiles to
# aarch64-unknown-linux-gnu, and only Qt/KF6 headers, pkg-config files and the
# moc come from a Debian trixie aarch64 sysroot.
#
# Why this exists: building *inside* the sysroot under qemu-user takes ~50 min
# and rebuilds every dependency each time. This path is ~1.5 min cold and
# seconds incremental.
#
# Usage:
#   ./build.sh [--debug|--release]     (default: --debug)
#
# Environment (all optional):
#   HISHELL_SYSROOT   path to the aarch64 sysroot (default /tmp/opencode/rgds/trixie-aarch64)
#   HISHELL_SKIP_SETUP=1   don't create the sysroot/links, just build
set -euo pipefail

PROFILE="debug"
PROFILE_FLAG=""
for arg in "$@"; do
	case "$arg" in
		--debug) PROFILE="debug"; PROFILE_FLAG="" ;;
		--release) PROFILE="release"; PROFILE_FLAG="--release" ;;
		*) echo "unknown option: $arg" >&2; exit 2 ;;
	esac
done

REPO="$(cd "$(dirname "$0")/.." || exit; pwd)"
SYSROOT="${HISHELL_SYSROOT:-/tmp/opencode/rgds/trixie-aarch64}"
TARGET=aarch64-unknown-linux-gnu

# ── Preconditions ───────────────────────────────────────────────────────────
need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 1; }; }
need cargo
need aarch64-linux-gnu-g++
need aarch64-linux-gnu-gcc
need qemu-aarch64-static

if [ ! -d "$SYSROOT/usr/lib/aarch64-linux-gnu" ]; then
	echo "sysroot not found at $SYSROOT" >&2
	echo "run scripts/setup-sysroot.sh first (or set HISHELL_SYSROOT)" >&2
	exit 1
fi

rustup target list --installed | grep -qx "$TARGET" || rustup target add "$TARGET"

# ── glibc absolute-path workaround ──────────────────────────────────────────
# Debian's libm.so is a linker script using absolute paths
# (/lib/aarch64-linux-gnu/libm.so.6, /lib/ld-linux-aarch64.so.1) that only
# resolve inside a real multiarch rootfs. Recreate them on the host as symlinks
# into the sysroot. Idempotent; needs sudo once.
if [ ! -e /lib/aarch64-linux-gnu ]; then
	echo "one-time: creating /lib/aarch64-linux-gnu symlink farm (needs sudo)"
	sudo mkdir -p /lib/aarch64-linux-gnu
	for f in "$SYSROOT"/lib/aarch64-linux-gnu/*; do
		sudo ln -sf "$f" "/lib/aarch64-linux-gnu/$(basename "$f")"
	done
fi
if [ ! -e /lib/ld-linux-aarch64.so.1 ]; then
	sudo ln -sf "$SYSROOT/lib/ld-linux-aarch64.so.1" /lib/ld-linux-aarch64.so.1
fi

# ── moc wrapper (the sysroot's Qt 6.8 moc, run under qemu; ~1 s) ────────────
MOC_WRAPPER="${TMPDIR:-/tmp}/hishell-moc-aarch64.sh"
cat > "$MOC_WRAPPER" <<EOF
#!/bin/bash
exec qemu-aarch64-static -L "$SYSROOT" "$SYSROOT/usr/lib/qt6/libexec/moc" "\$@"
EOF
chmod +x "$MOC_WRAPPER"

# ── Cross environment ───────────────────────────────────────────────────────
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-g++
export CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc
export CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++
export AR_aarch64_unknown_linux_gnu=aarch64-linux-gnu-ar
export PKG_CONFIG_ALLOW_CROSS=1
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/lib/aarch64-linux-gnu/pkgconfig:$SYSROOT/usr/share/pkgconfig"
export QT_INCLUDE_PATH="$SYSROOT/usr/include/aarch64-linux-gnu/qt6"
export QT_LIBRARY_PATH="$SYSROOT/usr/lib/aarch64-linux-gnu"
export CPLUS_INCLUDE_PATH="$SYSROOT/usr/include/aarch64-linux-gnu:$SYSROOT/usr/include"
export LIBRARY_PATH="$SYSROOT/usr/lib/aarch64-linux-gnu:$SYSROOT/lib/aarch64-linux-gnu"
export KF6_INCLUDE_PATH="$SYSROOT/usr/include/KF6"
export MOC="$MOC_WRAPPER"
# Resolve the transitive deps of the Qt/KF6 .so files, and the proxy backend.
export RUSTFLAGS="-L native=$SYSROOT/usr/lib/aarch64-linux-gnu -L native=$SYSROOT/lib/aarch64-linux-gnu -C link-arg=-Wl,-rpath-link=$SYSROOT/usr/lib/aarch64-linux-gnu -C link-arg=-Wl,-rpath-link=$SYSROOT/lib/aarch64-linux-gnu -C link-arg=-Wl,-rpath-link=$SYSROOT/usr/lib/aarch64-linux-gnu/libproxy"

echo "building hishell-qt ($PROFILE) for $TARGET"
cd "$REPO"
cargo build --target "$TARGET" $PROFILE_FLAG

BIN="$REPO/target/$TARGET/$PROFILE/hishell-qt"
echo
echo "built: $BIN"
file "$BIN"
echo
echo "deploy (example):"
echo "  scp '$BIN' root@<device>:/opt/hishell/hishell-qt"
