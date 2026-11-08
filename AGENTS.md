# Hishell Qt File Manager

## Build & Run

- Clone with `git clone --recurse-submodules`; the pure core lives in the `hishell/` submodule.
- **Core build**: `cargo build` inside `hishell/` (no Qt or system dependencies).
- **Build**: `cargo build` in the repository root (Rust + Qt6, no separate QML compilation)
- **Qt dependency**: `qtbridge` (Qt 6.10+ with private headers). The `hishell-qt` binary is the qtbridge frontend.
- **QML is embedded at compile time** via `include_bytes_qml!` in `src/main.rs`. Rebuild after QML changes; the debug binary picks up the new resource.
- **Gamepad**: `cargo build --features gamepad`; the release bundle enables it. Default builds omit `gilrs`/`libudev`.
- **Run**: `cargo run` or `cargo run -- /path/to/folder`
    - Accepts `file://` URIs which are percent-decoded to absolute paths.
- **CMake** is present in a `build/` directory but the default workflow is Cargo-only.

## Architecture

- Two repositories: `hishell` (pure Rust core, the `hishell/` submodule) and `hishell-qt`
  (Qt frontend). Qt code lives only in the outer repository.
- Rust backend (`src/main.rs`) + Qt6 QML frontend (`src/qml/`). Bridged via `qtbridge`.
- Main entry: `src/main.rs` registers `ConfigBridge`, `Directory`, and `PathBridge` with `QApp`.
- QML entry: `src/qml/Main.qml` uses Qt Quick Controls and Kirigami icons.
- **Prefer Rust backend over JS inside QML for code implementation whenever possible.** Use qtbridge to expose Rust
  types/functions to QML rather than writing inline JavaScript logic.
- **Pass a `window` property to each loaded component** to avoid unqualified access in QML.
- **Be very mindful about the comments you add, don't write anything unessecary**

## Rust-exposed QML Types

- QML types are exposed from the `#[qobject]` impls in `src/main.rs` and registered in `QApp`.

## Configuration

- Per-folder config is a `.cfg` file (INI-style), e.g., `~/.config/hishell/folder.cfg`.
- Default config: `config/default.cfg`.
- System config: `$XDG_CONFIG_DIRS/hishell/folder.cfg` (default `/etc/xdg/hishell/folder.cfg`).
  Loaded after the default and before the user's config, with later files overriding earlier ones.
- Config keys control layout, sorting, grid size, thumbnails, and navigation behavior.

## Testing

- No unit or integration tests exist in this repo.
- Verify by running the app with a target directory and inspecting behavior (drag-and-drop, views, layouts).
- On the device, never leave test files in the home directory root. Use
  `/home/.scratch/<task>/` (dot-prefixed so the file manager does not list it),
  or `/tmp` for files that do not need to survive a reboot. Clean up afterwards.

## Dependencies

- Rust toolchain + `cargo`
- Qt6 development packages (Core, Gui, Qml, Quick)
- A user-local KF6 development prefix is detected at `~/.local/lib/kf6-devel`; set `KF6_PREFIX` to override it.
- CMake ≥ 3.20
- pkg-config
- ImageMagick (`magick` or `convert`)
- ffmpegthumbnailer (optional; video thumbnails fall back to Rust fallback)

## Tools & Validation

- **qmlls**: QML language linter for validating `.qml` files and catching syntax/type errors early
    - Usage: `qmlls --no-cmake-calls -E QML_IMPORT_PATH=/home/iris/Projects/hishell-qt:qml -I . qml/*.qml`
    - No output = no errors found

- **cargo fmt**: Ensures consistent tab indentation across all files (Rust and QML)

- **cargo clippy**: Optional static analysis for Rust code quality

- Branches are not explicitly documented; follow standard practices.

## Tools & Validation

- Always validate with `cargo run` and a timeout before considering a task done.

- **qmlls**: QML language linter for validating `.qml` files and catching syntax/type errors early
    - Usage: `timeout 30s qmlls --no-cmake-calls -E QML_IMPORT_PATH=/home/iris/Projects/hishell-qt:qml -I . src/qml/*.qml; status=$status; printf 'qmlls exit: %s\n' $status; exit $status`
    - No output = no errors found

- **cargo fmt**: Ensures consistent tab indentation across all files (Rust and QML)

- **cargo clippy**: Optional static analysis for Rust code quality

- Branches are not explicitly documented; follow standard practices.
- Commits often include "i swear it worked a second ago" for flaky runtime fixes — treat flakiness as a known issue.

## State Synchronization Notes (QML/Rust)

- For complex state passing between QML and Rust via qtbridge, relying on direct property bindings during component
  declaration can lead to timing or syntax errors.
- Best practice dictates consolidating related state into a single, structured property (e.g., JSON string). This
  consolidated property should be updated in the backend logic whenever any underlying state changes.
- Furthermore, dependent components must explicitly read and set this derived state within `Component.onCompleted` to
  guarantee initialization occurs after all dependencies are ready.
