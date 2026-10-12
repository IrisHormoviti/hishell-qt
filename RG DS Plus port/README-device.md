# Hishell Qt on the Anbernic RG DS Plus (stock "Anbernic Linux" OS)

How the RG DS Plus port was produced, every change made, and the known issues.

## Target

| | |
|---|---|
| Device | Anbernic RG DS Plus, board id `RGdsplus` |
| SoC | Rockchip RK3568, 4× Cortex-A55 @ 2.0 GHz |
| GPU | Mali-G52 (Bifrost), `libmali-bifrost-g52-g24p0-wayland-gbm.so` |
| RAM | 1 GB |
| Displays | 2× 1024×768. **DSI-1 = top panel, DSI-2 = bottom panel (touchscreen)** |
| OS | Buildroot 2024.02, kernel 6.1.141 |
| libc | glibc **2.41** (flat `/lib`, no multiarch dir) |
| libstdc++ | GCC 12 (`libstdc++.so.6.0.32`, max `CXXABI_1.3.14`) |
| Display server | **weston 14** on Wayland (`wayland-0`, `XDG_RUNTIME_DIR=/var/run` → `/run`) |
| Launcher | `/mnt/vendor/bin/dmenu.bin`, entries under `/mnt/mmc/Roms/APPS` |
| Partitions | `vendor`→`/mnt/vendor` (991 MB, ~95% full), `ROMS`→`/mnt/mmc` (**vfat**), `userdata`→`/userdata` (1 GB), rootfs→`/` (4.9 GB, ~3 GB free) |

The stock OS ships **no Qt and no KDE Frameworks at all**. Everything has to be
shipped with the app.

## Result

The app builds, runs and renders on the device with GPU (EGL) rendering. It opens
on the bottom touch panel. See "Known issues" for what is not finished.

## How it was built

A **Debian trixie aarch64 sysroot** was created with `debootstrap` and the app was
built inside it with the real aarch64 Rust toolchain. Trixie provides Qt 6.8.2 +
KF6 6.13 built against glibc 2.36–2.38, so every bundled library needs at most
`GLIBC_2.35` — fine for the target's glibc 2.41.

A native cross-build fails immediately (`libudev-sys` pkg-config, KF6 headers,
`moc`), so the sysroot is required.

Reproduction steps are in the "Build environment" section below.

## Deployment layout

The bundle lives on the **rootfs at `/opt/hishell`** — *not* `/mnt/vendor`,
which is only ~1 GB and nearly full. The rootfs is ext4 (so the icon theme's
symlinks work) and has ~3 GB free.

```
rootfs/opt/hishell/              (= /opt/hishell on device)
├── hishell-qt                   aarch64 binary (release)
├── run.sh                       launcher: env, GPU, screen/touch placement
├── qt.conf                      Qt plugin/QML paths
├── config/                      default.cfg (app defaults) + folder.cfg (device)
├── lib/                         Qt6, KF6, Kirigami + deps (157 libs)
├── qml/                         QtQuick, QtQml, org.kde QML modules
├── qtplugins/                   platforms, imageformats, iconengines,
│                                wayland-shell-integration,
│                                wayland-graphics-integration-client,
│                                wayland-decoration-client, tls, networkinformation
└── share/icons/{breeze,breeze-dark}/   icon theme

ROMS/Roms/APPS/Hishell.sh        menu launcher
ROMS/Roms/APPS/Imgs/Hishell.png  menu icon (240×180)
rootfs/mnt/mod/ctrl/configs/apps.tsv   one added row ("Hishell" × 10 languages)
```

### Bundled vs system libraries

`run.sh` sets `LD_LIBRARY_PATH="$HERE/lib:…"` so bundled libraries win.

**Bundled (required):** `libstdc++`/`libgcc_s` (Debian's GCC 14 build — the Qt
libs import `CXXABI_1.3.15`, the target only has `1.3.14`), all Qt6/KF6/Kirigami,
ICU 76, glib, dbus, systemd, udev, freetype, harfbuzz, fontconfig, png, zlib,
zstd, and their transitive deps.

**Taken from the system (excluded on purpose):** the Mali/DRM stack
(`libEGL`, `libGLESv2`, `libmali*`, `libdrm`, `libgbm`), the Wayland core libs
(same 1.23.1 as the sysroot), and glibc.

## Changes made to the OS dump

1. **`rootfs/opt/hishell/`** — new: the whole bundle (binary, libs, QML, plugins,
   icon theme, launcher, config). Nothing stock was deleted.
2. **`ROMS/Roms/APPS/Hishell.sh`** — new: the menu entry. Follows the stock
   `Clock.sh` / `System_Tools.sh` convention (`/mnt/mmc/Roms/APPS/*.sh` are the
   menu entries). It sets `HOME=/`, installs the global config to
   `/.config/hishell/folder.cfg` on first run, and execs `/opt/hishell/run.sh`.
   (It must **not** write `tpctrl`; see the touch notes below.)
3. **`ROMS/Roms/APPS/Imgs/Hishell.png`** — new: 240×180 RGBA menu icon (from the
   project's `.icon.png`).
4. **`rootfs/mnt/mod/ctrl/configs/apps.tsv`** — edited: one row appended
   (`Hishell` in all 10 language columns) so the language-switching tool
   (`/mnt/mod/ctrl/sw`) keeps the entry consistent. The stock file had **no
   trailing newline**, which had to be fixed first or the row corrupts the last
   entry.

## Source changes (in `~/Projects/hishell-qt`)

These were needed to make the app run on Qt 6.8.2 / weston 14. Each is minimal.

1. **QML cyclic type dependencies** — `ShellWindow.qml` instantiates
   `ActionManager`/`LayoutEngine`, and those files declared
   `property ShellWindow window`, a mutual type dependency. Qt 6.8.2 rejects this
   ("Cyclic dependency detected… Type ShellWindow unavailable") and then never
   creates the window; Qt 6.12 (the dev machine) tolerates it. Changed the typed
   `ShellWindow` properties to `var` in `ActionManager.qml`, `LayoutEngine.qml`,
   `toolkit/MenuBar.qml`, `toolkit/PathBar.qml`, `FolderView.qml`, `FileSlot.qml`.
   Runtime behaviour is unchanged (QML property access is dynamic anyway).
2. **Undefined attached object `ContextMenu`** — `FileSlot.qml` and
   `FolderView.qml` used `ContextMenu.menu:` / `ContextMenu.onRequested:`, but no
   `ContextMenu` type exists anywhere in the project. Qt 6.8.2 fails with
   "Non-existent attached object" and marks `FileSlot` unavailable (which breaks
   `FolderView` and `PathBar`). Replaced with plain properties (`contextMenu`,
   `directoryMenu`) and moved the handler logic into `openContextMenu()`.
3. **`Maximized` config implemented** — the key existed in `default.cfg` but was
   never read. Added it to `Config` (`src/config.rs`) and the window opens
   fullscreen when set, so it covers the stock launcher.
4. **`Screen` config added** — a `[Layout] Screen` key names the output to open
   on. (weston ignores a client-chosen output on this device, so the actual
   placement is done by `run.sh`; the option is kept as it is harmless and helps
   on compositors that do honour it.)
5. **Window shown after screen selection** — `ShellWindow.qml` now starts hidden
   and becomes visible in `Component.onCompleted` after the config is loaded.
6. **`ShellContextMenu.qml` null-safety** — `actionManager.group("new")` can
   return `null`; the Instantiator model now filters it, removing
   "Unable to assign [undefined] to objectName" warnings.
7. **Focus stall fixed (`src/kde_bridge.cpp`)** — see "Focus stall" below.
   `hishell_default_app()` / `hishell_open_with_apps()` return immediately when
   the MIME type is empty (what this OS returns for binary files, since it ships
   no shared-mime-info database) instead of calling `KApplicationTrader`, and
   the trader results are cached by MIME name. `src/kde_bridge.rs` clears the
   cache when the default app changes.

## Device configuration

`/opt/hishell/config/folder.cfg` (installed to `/.config/hishell/folder.cfg`,
which is where the app reads its global config because `HOME=/`):

| Key | Value | Why |
|---|---|---|
| `Maximized` | `true` | open fullscreen, covering the launcher |
| `NativeTitleBar` | `false` | weston has no server-side decorations; the in-window header carries the controls |
| `GridSize` | `96` | touch-friendly hit targets |
| `Sort` | `ALPHABETICAL` | predictable on a file card |
| `NavigationType` | `IN_PLACE` | one window |
| `Screen` | `"DSI-2"` | the bottom touch panel |

## Screen and touch placement (weston)

Weston places new toplevels at the **virtual-desktop origin**, which is the first
output — the *top* panel (DSI-1). Qt/weston ignore a client's requested output.
It also associates the touch controller (`gt9xx-0`) with **DSI-1** by default,
which is the wrong panel.

`run.sh` fixes both through weston's dynamic output config
(`WESTON_DRM_CONFIG=/tmp/.weston_drm.conf`, watched by the stock compositor):

```
output:DSI-2:pos=0,0      # bottom panel at the origin -> new windows land here
output:DSI-1:pos=1024,0   # top panel keeps its own area
output:DSI-2:input=gt9xx* # point the touch controller at the bottom panel
```

This runs only when both `card0-DSI-1` and `card0-DSI-2` exist, and waits ~1 s
for weston to apply the layout before the window is mapped. `run.sh` saves the
previous config and **restores it on exit** (via an `EXIT` trap); leaving the
outputs swapped after the app closes confuses the stock menu.

### Touch

Three things have to be right for touch to work:

1. **The compositor must associate `gt9xx-0` with the panel the app is on.**
   weston's default association is DSI-1 (the top panel), but the stock menu —
   and therefore the app, which opens on the same panel — is on DSI-2 (bottom).
   `run.sh` points the controller at DSI-2 with `output:DSI-2:input=gt9xx*`.
2. **`/sys/class/anbernic_misc/tpctrl` must be `0` for a Wayland app.** It is a
   touch-routing flag: `0` routes the panel to the compositor (what we need),
   `1` takes it away from the compositor. The stock menu flips it to `1` while
   handing over to an app, which is why touch was dead on a real menu launch even
   though it worked when the app was started by hand. `run.sh` writes `0` back
   just before exec. An earlier version of `Hishell.sh` also wrote `1`, which
   compounded it. (Confusingly, the stock **SDL/DRM** apps — `wiliwili`,
   `fileM` — write `1` in their `launch.sh`, because they read the panel
   directly rather than through weston.)
3. The app itself needs no special handling: with those two correct, weston
   delivers `wl_touch` events to the app's surface (verified with
   `WAYLAND_DEBUG=1`, which shows `wl_touch.down` / `motion` / `up` for the
   app's surface) and Qt synthesizes the mouse events the `MouseArea`s handle.

Panel mapping (verified by switching an output off and watching which physical
panel goes dark): **DSI-1 = top, DSI-2 = bottom (touch)**. The stock menu opens
on the bottom, i.e. weston's default toplevel output is DSI-2.

The app itself needs no special handling: with those two correct, weston delivers
`wl_touch` events to the app's surface (verified with `WAYLAND_DEBUG=1`, which
shows `wl_touch.down` / `motion` / `up` for the app's surface) and Qt synthesizes
the mouse events the `MouseArea`s already handle.

### The launcher must not be running underneath

`dmenu.bin` (the stock menu) is fullscreen on the bottom panel. If it is still
running when the app is started, it keeps the touch focus and the app gets no
touch. In the normal menu flow this is not a problem — `dmenu.bin` writes
`/tmp/.next` and **exits** before `dmenu_ln` runs the app script, so the app is
alone. It only bites when the app is started by hand over SSH while the menu is
still up.

### UI scale

The panels are 1024×768, which leaves the stock sizes too small to hit reliably
with a finger. `run.sh` sets `QT_SCALE_FACTOR` (default `1.5`); override it with
`HISHELL_SCALE` (e.g. `HISHELL_SCALE=2`).

### Focus stall (fixed)

Moving the cursor onto some files used to freeze the UI for ~0.25–1 s. It only
happened on non-folders, because `ActionManager.openApp` (used for the *Open
with …* label and icon) is skipped for directories but runs on every focused
file.

`ActionManager` re-evaluates `get_default_app(path)` → `KApplicationTrader`
whenever the focused item changes. This OS ships **no shared-mime-info database
and no KService database**, so:

- `QMimeDatabase::mimeTypeForFile()` returns an **empty** MIME type for binary
  files, and
- `KApplicationTrader::preferredService("")` then takes its slow fallback path
  and logs `kf.service.services: KApplicationTrader: mimeType "" not found`,
  blocking the GUI thread for hundreds of ms each time.

An `strace` of an automated focus sweep (a uinput virtual keyboard) showed the
main thread stalling up to **960 ms**, with a blank gap right before the
`KApplicationTrader` warning. `kde_bridge.cpp` now short-circuits the empty-MIME
case and caches results by MIME name; the same sweep afterwards shows **no
main-thread gaps over 100 ms and zero trader warnings**.

## Building (fast path — use this)

Only the **C++ bridge** needs the sysroot; the Rust side cross-compiles
**natively** on the host. Building *inside* the sysroot under qemu-user instead
takes ~50 min cold and re-runs on every change; this path is ~1.5 min cold and
**~15 s incremental**.

```bash
# one-off (a few minutes, ~2 GB)
"RG DS Plus port/setup-sysroot.sh"          # creates /tmp/opencode/rgds/trixie-aarch64

# every iteration
"RG DS Plus port/build.sh"                  # --debug (default) or --release
"RG DS Plus port/deploy.sh"                 # scp to root@192.168.31.28:/opt/hishell
```

`build.sh` needs, on the host: `cargo`, `aarch64-linux-gnu-gcc/g++`,
`qemu-user-static`, and the `aarch64-unknown-linux-gnu` Rust target (installed
automatically). It sets up, around `cargo build --target aarch64-unknown-linux-gnu`:

- `PKG_CONFIG_*` / `QT_INCLUDE_PATH` / `KF6_INCLUDE_PATH` / `MOC` pointed at the
  sysroot (the sysroot's Qt 6.8 `moc`, run under qemu — ~1 s);
- `-rpath-link` into the sysroot for the Qt/KF6 transitive deps;
- a host-side `/lib/aarch64-linux-gnu` symlink farm: Debian's `libm.so` is a
  linker script with **absolute** paths (`/lib/aarch64-linux-gnu/libm.so.6`,
  `/lib/ld-linux-aarch64.so.1`) that otherwise do not resolve outside a real
  multiarch rootfs.

`build.rs` honours `KF6_INCLUDE_PATH` / `PKG_CONFIG_SYSROOT_DIR` so the KF6
headers are found under the sysroot instead of the hard-coded `/usr/include/KF6`.

### Bundle → device install path

The Rust binary is the same either way; only the *bundle* (Qt/KF6 libs, QML,
plugins, icon theme under `/opt/hishell`) comes from `collect_bundle.sh`. For
iterating on app code you only need to replace the binary
(`deploy.sh` does exactly that). Re-run the full bundle collection only when the
shipped Qt/KF6 set or the QML modules change.

### Slow path (fallback, builds entirely inside the sysroot under qemu)

```bash
# inside the sysroot:
sudo chroot /tmp/opencode/rgds/trixie-aarch64 /bin/bash -lc '
  export RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
  cd /build/hishell && cargo build'
```


## Key findings worth remembering

- **`libstdc++` must be bundled.** Debian's Qt6 needs `CXXABI_1.3.15`; the target
  only has `1.3.14`. Without it the app dies at load.
- **Qt 6.8.2 rejects cyclic QML type dependencies** that Qt 6.12 accepts. The dev
  machine runs Qt 6.12, the port ships Qt 6.8.2 — that difference is why the
  window never appeared at first.
- **The SVG icon-engine plugin (`qt6-svg-plugins`) is required** for themed SVG
  icons to be found at all (`QIcon::m_supportsSvg`).
- **`wayland-graphics-integration-client` plugins are required for GL.** Without
  them Qt Quick falls back to nothing ("Failed to load client buffer integration:
  wayland-egl"), then fails to create a GL context and draws nothing.
- **The Breeze theme symlinks its mimetype icons into `breeze-dark`**, so both
  trees must be shipped or file-type icons are missing.
- **weston ignores a client's requested output**; placement is done via the
  compositor's dynamic output config.
- **Touch needs two things**: the compositor must associate `gt9xx-0` with the
  app's output (`output:DSI-2:input=gt9xx*`), and
  `/sys/class/anbernic_misc/tpctrl` must be `0` for a Wayland app. `dmenu.bin`
  sets `tpctrl=1` while handing over to an app, so `run.sh` writes `0` back.
- **`tpctrl` is a routing flag, not a power switch.** Wayland apps want `0`
  (panel goes to the compositor); the stock SDL/DRM apps write `1` (they read
  the panel directly).
- **The stock menu holds the touch focus.** While `dmenu.bin` is running, an app
  started on top of it gets no touch. The normal menu flow is fine because
  `dmenu.bin` exits before the app script runs.
- **Leaving the outputs swapped confuses the stock menu.** `run.sh` restores the
  previous layout on exit.

## Known issues / not finished

- **Intermittent crash when a context menu opens.** Seen once: the app
  segfaulted (`SIGSEGV`, exit 139) right after the context-menu `xdg_popup` was
  configured. It has not reproduced since, and a later attempt opened the same
  menu fine, so the trigger is not known. The device binary is unstripped, so a
  core dump (`core_pattern`, `ulimit -c unlimited`) plus the host `gdb`
  (`--enable-targets=all`, `set sysroot` to the dump rootfs) should give a
  backtrace if it recurs.
- **Fixed: brief freeze when focusing some files.** Was a ~0.25–1 s GUI-thread
  stall from `KApplicationTrader` on an empty MIME type (see "Focus stall"
  above). Fixed and verified.
- **The focus border renders wrong** — four separate corner borders instead of
  one clipped frame (`sourceClipRect` on the SVG does not clip as intended). A
  pre-existing app issue.
- **The top panel is unused** — only the bottom is wired up.
- **The stock menu can crash after output swapping.** Once, after the app had
  been run (and the outputs were left swapped by the old `run.sh`), navigating
  the menu wrapped onto the top panel and the menu crashed. `run.sh` now restores
  the stock layout on exit; whether that fully prevents it is unconfirmed.
- `kf.kirigami.platform: Failed to find a Kirigami platform plugin for style
  "Fusion"` — harmless (no plasma workspace).
- `qt.qml.typeresolution.cycle` warning — pre-existing, non-fatal.

## Validation performed

- **End-to-end via the real menu**: tapping the Hishell icon in the stock APPS
  menu opens the app fullscreen on the bottom (touch) panel, with working touch
  and the UI scaled 1.5× (via `QT_SCALE_FACTOR`). This was the key acceptance
  test and it passes.
- `cargo build --release` succeeds inside the aarch64 sysroot.
- Runs under weston 14 headless and, on the device, with the **threaded GPU
  render loop** (`QSG_INFO=1` confirms OpenGL, not software).
- Clean-room test: with all system Qt/KF moved aside the bundle still ran.
- Icons resolve: `text-x-generic`, `image-x-generic`, `folder`, etc.
- ABI: bundle provides `CXXABI_1.3.15`, needs ≤ `GLIBC_2.35`, target has 2.41.
- Dependency closure: all `NEEDED` SONAMEs resolve.
- ~110 MB RSS, comfortable in 1 GB.

## Debugging notes

- **Remote desktop via weston's `[screen-share]` does not work on this OS** —
  weston ships without `vnc-backend.so` (only `drm-backend`, `gl-renderer`,
  `color-lcms`), and the upstream `vnc-backend.so` needs `libneatvnc`/`libaml`
  built against libav 63, which the device's libav 61 will not satisfy. Building
  a matching backend is possible but out of scope. `weston-screenshooter` is
  present but the compositor does not export the capture protocol the client
  expects ("unauthorized").
- The device binary is **unstripped**, and the dump contains the whole rootfs, so
  a core dump plus the host `gdb` (`--enable-targets=all`) with
  `set sysroot ~/Desktop/Ambernic/rootfs` can symbolise a crash if needed.
