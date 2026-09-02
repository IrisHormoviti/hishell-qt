# Hishell Qt File Manager

## Build & Run

- **Build**: `cargo build` (Rust + Qt6, no separate QML compilation)
- **Run**: `cargo run` or `cargo run -- /path/to/folder`
  - Accepts `file://` URIs which are percent-decoded to absolute paths.
- **CMake** is present in a `build/` directory but the default workflow is Cargo-only.

## Architecture

- Rust backend (`src/`) + Qt6 QML frontend (`qml/`). Bridged via `qmetaobject`.
- Main entry: `src/main.rs` registers `Config`, `Directory`, and `FileManager` types for Qt.
- QML entry: `qml/main.qml` uses Kirigami application window; layouts are driven by `.cfg` config files.
- **Prefer Rust backend over JS inside QML for code implementation whenever possible.** Use qmetaobject to expose Rust types/functions to QML rather than writing inline JavaScript logic.

## Rust-exposed QML Types

- When adding or modifying types exposed from Rust to QML, ensure they are properly registered in `qml/Hishell/hishell.qmltypes`.
- QML types are registered in `src/main.rs` via `qmetaobject::qml_register_type` calls.
- The `qml/Hishell/hishell.qmltypes` file lists the types available to QML imports; keep it in sync with what is registered in Rust.

## Configuration

- Per-folder config is a `.cfg` file (INI-style), e.g., `~/.config/hishell/folder.cfg`.
- Default config: `config/default.cfg`.
- Config keys control layout, sorting, grid size, thumbnails, and navigation behavior.

## Testing

- No unit or integration tests exist in this repo.
- Verify by running the app with a target directory and inspecting behavior (drag-and-drop, views, layouts).

## Dependencies

- Rust toolchain + `cargo`
- Qt6 development packages (Core, Gui, Qml, Quick)
- CMake ≥ 3.20
- pkg-config
- bsdtar
- ImageMagick (`magick` or `convert`)
- ffmpegthumbnailer (optional; video thumbnails fall back to Rust fallback)

## Style & Formatting

- **Always use tabs for indentation** in all files:
  - Rust: enforced by `rustfmt.toml` (`hard_tabs = true`, `tab_spaces = 4`)
  - QML: `.qmlls.ini` requires tabs
  - Config/editor config: `.editorconfig` specifies tab indent style

## Git workflow

- Branches are not explicitly documented; follow standard practices.
- Commits often include "i swear it worked a second ago" for flaky runtime fixes — treat flakiness as a known issue.
