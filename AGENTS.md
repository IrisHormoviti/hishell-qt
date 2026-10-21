# Hishell Qt File Manager

## Build & Run

- **Build**: `cargo build` (Rust + Qt6, no separate QML compilation)
- **QML is embedded at compile time** via `qmetaobject::qrc!` in `src/main.rs`. `build.rs` only watches `src/`, so editing a `.qml` file alone does not trigger a rebuild. After QML changes, `touch src/main.rs` (or `cargo clean -p hishell-qt`) before `cargo build`, or the running binary keeps the old QML.
- **Run**: `cargo run` or `cargo run -- /path/to/folder`
    - Accepts `file://` URIs which are percent-decoded to absolute paths.
- **CMake** is present in a `build/` directory but the default workflow is Cargo-only.

## Architecture

- Rust backend (`src/`) + Qt6 QML frontend (`Hishell/`). Bridged via `qmetaobject`.
- Main entry: `src/main.rs` registers `Config`, `Directory`, `FileManager`, `DragHandler`, `DropValidator`, `PathUtils`,
  `LayoutEngine`, `SelectionManager`, `FocusManager` types for Qt.
- QML entry: `Hishell/ShellWindow.qml` uses Kirigami application window; layouts are driven by `.cfg` config files.
- **Prefer Rust backend over JS inside QML for code implementation whenever possible.** Use qmetaobject to expose Rust
  types/functions to QML rather than writing inline JavaScript logic.
- **Pass a `window` property to each loaded component** to avoid unqualified access in QML.
- **Be very mindful about the comments you add, don't write anything unessecary**

## Rust-exposed QML Types

- When adding or modifying types exposed from Rust to QML, ensure they are properly registered in
  `Hishell/plugins.qmltypes`.
- QML types are registered in `src/main.rs` via `qmetaobject::qml_register_type` calls.
- The `Hishell/plugins.qmltypes` file lists the types available to QML imports; keep it in sync with what is
  registered in Rust.
- New modules: `drag_handler.rs`, `selection_manager.rs`, `focus_manager.rs`, `gamepad.rs`, `path_utils.rs`,
  `drop_validator.rs`, `layout_engine.rs`
- AppImage desktop entries and icons are read directly from the appended SquashFS image by
  `appimage.rs` + `squashfs.rs`; no external tools are involved.

## Configuration

- Per-folder config is a `.cfg` file (INI-style), e.g., `~/.config/hishell/folder.cfg`.
- Default config: `config/default.cfg`.
- System config: `$XDG_CONFIG_DIRS/hishell/folder.cfg` (default `/etc/xdg/hishell/folder.cfg`).
  Loaded after the default and before the user's config, with later files overriding earlier ones.
- Config keys control layout, sorting, grid size, thumbnails, and navigation behavior.

## Testing

- No unit or integration tests exist in this repo.
- Verify by running the app with a target directory and inspecting behavior (drag-and-drop, views, layouts).

## Dependencies

- Rust toolchain + `cargo`
- Qt6 development packages (Core, Gui, Qml, Quick)
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
    - Usage: `timeout 30s qmlls --no-cmake-calls -E QML_IMPORT_PATH=/home/iris/Projects/hishell-qt:qml -I . Hishell/*.qml; status=$status; printf 'qmlls exit: %s\n' $status; exit $status`
    - No output = no errors found

- **cargo fmt**: Ensures consistent tab indentation across all files (Rust and QML)

- **cargo clippy**: Optional static analysis for Rust code quality

- Branches are not explicitly documented; follow standard practices.
- Commits often include "i swear it worked a second ago" for flaky runtime fixes — treat flakiness as a known issue.

## State Synchronization Notes (QML/Rust)

- For complex state passing between QML and Rust via qmetaobject, relying on direct property bindings during component
  declaration can lead to timing or syntax errors.
- Best practice dictates consolidating related state into a single, structured property (e.g., JSON string). This
  consolidated property should be updated in the backend logic whenever any underlying state changes.
- Furthermore, dependent components must explicitly read and set this derived state within `Component.onCompleted` to
  guarantee initialization occurs after all dependencies are ready.
