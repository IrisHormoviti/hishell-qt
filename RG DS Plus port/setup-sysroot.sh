#!/bin/bash
# Create the Debian trixie aarch64 sysroot used to cross-build hishell-qt for
# the Anbernic RG DS Plus, then install the Qt6 / KF6 / Rust toolchain inside it.
#
# Only Qt/KF6 headers, pkg-config files, the moc and the target libraries come
# from this sysroot — the Rust compilation itself runs natively on the host (see
# build.sh). One-off; takes a few minutes and ~2 GB.
#
# Usage:  sudo is used as needed; run as your normal user.
#         ./setup-sysroot.sh [dest]     (default /tmp/opencode/rgds/trixie-aarch64)
set -euo pipefail

DEST="${1:-/tmp/opencode/rgds/trixie-aarch64}"
ROOT="$(dirname "$DEST")"
SUITE=trixie
MIRROR=http://deb.debian.org/debian

command -v debootstrap >/dev/null || { echo "install debootstrap" >&2; exit 1; }
command -v qemu-aarch64-static >/dev/null || { echo "install qemu-user-static (binfmt)" >&2; exit 1; }

mkdir -p "$ROOT"
cd "$ROOT"

if [ ! -d "$DEST" ]; then
	sudo debootstrap --arch=arm64 --foreign --variant=minbase "$SUITE" "$DEST" "$MIRROR"
fi

sudo cp /usr/bin/qemu-aarch64-static "$DEST/usr/bin/" 2>/dev/null || true
mountpoint -q "$DEST/proc" || sudo mount -t proc proc "$DEST/proc"
mountpoint -q "$DEST/sys" || sudo mount --bind /sys "$DEST/sys"
mountpoint -q "$DEST/dev" || sudo mount --bind /dev "$DEST/dev"
mountpoint -q "$DEST/dev/pts" || sudo mount --bind /dev/pts "$DEST/dev/pts"

if [ ! -f "$DEST/debootstrap/debootstrap.log" ] \
	|| ! grep -q "base system installed" "$DEST/debootstrap/debootstrap.log" 2>/dev/null; then
	sudo chroot "$DEST" /debootstrap/debootstrap --second-stage
fi

echo "nameserver 1.1.1.1" | sudo tee "$DEST/etc/resolv.conf" >/dev/null
printf 'deb %s %s main\ndeb %s %s-updates main\ndeb %s %s-security main\n' \
	"$MIRROR" "$SUITE" "$MIRROR" "$SUITE" "$MIRROR" "$SUITE" | sudo tee "$DEST/etc/apt/sources.list" >/dev/null

sudo chroot "$DEST" /bin/sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get update'
sudo chroot "$DEST" /bin/sh -c 'export DEBIAN_FRONTEND=noninteractive; apt-get install -y --no-install-recommends \
	build-essential pkg-config cmake git curl ca-certificates file \
	qt6-base-dev qt6-declarative-dev qt6-tools-dev qt6-wayland-dev \
	qt6-wayland qml6-module-qtwayland-compositor \
	qml6-module-qtquick qml6-module-qtquick-controls \
	qml6-module-qtquick-layouts qml6-module-qtquick-dialogs \
	qml6-module-qtqml-workerscript qml6-module-qtquick-templates \
	qml6-module-qtquick-window qml6-module-qtquick-shapes \
	libkf6service-dev libkf6kio-dev libkf6coreaddons-dev libkf6guiaddons-dev \
	qml6-module-org-kde-kirigami kirigami2-dev \
	qt6-svg-dev qt6-svg-plugins libqt6svg6 kf6-breeze-icon-theme'

sudo chroot "$DEST" /bin/sh -c 'export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo \
	RUSTUP_INIT_SKIP_PATH_CHECK=yes; curl -sSf https://sh.rustup.rs -o /tmp/rustup.sh; \
	sh /tmp/rustup.sh -y --no-modify-path --default-toolchain 1.99.0 --profile minimal'

echo
echo "sysroot ready: $DEST"
echo "now run:  HISHELL_SYSROOT=$DEST scripts/build.sh"
