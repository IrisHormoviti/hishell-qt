# Hishell Core Migration

This document describes splitting the current `hishell-qt` application into:

- **`hishell`** — a pure, toolkit-agnostic Rust core, including its pure-Rust platform
  implementations.
- **`hishell-qt`** — a standalone Qt desktop frontend that only renders and forwards input.

The goal is that all behaviour that is not presentation lives in `hishell`, and that
`hishell-qt` becomes a thin adapter. A future Slint frontend must be able to reuse the
same core without reimplementing file management, config, selection, actions, layout, or
file operations.

The migration deliverable is the pure core plus the `qtbridge` frontend. `hishell-qt` is
now that frontend: the `qmetaobject` app, its adapters, and its ClamOS theme have been
removed.

## 1. Locked decisions

These are settled and should not be revisited during the migration.

1. **Core config type is `Config`, not `Settings`.**
   `hishell::config::Config` is the data type. The qtbridge adapter is `ConfigBridge`
   (registered to QML as `Config`).
2. **The core owns selection state and actions.**
   `Selection` and an action registry/state machine live in `hishell`. The Qt frontend
   renders menus and forwards `ActionId` invocations.
3. **File operations are pure Rust and asynchronous.**
   `hishell::ops` performs the work with Rust crates; `hishell::jobs` runs it on a worker
   pool and delivers completion/progress events. No KDE in the operation path.
4. **ClamOS-specific visuals are removed from the frontend.**
   `topscreen`, the custom focus border, the ClamOS theme backend, and the custom
   `ViewButton`/`ViewDialog`/`ViewMenu`/`ViewSlider`/`SegmentedButtons` stack are gone.
5. **The frontend uses native KDE widgets and theme.**
   `Kirigami.Theme`, `Kirigami.Units`, `Kirigami.Icon`, Qt Quick Controls with the host
   style. No custom `CoreTheme`.
6. **The fancy focus border is ClamOS-only.**
   The frontend draws an ordinary focus rectangle; the SVG and its recolouring code are
   deleted.
7. **Icons distinguish theme names from paths.**
   `IconRef::Theme(name)` is resolved by the frontend's native icon theme.
   `IconRef::Path(path)` is always an absolute path/URI for icons that are real files.
   This is a common case here: `.directory`/`.desktop` `Icon=`, AppImage icons, and
   descriptor icons can all be files.
8. **The Qt frontend owns the application and event loop.**
   The current host-loading contract (`install`/`setup_process`/`load(engine)`) is
   dropped. `hishell-qt` is a standalone binary.
9. **The Qt binding is Qt Bridge for Rust (`qtbridge`), not CXX-Qt.**
   Target Qt is 6.10+ and confirmed. `qmetaobject` has been removed from the crate.
10. **A `hishell` location may be a folder or a file.**
    The core models both through `Location`. Folder-only features (listing, sorting,
    grouping, slots, free placement, radio groups, selection) apply only to folder
    locations. File locations expose the single item's icon, thumbnail, MIME, metadata,
    preview, and the file-applicable actions. `hishell-qt` stays a folder file manager and
    resolves a file argument to its parent folder; it does not need a file view. The file
    location exists for frontends that do need it (e.g. ClamOS opening an individual file).
11. **Input handling belongs to the frontend.**
    Core exposes semantic commands (focus navigation, selection operations, action
    invocation, open/navigate, drag/drop decisions), never raw events. Key bindings,
    gamepad polling, pointer/touch handling, drag gesture recognition, shortcut
    registration, and text entry stay in each frontend.
    The ClamOS system-keyboard request protocol is removed from the shared code:
    `src/keyboard.rs`, `FileManager::{request_text_entry, poll_text_entry,
    cancel_text_entry, keyboard_available}`, and the `ActionManager.qml` polling flow are
    deleted. The Qt app renames through its own dialog; a ClamOS frontend can reintroduce
    its keyboard IPC on its own.
12. **Execution and the execution wrapper stay in `hishell`.**
    Core owns `[Layout] ExecutionWrapper`, the `--preflight` handshake, confirm/cancel,
    the `HISHELL_APP_ITEM`/`HISHELL_APP_NAME` environment contract, process spawning,
    launch markers, `quit_active`, and pending-launch state. The frontend only renders a
    launch prompt and forwards confirmation/cancellation by request id.
13. **Configs are a superset of freedesktop desktop entries.**
    `Type=Application`, `Type=Link`, and `Type=Directory` stay compatible. Hishell adds
    `Type=Button`, `Type=Toggle`, `Type=Number`, `Type=Radio`, and `Type=File` (metadata
    for the file it is attached to, or a `Path=` descriptor for a file in a general
    location; no `Exec`). A folder does not have to be `Type=Directory`: an entry on the
    folder can make it act as an `Application` or a `Link`.
14. **Hishell supports a raw mode.**
    `Mode::Raw` ignores every on-disk config (`.desktop`, `.directory`, `.cfg`,
    descriptors, AppImage metadata) and treats each item as exactly what it is physically:
    `File` or `Directory`. Engine defaults and host-provided runtime settings still apply.

## 2. Non-goals

- Building the Slint frontend in this migration.
- Preserving the ClamOS look in the frontend.
- Preserving the ClamOS system-keyboard request IPC in the frontend.
- Moving QML animation, delegate construction, drag gestures, or dialog painting into core.
- Moving key, gamepad, pointer, touch, shortcut, or text-entry input handling into core.
- Keeping `qmetaobject`.
- Preserving the old host-loading library contract.

## 3. Target architecture

`hishell` is its own repository (`IrisHormoviti/hishell`) and is checked out as a git
submodule at `hishell/`; the outer repository stays `hishell-qt`. The core builds
standalone (`cargo build` inside `hishell/`).

```
hishell/                       # pure Rust, no Qt, no Slint, no KDE
  engine.rs                    # Engine, Deps, Command, Outcome, Effect
  change.rs                    # ChangeSet, FolderDelta, ConfigDelta
  config.rs, config_parser.rs  # Config, ConfigKey, parser, writes
  value.rs
  view.rs, layout.rs           # ViewSpec, grid/list math, grouped/free slots
  location.rs                  # Location = Folder(Folder) | File(File)
  folder.rs                    # scan, sort, apply config, radio helpers
  item.rs, entry.rs, icon.rs   # Item, ItemId, IconRef, entry types, MIME icons
  group.rs                     # date, letter, type, custom, and stash groups
  selection.rs                 # Selection
  navigation.rs, path.rs       # PathRelation, NavigationPlan, lexical helpers
  history.rs, session.rs       # back/forward stacks, SessionStore
  ops.rs, jobs.rs              # file operations and the worker pool
  prompt.rs                    # Prompt, Notice, FrontendRequest
  execution.rs                 # wrapper, preflight, spawner, launch lifecycle
  platform.rs                  # capability traits and FreeDesktop implementations
  squashfs.rs                  # AppImage support
  error.rs, lib.rs

hishell-qt/                    # thin qtbridge desktop frontend
  src/main.rs                # ConfigBridge, Directory, PathBridge
  src/qml/Main.qml           # window and the Header/Top/Middle/Bottom stack
  src/qml/LayoutEngine.qml   # loads the configured layout components
  src/qml/FolderPane.qml     # one folder pane and its transitions
  src/qml/toolkit/           # header items, the old toolkit split
    MenuBar.qml, ViewMenu.qml, ViewActions.qml, ViewSlider.qml
    PathBar.qml, Spacer.qml, WindowControl.qml
    ConfigureDialog.qml, ShellMenuItem.qml
  Cargo.toml                 # hishell + qtbridge only
```

### Dependency rules

- `hishell` must not depend on `qtbridge`, `qttypes`, `slint`, KDE, or C++.
- `hishell` may depend on crates such as `serde`, `image`, `zip`, `trash`, `walkdir`.
- `hishell-qt` depends on `hishell`, `qtbridge`, and `gilrs` for gamepad input.
- A future `hishell-slint` depends on `hishell` and may inject its own platform impl.
- Core exposes traits and ships the default pure-Rust implementation; it never links a
  frontend.

### Threading model

- The UI thread owns all frontend objects.
- Scanning, thumbnail generation, descriptor generation, and file operations run on
  workers.
- Workers never call into the frontend. They send values through channels.
- The frontend pumps events on the UI thread:
  - `qmetaobject`: existing `poll_*` methods.
  - `qtbridge`: `QThreadHandle` or a poll timer.
  - Slint later: `invoke_from_event_loop` or a timer.

## 4. Core design

### 4.0 `Engine` facade and ownership

The public entry point is a single `Engine`. It owns the state and services; there are no
process globals.

```rust
pub struct Engine {
    config: Config,
    location: Location,
    ops: Jobs,
    execution: Execution,
    session: SessionStore,
    history: History,
    platform: Platform,
    clock: Arc<dyn Clock>,
    diagnostics: Diagnostics,
}

pub struct Deps {
    pub platform: Platform,
    pub spawner: Arc<dyn Spawner>,
    pub clock: Arc<dyn Clock>,
    pub executor: Arc<dyn Executor>,
    pub session: SessionStore,
}

pub enum Mode {
    Config, // read entries and per-folder configs
    Raw,    // ignore all on-disk config; items are File or Directory only
}

pub struct RuntimeSettings {
    pub execution_wrapper: Option<String>,
    pub screen: Option<String>,
    pub default_layout: LayoutSpec,
}

pub struct OpenOptions {
    pub mode: Mode,
    pub deps: Deps,
    pub runtime: RuntimeSettings,
}

impl Engine {
    pub fn open(path: &Path) -> Result<Self, Error>;
    pub fn open_with(path: &Path, options: OpenOptions) -> Result<Self, Error>;
    pub fn open_location(location: Location) -> Result<Self, Error>;
    pub fn open_location_with(location: Location, options: OpenOptions) -> Result<Self, Error>;

    pub fn mode(&self) -> Mode;
    pub fn set_mode(&mut self, mode: Mode) -> Result<ChangeSet, Error>;

    pub fn location(&self) -> &Location;
    pub fn config(&self) -> &Config;
    pub fn selection(&self) -> Option<&Selection>;
    pub fn item(&self, id: ItemId) -> Option<&Item>;
    pub fn item_at(&self, path: &Path) -> Option<&Item>;
    pub fn history(&self) -> HistoryStatus;

    pub fn view(&self, request: ViewRequest) -> ViewSpec;
    pub fn actions(&self, request: &ActionRequest) -> Vec<ActionSpec>;
    pub fn descriptor(&self, id: ActionId) -> &'static ActionDescriptor;
    pub fn relation(&self, target: &Path) -> PathRelation;
    pub fn navigation_plan(&self, request: &NavigationRequest) -> NavigationPlan;
    pub fn dispatch(&mut self, command: Command) -> Result<Outcome, Error>;
    pub fn tick(&mut self) -> TickResult;
}
```

`Command` is the single mutation boundary:

```rust
pub enum Command {
    Open(PathBuf),
    Navigate(NavigationRequest),
    History(HistoryCommand),
    GoUp,
    Refresh,
    SetConfig { key: ConfigKey, value: ConfigValue, local: bool },
    SetMode(Mode),
    Select(SelectionCommand),
    Focus(FocusCommand),
    Invoke(ActionId),
    ConfirmLaunch(LaunchId),
    CancelLaunch(LaunchId),
    Drop { sources: Vec<PathBuf>, dest: PathBuf, action: DropAction },
    CancelJob(JobHandle),
}
```

`Outcome` is what every mutation returns:

```rust
pub struct Outcome {
    pub changes: ChangeSet,
    pub effects: Vec<Effect>,
    pub job: Option<JobHandle>,
}

pub struct TickResult {
    pub changes: ChangeSet,
    pub effects: Vec<Effect>,
}
```

Rules:

- `Engine` is single-threaded and lives on the UI thread. It is not `Sync`.
- `Deps` injects the platform, spawner, clock, executor, and session store. Tests use
  fakes; there is no `install()` global and no static launch/session state.
- `RuntimeSettings` carries host policy that must survive raw mode: execution wrapper,
  screen, and default layout.
- `Op`, `Platform`, and owned snapshots are `Send`. Workers receive owned values.
- `Engine::open` uses the default FreeDesktop dependencies. `open_with`/`open_location_with`
  accept `OpenOptions` for tests, alternate frontends, and the Qt/Slint adapters.
- Queries (`view`, `actions`, `location`, `config`, `selection`, `item`, `item_at`) are
  `&self`; mutations go through `dispatch`; worker results arrive through `tick`.
- `tick` returns both changes and effects: a background job or launch can produce a
  notice or prompt long after the command that started it.

### 4.1 `Config`

`hishell::config::Config` owns every config value, including all UI fields.

Categories to move:

| Category | Fields |
|---|---|
| Layout | `Top`, `Middle`, `Bottom`, `Header`, `NativeMenuBar`, `NativeMenus`, `NativeTitleBar`, `NativeDrag`, `ShowShortcuts`, `ExecutionWrapper`, `Screen` |
| Window | `Title`, `Icon`, `Wallpaper`, `Maximized` |
| View | `GridMode`, `GridSize`, `GridHorizontalAlign`, `GridVerticalAlign`, `Lines`, `ScrollHorizontal`, `CenterFocus`, `SmoothScrolling`, `OpenOnClick`, `FocusEmptySlots`, `ShowLabels`, `GridLabelsBesideIcons`, `LabelText`, `ViewMode`, `ListColumns`, `ListHeader` |
| Sort | `Sort`, `SortDateMode`, `SortAlphaMode` |
| Group | `GroupMode`, `Groups`, `ShowStash`, `StashShown`, `StashDotfiles`, `FreePlacementPositions` |
| Radio | `RadioEnabled`, `RadioOnly`, `RadioSelected`, `RadioExec` |
| Diagnostics | error/error-file values |

`Lines` (`grid_lines`) and `GridSize` (`grid_size`) are not independent layout
controls. Exactly one of them determines the grid, selected by `GridMode`. See
§4.2.1.

Config scope by location:

| Scope | Fields |
|---|---|
| Both | `Title`, `Icon`, `Wallpaper`, `Maximized`, `Native*`, `ShowShortcuts`, `ExecutionWrapper`, `Screen`, `Layout` |
| Folder only | `GridMode`, `GridSize`, `Lines`, `GridHorizontalAlign`, `GridVerticalAlign`, `ScrollDirection`, `ShowLabels`, `GridLabelsBesideIcons`, `LabelText`, `ViewMode` (grid/list selection), `Sort*`, `Group*`, `ShowStash`, `Stash*`, `FreePlacementPositions`, `Radio*`, `CenterFocus`, `FocusEmptySlots` |
| File only | none in the folder config; file display data comes from its `.desktop` or descriptor |

`Config::load_for(location)`:

- Folder: the folder's `.directory` and `.cfg`, as today.
- File: the file's own entry (`.desktop`, descriptor, or sidecar) for display metadata,
  plus the parent folder's `.cfg` for location-wide fields. Folder-only fields are present
  but ignored by the file spec.

`hishell-qt` always calls `Config::load_for` with a folder location, because it resolves a
file argument to its parent folder.

The config surface is schema-driven. Core does not mutate fields by stringly-typed name.

```rust
pub enum ConfigKey { GridMode, GridLines, GridSize, /* ... */ }

impl ConfigKey {
    pub fn section(self) -> &'static str;
    pub fn name(self) -> &'static str;
    pub fn scope(self) -> LocationScope; // Both | Folder | File
    pub fn default(self) -> ConfigValue;
}

pub enum ConfigValue { Bool(bool), Int(i64), Str(String), Json(String) }

pub struct ConfigLoad {
    pub config: Config,
    pub diagnostics: Vec<ConfigDiagnostic>,
}

pub struct ConfigDiagnostic {
    pub file: PathBuf,
    pub line: Option<u32>,
    pub message: String,
}

pub struct ConfigDelta {
    pub key: ConfigKey,
    pub scope: ChangeScope, // order | items | view | all
    pub old: ConfigValue,
    pub new: ConfigValue,
}

impl Config {
    pub fn load_for(location: &Location) -> ConfigLoad;
    pub fn get(&self, key: ConfigKey) -> ConfigValue;
    pub fn set(&mut self, key: ConfigKey, value: ConfigValue) -> Result<ConfigDelta, ConfigError>;
    pub fn set_raw(&mut self, path: &Path, section: &str, key: &str, value: &str, local: bool)
        -> Result<ConfigDelta, ConfigError>;
    pub fn grid_sizing(&self) -> GridSizing; // LINES | SIZE, see §4.2.1
}
```

Rules:

- The schema (section, key, scope, default) is the single source of truth for parsing,
  validation, the View menu, and change routing.
- Core uses typed `get`/`set`; the frontend settings UI may use `set_raw` with the config
  file's string form.
- Load errors and validation diagnostics are returned in `ConfigLoad`, not stored as
  `error`/`error_file` fields.
- `ConfigDelta.scope` tells the adapter whether to re-sort, re-scan, or only re-layout.

The Qt `ConfigBridge` mirrors these fields with the existing QML property names and
notifies from a single `apply(&Config, ChangeScope)`. `Directory.config` still returns the
bridge.

### 4.2 `ViewSpec` and `LayoutSpec`

Core decides how a folder is displayed. The frontend supplies only measurements it can
know:

```rust
pub struct Viewport {
    pub width: f64,
    pub height: f64,
    pub horizontal_scrollbar: f64,
    pub vertical_scrollbar: f64,
}

pub struct Metrics {
    pub grid_unit: f64,
    pub small_spacing: f64,
    pub medium_spacing: f64,
    pub large_spacing: f64,
    pub label_height: f64,
}

pub struct ViewRequest {
    pub viewport: Viewport,
    pub metrics: Metrics,
}

pub enum GridSizing {
    /// `GridLines` wins: the line count is fixed and the icon size is derived.
    FixedLines { lines: u8 },
    /// `GridSize` wins: the icon size is fixed and the line count is derived.
    FixedIcon { icon_size: u16 },
}

pub struct GridSpec {
    pub sizing: GridSizing,
    pub lines: u8,          // resolved line count
    pub icon_size: f64,     // resolved icon size
    pub cell: Size,         // resolved cell size
    pub gap: f64,
    pub labels: LabelSpec,
    pub horizontal: bool,
}

pub enum FolderMode {
    Grid(GridSpec),
    List(ListSpec),
}

pub enum ViewSpec {
    Folder(FolderView),
    File(FileView),
}

pub struct FolderView {
    pub revision: u64,
    pub mode: FolderMode,
    pub sort: SortSpec,
    pub grouping: GroupingSpec,
    pub slots: Vec<SlotSpec>,      // SlotId + ItemId + logical cell + pixel rect
    pub headers: Vec<HeaderSpec>,
    pub focus: FocusSpec,
    pub interaction: InteractionSpec,
}

pub struct SlotSpec {
    pub id: SlotId,
    pub item: ItemId,
    pub cell: Cell,
    pub rect: Rect,
}

pub struct FileView {
    pub revision: u64,
    pub item: ItemId,
    pub mime: String,
    pub thumbnail: Option<PathBuf>,
    pub metadata: Vec<MetadataRow>,
    pub preview: Preview,          // None | Image | Text | Thumbnail | Custom
    pub interaction: InteractionSpec,
}

impl Engine {
    pub fn view(&self, request: ViewRequest) -> ViewSpec;
}
```

Consequences:

- `FolderGrid.qml` stops deciding columns/rows/cells/icon size.
- `Directory::free_layout` and `Directory::group_layout` fold into `Engine::view`.
- `ViewSpec` has two variants; a `FileView` cannot carry sort, grouping, slots, headers,
  focus, free placement, radio groups, or selection.
- `hishell-qt` only consumes `ViewSpec::Folder(FolderView)`; it resolves a file argument
  to its parent folder and never renders a file view.
- `Metrics` contains only units and label height. Icon sizes are derived by core and
  returned in `GridSpec`.
- `FolderView.revision` increments when the spec changes; `SlotSpec.id` is stable so a
  frontend can diff slots instead of rebuilding every delegate.
- `LayoutEngine.qml` stops parsing `[Layout]` strings; core returns:

```rust
pub struct LayoutSpec {
    pub panes: Vec<PaneSpec>, // path or component name, order, follows-window flag
    pub diagnostics: Vec<LayoutDiagnostic>,
}

pub struct PaneSpec {
    pub path: PathBuf,
    pub follows_window: bool,
    pub kind: PaneKind,
}

pub enum PaneKind {
    Folder,
    File,
    Component(String),
}
```

Qt still instantiates components, but the decision of what panes exist and which path each
pane shows is core.

The Qt adapter serializes `Engine::view`'s typed `ViewSpec` and `LayoutSpec` to JSON plus
revision counters.

#### 4.2.1 Grid sizing

`GridSize` was removed from the view previously; this migration brings it back as a
first-class alternative to fixed lines. The two modes are mutually exclusive, and the
choice belongs to the spec, not to QML.

`GridLines` is the existing `Lines` config key (`grid_lines` in Rust); this spec uses
the `GridLines` name for clarity. Keeping the key unchanged preserves existing configs.

Config encoding:

```toml
[Folder View]
GridMode = LINES   ; LINES | SIZE (default LINES)
Lines = 4          ; used when GridMode = LINES
GridSize = 72      ; used when GridMode = SIZE
```

Rules:

- `GridMode` is `LINES` when absent. Existing configs therefore keep today's behaviour.
- `GridMode` values are case-insensitive; an unknown value falls back to `LINES` with a
  `ConfigDiagnostic`.
- `LINES`: `GridSizing::FixedLines { lines: clamp(Lines or 4, 1, 8) }`.
  `GridSize` is ignored.
- `SIZE`: `GridSizing::FixedIcon { icon_size: clamp(GridSize or 72, 16, 256) }`.
  `Lines` is ignored.
- `Lines = 0` or negative in `LINES` mode means 4.
- `GridSize = 0` or negative in `SIZE` mode means 72.
- The resolved `GridSpec` always carries both `lines` and `icon_size`; the frontend reads
  both and never derives one from the other.
- If even one cell at the minimum icon size cannot fit the viewport, the view uses that
  minimum and scrolls rather than producing a zero-size cell.

Resolution:

- The main axis is the scroll axis: `ScrollDirection = VERTICAL` means lines are
  columns; `HORIZONTAL` means lines are rows.
- `FixedLines`: the icon size is the largest that fits `lines` cells across the main axis,
  after subtracting the scrollbar, gap, and label/padding. Clamp to `16..=256`.
- `FixedIcon`: the line count is the largest that fits `icon_size` cells across the main
  axis. Clamp to `1..=8`. If even one cell does not fit, `lines = 1` and the view scrolls.
- Both modes use the same cell formula, and `GridHorizontalAlign`/`GridVerticalAlign`
  apply to the resulting grid extent.
- `ShowLabels`, `GridLabelsBesideIcons`, `LabelText`, and the label height affect the
  cell in both modes.

The View menu should expose the active control based on `GridSizing`, or show both with
the inactive one disabled. The `config/default.cfg` comment for `GridSize` changes from
"legacy icon size" to "used when GridMode = SIZE".

### 4.3 `Folder`, `Item`, and `IconRef`

Move from `directory.rs`:

- `FileItem` becomes `Item`.
- `scan_items` / `placeholder_items`.
- Sorting (`sort_items`, date/alpha modes).
- Grouping (`date_group_key`, `letter_group_key`, `type_group_key`, custom groups).
- Filtering.
- Free and grouped slot computation.
- Radio group helpers.
- Execute/launch prompt preparation.
- Icon and title resolution.

`Item` keeps the current fields but cleans up the icon:

```rust
pub enum IconRef {
    Theme(String),       // "folder", "user-home", "text-x-generic"
    Path(PathBuf),       // absolute path or file:// target
}

pub struct ItemId(u64);

pub struct Item {
    pub id: ItemId,
    pub name: String,
    pub title: String,
    pub comment: String,
    pub path: PathBuf,               // what the item represents
    pub entry_path: Option<PathBuf>, // metadata entry, if any
    pub target: Option<PathBuf>,     // Link target
    pub fs_kind: FsKind,
    pub kind: ItemKind,
    pub mime: Option<String>,
    pub is_symlink: bool,
    pub is_dotfile: bool,
    pub icon: IconRef,
    pub is_entry: bool,
    pub toggle_on: bool,
    pub number_value: String,
    pub size: u64,
    pub modified: u64,
    pub created: u64,
    pub accessed: u64,
    pub group: u16,
    pub group_label: String,
    pub is_stashed: bool,
    pub custom_group: String,
    pub icon_ready: bool,
}
```

Icon resolution rules (the important part):

- An `Icon=` value from a `.desktop`, `.directory`, or descriptor is:
  - `Path` if it is absolute, contains a `/`, or starts with `file://`.
  - `Theme` otherwise.
- A relative path is resolved against the entry file's base directory and then made
  absolute.
- AppImage icons and descriptor icons are `Path`.
- MIME-derived and fallback icons are `Theme`.
- An icon that cannot be resolved to an existing file still stays a `Path` if the source
  was a path; the frontend shows a placeholder until it appears.
- The frontend must not sniff string prefixes to decide theme-vs-path. It reads the
  `IconRef` variant (serialized as `{"kind":"theme","name":...}` or
  `{"kind":"path","path":...}`).
- A `Theme` name the frontend's icon theme cannot resolve falls back to that frontend's
  generic type icon; core does not substitute a path.
- A `Path` that does not load yet is shown with a placeholder; core keeps the path so the
  icon can appear later.

Remove `query_gio_icon` and every `gio`/GLib shell-out. Resolve icons with a pure-Rust
path:

1. `.desktop`/`.directory`/descriptor/AppImage icon.
2. MIME-derived theme name from `mime_guess` (extension) and `infer` (content sniffing)
   plus a built-in MIME→icon-name table.
3. Descriptor-generator placeholder icon.
4. Fallback (`image-x-generic`, `video-x-generic`, `text-x-generic`).

There is no `gio` process and no per-extension subprocess. The Qt frontend may additionally
use native KDE MIME icons if it wants; the core value is still a valid `Theme` name.

#### 4.3.1 Location

The top-level state is a location, not always a folder:

```rust
pub enum Location {
    Folder(Folder),
    File(File),
}

pub struct Folder {
    pub items: Vec<Item>,
    pub visible: Vec<ItemId>,
    pub groups: Vec<Group>,
    pub selection: Selection,
    // scan generation, exposure, deferred load, ...
}

pub struct File {
    pub item: Item,
    pub mime: String,
    pub metadata: Vec<MetadataRow>,
    pub thumbnail: Option<PathBuf>,
}

impl Location {
    pub fn from_path(path: &Path) -> Result<Location, Error>;
    pub fn folder_or_parent(path: &Path) -> Location;
    pub fn folder(&self) -> Option<&Folder>;
    pub fn folder_mut(&mut self) -> Option<&mut Folder>;
    pub fn file(&self) -> Option<&File>;
}
```

Rules:

- `Location::from_path` returns `Folder` for a directory and `File` for a regular file. A
  symlink follows its target for this decision.
- `Folder` owns listing, sorting, grouping, filtering, slots, free placement, radio groups,
  and selection.
- `File` has exactly one `Item` and no listing, scan, sort, group, slots, free placement,
  radio group, or selection. It carries the metadata and preview data a frontend needs.
- `Item` is reused for files; `is_dir = false`, and file-only fields such as
  `toggle_on`/`number_value` still apply to desktop entries that are files.
- `ItemId` is the stable identity used by selection, focus, and slots. The visible order is
  `Vec<ItemId>`, not raw indices.
- `ItemId` is path-keyed and stable while the path remains in the folder, including across
  rescans and reorders. It is invalidated when the path disappears or the location changes;
  frontends ignore unknown IDs.
- `Engine::selection()` returns `Option<&Selection>`; it is `Some` only for a folder.
- Folder-only operations are capability methods on `Folder`; `Location` does not pretend to
  have them for a file.
- `SessionStore` saves and restores the location kind, so a file location survives a
  restart.
- `hishell-qt` resolves a file path to its parent folder before constructing a `Location`;
  it never creates `Location::File`.

#### 4.3.2 Entries and item kinds

The config model is a superset of freedesktop desktop entries. A parsed entry has a
`Type`, the standard keys, and Hishell extensions.

```rust
pub enum EntryType {
    Application,
    Link,
    Directory,
    Button,
    Toggle,
    Number,
    Radio,
    File, // metadata for the file it is attached to
}

pub struct Entry {
    pub path: PathBuf,                 // the entry file
    pub attached_to: Option<PathBuf>,  // sidecar attachment, when no Path= is given
    pub target: Option<PathBuf>,       // Path=/URL= for a File descriptor or Link
    pub entry_type: EntryType,
    pub mime: Option<String>,          // MimeType=, for EntryType::File
    pub sections: BTreeMap<String, BTreeMap<String, String>>,
    pub diagnostics: Vec<ConfigDiagnostic>,
}

pub enum FsKind { File, Directory }

pub enum ItemKind {
    Directory,
    File,
    Application,
    Link,
    Button,
    Toggle,
    Number,
    Radio,
}

`Item` is defined in §4.3; the fields relevant to entry resolution are `path`,
`entry_path`, `target`, `fs_kind`, `kind`, and `mime`.
```

Resolution:

- **Config mode**: an entry's `Type=` wins over the physical kind.
  - `Application` → `ItemKind::Application`; `Exec=` is launched even when the item is a
    folder.
  - `Link` → `ItemKind::Link`; `URL=`/`Path=` becomes `target`.
  - `Directory` → `ItemKind::Directory`.
  - `Button`/`Toggle`/`Number`/`Radio` → the matching control kind.
  - `File` → `ItemKind::File`. Two forms:
    - With `Path=` (or `URL=`): a descriptor for a specific file in a general location.
      The item's `path` is the target file and `entry_path` is the descriptor.
    - Without `Path=`: a sidecar attached to the file it accompanies. The item's `path` is
      that file and `entry_path` is the sidecar.
    `Name`, `Icon`, `Comment`, `MimeType`, and other display fields are supported.
    `Exec=` is invalid for `Type=File` and is ignored with a diagnostic. `Path=` is
    optional, but when present it must name a file; a directory or missing target is a
    diagnostic and the entry is skipped.
  - Missing entry → `File` or `Directory` from `fs_kind`.
- **Raw mode**: no entry is read; a directory is `Directory`, a file is `File`. Symlinks
  resolve to the target kind; a broken symlink is `File`.
- `path` is what the item represents. `Item.target` is only used by `Link`; a `Type=File`
  descriptor puts its target in `Item.path`.
- `Type=File` entries are metadata, not separate items, in both forms. If `Path=` is
  present and the target cannot be resolved, or a sidecar attachment cannot be resolved,
  the entry is skipped with a diagnostic.
- `MimeType=` overrides the detected MIME type for a `Type=File` entry.
- Actions on a `Type=File` descriptor operate on `path` (the target file) by default:
  open, rename, copy, trash, rotate, and the rest. `RemoveDescriptor` is a separate action
  that operates on `entry_path`.
- `is_dir` is derived from `fs_kind`; `is_entry` says whether an entry supplied the
  semantics.
- `control_kind` disappears; `kind` carries it. `toggle_on` and `number_value` are only
  meaningful for the matching control kinds.
- Unknown `Type=` values produce a `ConfigDiagnostic` and fall back to the physical kind.
- Freedesktop keys (`Name`, `Icon`, `Exec`, `URL`, `Path`, `Terminal`, `Categories`, ...)
  are parsed as usual. Hishell sections (`[Folder View]`, `[Radio]`, `[Destroy]`, ...)
  are extra keys on the same entry.
- A folder with `Type=Application` or `Type=Link` acts as that type, not as a directory;
  `fs_kind` still records that it is a directory for filesystem operations.

Allowed combinations:

| `Type=` | `FsKind::File` | `FsKind::Directory` | Notes |
|---|---|---|---|
| `Application` | yes | yes | folder launches `Exec=` |
| `Link` | yes | yes | target from `URL=`/`Path=` |
| `Directory` | no | yes | file emits a diagnostic |
| `Button` | yes | yes | trigger |
| `Toggle` | yes | yes | boolean state |
| `Number` | yes | yes | number fields |
| `Radio` | yes | yes | group member |
| `File` | yes | no | sidecar or `Path=` descriptor |
| missing | File | Directory | physical kind |

Filesystem actions (`rename`, `copy`, `trash`, `delete`) always operate on `path`, even
when `Type=Application`/`Link` changes the open/launch behaviour. A `Type=File` descriptor
is the exception: its `path` is the target file, and the descriptor itself is
`entry_path`.

Freedesktop keys that core honours:

- `Name`, `GenericName`, `Comment`, `Icon`, `Type`, `Exec`, `URL`, `Path`, `Terminal`,
  `Categories`, `MimeType`.
- `NoDisplay` and `Hidden` hide the entry as they do for desktop entries.
- `OnlyShowIn`/`NotShowIn` compare against `XDG_CURRENT_DESKTOP`.
- `TryExec` gates an `Application`.
- `Exec` field codes are parsed; there is no shell expansion beyond the desktop-entry
  substitution rules.

Hishell extensions are extra keys on the same entry: `[Folder View]`, `[Radio]`,
`[Destroy]`, `Type=Button/Toggle/Number/Radio/File`. They are honoured wherever the entry
lives; `Mode::Raw` is the way to browse untrusted media without reading entries.

### 4.4 `Selection`

Selection lives inside `Folder`, because a file location cannot have one:

```rust
pub struct Selection {
    pub active: bool,
    selected: HashSet<ItemId>,
    last: Option<ItemId>,
    anchor: Option<ItemId>,
}

impl Selection {
    pub fn enter(&mut self);
    pub fn exit(&mut self);
    pub fn toggle(&mut self, id: ItemId);
    pub fn select_only(&mut self, id: ItemId);
    pub fn range_to(&mut self, folder: &Folder, id: ItemId);
    pub fn select_all(&mut self, folder: &Folder);
    pub fn clear(&mut self);
    pub fn status(&self, folder: &Folder) -> SelectionStatus; // count + ordered ItemIds/paths
}

pub struct SelectionStatus {
    pub active: bool,
    pub count: usize,
    pub items: Vec<ItemId>,
    pub paths: Vec<PathBuf>,
}
```

Rules:

- `Engine::selection()` returns `Option<&Selection>`; it is `Some` only for
  `Location::Folder`.
- Selection operations take `ItemId`; core resolves the path and row index.
- The frontend emits `SelectionCommand` values through `Engine::dispatch`; it never
  mutates the selected set directly.
- `SelectionStatus` is a typed view struct; adapters serialize it. The qtbridge
  `Directory` mirrors it into its selection properties.
- `range_to` selects from the current anchor to `id`, inclusive, in visible order. The
  anchor is the last explicitly selected item, or the focused item when none has been
  selected; hidden/filtered items are skipped.

### 4.5 Actions

Move the decision-making parts of `ActionManager.qml` into `hishell::action`.

```rust
pub struct ActionId(&'static str);

impl ActionId {
    pub const COPY: ActionId = ActionId("copy");
    pub const CUT: ActionId = ActionId("cut");
    pub const PASTE: ActionId = ActionId("paste");
    // ...
    pub fn as_str(self) -> &'static str;
    pub fn from_str(value: &str) -> Option<ActionId>;
}

pub enum MenuKind {
    Main,
    Context,
    Edit,
    New,
    FolderMenu,
    View,
    SelectionBar,
}

pub enum Target {
    Location,
    Focus,
    Selection,
    Items(Vec<ItemId>),
    Auto, // Selection when active, otherwise Focus
}

pub struct ActionRequest {
    pub menu: MenuKind,
    pub target: Target,
}

pub enum LocationScope {
    Folder,
    File,
    Both,
}

/// What an action applies to. `Here` is the current view/location; menu placement is
/// independent (`ActionDescriptor.menus`).
#[derive(Clone, Copy)]
pub struct ActionSubjects(u32);

impl ActionSubjects {
    pub const HERE: Self = Self(1 << 0);
    pub const FOLDER: Self = Self(1 << 1);
    pub const FILE: Self = Self(1 << 2);
    pub const IMAGE: Self = Self(1 << 3);
    pub const AUDIO: Self = Self(1 << 4);
    pub const VIDEO: Self = Self(1 << 5);
    pub const APPLICATION: Self = Self(1 << 6);
    pub const LINK: Self = Self(1 << 7);
    pub const BUTTON: Self = Self(1 << 8);
    pub const TOGGLE: Self = Self(1 << 9);
    pub const NUMBER: Self = Self(1 << 10);
    pub const RADIO: Self = Self(1 << 11);

    pub fn contains(self, other: Self) -> bool;
    pub fn union(self, other: Self) -> Self;
}

pub struct GroupId(&'static str);

impl GroupId {
    pub const OPEN: Self = GroupId("open");
    pub const NAVIGATION: Self = GroupId("navigation");
    pub const EDIT: Self = GroupId("edit");
    pub const NEW: Self = GroupId("new");
    pub const MEDIA: Self = GroupId("media");
    pub const DANGEROUS: Self = GroupId("dangerous");
    pub const VIEW: Self = GroupId("view");
    pub const SELECTION: Self = GroupId("selection");
    pub fn as_str(self) -> &'static str;
}

pub struct ActionGroup {
    pub id: GroupId,
    pub order: i32,
}

pub struct ActionDescriptor {
    pub id: ActionId,
    pub group: ActionGroup,
    pub subjects: ActionSubjects,
    pub menus: &'static [MenuKind], // recommended placement; may be a submenu; not enforced
    pub icon_name: &'static str,
    pub default_shortcut: Option<&'static str>,
    pub i18n_key: &'static str,
}

pub struct ActionSpec {
    pub id: ActionId,
    pub group: ActionGroup,
    pub subjects: ActionSubjects,
    pub location: LocationScope,
    pub enabled: bool,
    pub visible: bool,
    pub checked: Option<bool>,
    pub disabled_reason: Option<DisabledReason>,
}

pub enum Effect {
    Prompt(Prompt),
    Notice(Notice),
    Reload(Vec<PathBuf>),
    Navigate(NavigationPlan),
    Frontend(FrontendRequest),
}

pub enum Prompt {
    Rename { path: PathBuf, suggested: String },
    Destroy { options: Vec<DestroyOption> },
    OpenWith { apps: Vec<AppEntry> },
    Launch { id: LaunchId, warning: LaunchWarning },
    Number { spec: NumberSpec },
}

pub enum Notice {
    OperationFailed { op: OpKind, path: PathBuf, error: OpError },
    DropsDeclined { names: Vec<String> },
    LaunchBlocked { warning: LaunchWarning },
}
```

Menu meanings:

| Menu | Purpose |
|---|---|
| `Main` | The window's main menubar. |
| `Context` | Right-click/context menu for the target. |
| `Edit` | Edit actions for the target (generic + type-specific). |
| `New` | New Folder/New Text File; may be a submenu of Edit/Context. |
| `FolderMenu` | Actions on the current folder/view itself. |
| `View` | Display/layout settings. |
| `SelectionBar` | Actions shown while a selection is active. |

Rules:

- Core decides visibility, enablement, checked state, target resolution, grouping, and
  which operation or dialog follows.
- `ActionSpec.location` is the location filter: `Folder` actions are hidden for
  `Location::File`, `File` actions are hidden for `Location::Folder`, and `Both` are
  considered for either.
- `Target` resolution:
  - `Location` means the current location/view.
  - `Focus` means the focused item; no focus means no item actions.
  - `Selection` means the active selection; an empty selection means no item actions.
  - `Items` must belong to the current folder; stale IDs are ignored.
  - `Auto` uses the selection when active and non-empty, otherwise the focus.
- `visible` means “core considers this action applicable in this context”. The frontend
  may hide, reorder, regroup, or omit any action regardless of `visible`.
- `ActionSpec` is state-only. The operation is produced by `dispatch` as an `Effect`; there
  is no separate `ActionKind` to keep in sync.
- `hishell-qt` only requests folder contexts; a file-location frontend uses the same
  registry with `Location::File`.
- **Presentation strings stay out of core.** `ActionDescriptor` carries the stable icon
  name, default shortcut, and i18n key; the frontend resolves the translated label.
  `Prompt` and `Notice` carry data, never sentences.
- Frontends call `Engine::actions(&ActionRequest)` and then `Engine::dispatch` with the
  chosen `ActionId`. `ActionManager.qml` becomes a renderer plus label table.
- `ActionId` is a stable, serializable newtype; QML can pass it back unchanged.
- `Engine::descriptor(ActionId)` returns the stable `ActionDescriptor`; the frontend
  resolves the translated label from `i18n_key` and the icon from `icon_name`.
- `disabled_reason` is a typed reason, not a string, so the frontend can show or hide a
  tooltip without parsing text.

Actions currently in `ActionManager.qml` that move:

- execute/open/open-in-new-window/open-with/navigate
- copy/cut/paste/duplicate/create-link/rename/trash
- new folder/new text file
- rotate image
- radio/toggle/number controls
- default-app setting
- quit-active
- launch confirmation

Action applicability is two-dimensional: the location kind (`Folder`/`File`/`Both`) and the
`ActionSubjects` of the target. The registry filters by both.

- Location `Both`: execute/open, open with, rename, copy, cut, duplicate, create link,
  trash, destroy, properties, go up.
- Location `File` only (the current location is a file): open, open with, rename, copy,
  trash, preview; no folder-only actions.
- Location `Folder` only: paste into, new folder, new text file, select all,
  sort/group/view settings, free placement, radio group actions.
- Item kinds inside a folder:
  - `Application` → execute/launch.
  - `File` → open using the attached file's real type; rotate image when the MIME is an
    image.
  - `Link` → open/navigate its target.
  - `Button` → trigger.
  - `Toggle` → toggle.
  - `Number` → edit values.
  - `Radio` → select within the group.
  - `Directory` → navigate.

Availability is computed from `ItemKind`, not `is_dir`. `fs_kind` only decides filesystem
operations.

Actions that remain frontend requests (core still decides visibility):

- open View sheet/dialog
- edit location text box
- show shortcuts
- open context menu

These are core actions whose effect is a `FrontendRequest`. They are distinct from
frontend-specific actions, which core does not know about.

#### 4.5.1 Menu composition and frontend actions

Core returns a recommended list; the frontend owns the final menu.

```rust
impl Engine {
    /// Core actions applicable to this menu/target, already filtered by
    /// subjects, location, item kind, and enabled state.
    pub fn actions(&self, request: &ActionRequest) -> Vec<ActionSpec>;
}
```

- The returned list is a recommendation. A frontend may hide, reorder, regroup, or omit
  any action, including `Duplicate`. Core never requires an action to be rendered.
- The frontend may add its own actions. Those are not core `ActionId`s; the adapter keeps
  a separate frontend action table and namespaces its IDs (for example
  `frontend.open-in-new-window`) so they cannot collide with core IDs.
- Invoking a core action goes through `Engine::dispatch(Command::Invoke(id))`; invoking a
  frontend action is local to that frontend.
- `ActionSubjects::HERE` actions apply to the current view/location: refresh, edit path,
  paste, select all, view/sort/group settings, go up. They do not depend on a selected
  item.
- Subject and menu are orthogonal. New Folder and New Text File are `Here` actions, but
  their recommended menu is `MenuKind::New` (and optionally `Context`). The frontend may
  render New as a top-level menu or a submenu of Edit/Context.
- Item subjects (`Folder`, `File`, `Image`, `Audio`, `Video`, `Application`, `Link`,
  `Button`, `Toggle`, `Number`, `Radio`) apply to the target item(s). The Edit menu can
  combine Here actions with item-specific actions; the frontend decides the mix.
- A type-specific action is only returned when the target matches. Rotate is an `Image`
  action; Open/Execute is `Application`; Duplicate may be `File`/`Folder`.
- `ActionDescriptor.menus` records the recommended menu placement, but the frontend is free
  to place an action elsewhere or omit it.
- Core never fails because a frontend omits an action; an action that is not rendered
  simply never reaches `dispatch`.

Example 1: for `ActionRequest { menu: Edit, target: Focus }` on an image, core may return
Copy, Cut, Duplicate, Rename, Trash (item), Rotate (image), and Open With (file). A Qt
frontend may render only Copy, Rename, Trash, Rotate, and add its own "Open in new window".
A Slint frontend may render all of them and nothing extra.

Example 2: for `ActionRequest { menu: New, target: Location }`, core returns New Folder and
New Text File. Both carry `ActionSubjects::HERE`; the menu placement is `New`, and a
frontend may also expose them under Context or a submenu.

### 4.6 `ops` and `jobs`

`hishell::ops` is synchronous and pure:

```rust
pub struct CopyOptions {
    pub overwrite: Overwrite,
    pub preserve_times: bool,
    pub follow_symlinks: bool,
}

pub struct PasteOptions {
    pub cut: bool,
    pub overwrite: Overwrite,
}

pub struct ClipboardSnapshot {
    pub paths: Vec<PathBuf>,
    pub cut: bool,
}

pub enum Op {
    Copy { sources: Vec<PathBuf>, dest: PathBuf, options: CopyOptions },
    Move { sources: Vec<PathBuf>, dest: PathBuf, options: CopyOptions },
    Link { sources: Vec<PathBuf>, dest: PathBuf },
    Paste { snapshot: ClipboardSnapshot, dest: PathBuf, options: PasteOptions },
    Rename { path: PathBuf, new_name: String },
    Trash { paths: Vec<PathBuf> },
    Destroy { paths: Vec<PathBuf> },
    Delete { paths: Vec<PathBuf> },
    NewFolder { parent: PathBuf },
    NewTextFile { parent: PathBuf },
    Duplicate { paths: Vec<PathBuf> },
    RotateImage { path: PathBuf, degrees: i32 },
    Toggle { path: PathBuf },
    Number { path: PathBuf, values: Vec<i64> },
}

pub enum OpKind {
    Copy, Move, Link, Paste, Rename, Trash, Destroy, Delete,
    NewFolder, NewTextFile, Duplicate, RotateImage, Toggle, Number, Launch,
}

pub type JobKind = OpKind;
```

Use crates where they are a clear win:

| Need | Crate |
|---|---|
| Trash | `trash` (already a dependency) |
| Recursive copy/move | `fs_extra` or `dircpy`; retain the existing cross-device fallback |
| Timestamps | `filetime` |
| Atomic writes | `tempfile` |
| Traversal | `walkdir` |
| Same-file detection | `same-file` |
| MIME | `mime_guess` (already) + `infer` |
| Archives | `zip`, `flate2`, `zstd` (already) |
| Images | `image` (already), optional `ffmpegthumbnailer` |
| Default apps/open-with | `xdg-mime` crate, or a small `mimeapps.list` reader on top of `desktop_entry.rs` |
| Portals (optional) | `ashpd` |
| File watching (optional) | `notify`; keep polling on device/vfat targets |

Do not add a crate where the existing code is already correct and project-specific
(`desktop_entry.rs`, `directory_descriptor.rs`, `launch.rs`).

`hishell::jobs`:

```rust
pub struct JobId(u64);
pub struct JobHandle { id: JobId, cancel: CancelToken }

impl JobHandle {
    pub fn id(&self) -> JobId;
    pub fn cancel(&self);
}

pub struct JobOutcome {
    pub succeeded: Vec<PathBuf>,
    pub failed: Vec<OpFailure>,
    pub declined: Vec<DeclinedDrop>,
}

pub enum JobEvent {
    Started { id: JobId, kind: JobKind },
    Progress { id: JobId, done: u64, total: u64, current: PathBuf },
    Finished { id: JobId, outcome: JobOutcome },
    Cancelled { id: JobId },
}

impl Jobs {
    pub fn submit(&self, op: Op) -> JobHandle;
    pub fn drain(&self) -> Vec<JobEvent>;
    pub fn subscribe(&self, f: impl Fn(JobEvent) + Send + 'static); // optional
    pub fn shutdown(&self);
}
```

- Use `crossbeam-channel` (already a dependency) or `std::sync::mpsc`.
- Bounded queue with N workers; `Executor` is injectable so tests can run jobs
  synchronously.
- Never block the UI thread.
- Move the current 1.5-second `report_declined_drops` wait and the execution-wrapper
  preflight onto a worker.
- Coalesce progress events so a large copy does not flood the UI thread.
- No global clipboard: `Paste` carries a `ClipboardSnapshot`.
- `JobOutcome` separates success, failure, and declined drops; partial success is a
  normal outcome, not an error string.

### 4.7 `Platform` capabilities

Platform services are split into optional capabilities instead of one god trait:

```rust
pub trait Launcher: Send + Sync {
    /// Only for apps that cannot be spawned by command (D-Bus/portal activation).
    /// Normal launches and the execution wrapper are core `hishell::execution`.
    fn activate(&self, app: &AppId, uris: &[&Path]) -> Result<(), PlatformError>;
}

pub trait AppCatalog: Send + Sync {
    fn apps_for(&self, path: &Path) -> Vec<AppEntry>;
    fn default_app(&self, path: &Path) -> Option<AppEntry>;
    fn set_default(&self, mime: &str, app: &AppId) -> Result<(), PlatformError>;
}

pub trait MimeResolver: Send + Sync {
    fn mime_type(&self, path: &Path) -> Mime;
}

pub trait Thumbnailer: Send + Sync {
    fn thumbnail(&self, request: &ThumbnailRequest) -> Result<Option<Thumbnail>, PlatformError>;
}

pub trait SoundPlayer: Send + Sync {
    fn play(&self, event: &str);
    fn set_volume(&self, volume: f32);
}

pub trait Portal: Send + Sync {
    fn open_with(&self, path: &Path) -> Result<(), PlatformError>;
    fn poll(&self) -> PortalState;
}

pub struct Platform {
    pub launcher: Option<Arc<dyn Launcher>>,
    pub apps: Option<Arc<dyn AppCatalog>>,
    pub mime: Option<Arc<dyn MimeResolver>>,
    pub thumbnails: Option<Arc<dyn Thumbnailer>>,
    pub sound: Option<Arc<dyn SoundPlayer>>,
    pub portal: Option<Arc<dyn Portal>>,
}

impl Platform {
    pub fn free_desktop() -> Self;
}
```

- The traits and the default pure-Rust FreeDesktop implementation live in
  `hishell::platform`.
- `Deps` injects `Platform`; there is no `install()` global. Tests fill only the
  capabilities they exercise.
- There are no trust roots: every `.desktop`/`.directory` entry may carry `Exec=`,
  `TryExec=`, and `Destroy=`, wherever it lives.
- `Mode::Raw` is the untrusted-media mode: it never reads entries, so no entry-supplied
  command can run.
- `hishell-qt` may supply KDE implementations for thumbnails and sound, but **not** for
  file operations or the core execution path.
- Operations return `Result`, not `bool`; `thumbnailer_dirs` is an implementation detail
  and is not exposed.
- `IconRef` does not need a trait; it is data.
- Missing capabilities have explicit fallbacks:

| Missing | Behaviour |
|---|---|
| `Launcher` | D-Bus/portal activation returns `PlatformError::Unsupported`; normal command launches still work. |
| `AppCatalog` | `apps_for` is empty, `default_app` is `None`, `set_default` is `Unsupported`. |
| `MimeResolver` | `application/octet-stream`. |
| `Thumbnailer` | `None`; the item keeps its themed/generic icon. |
| `SoundPlayer` | no-op. |
| `Portal` | `Unsupported`; open-with falls back to the app catalog. |

### 4.8 Change deltas

Core mutations return a `ChangeSet` describing what the frontend must update:

```rust
pub struct ChangeSet {
    pub location: Option<LocationDelta>,
    pub folder: Option<FolderDelta>,
    pub config: Option<ConfigDelta>,
    pub selection: Option<SelectionDelta>,
    pub focus: Option<FocusDelta>,
    pub notices: Vec<Notice>,
}

pub enum LocationDelta {
    PathChanged { from: LocationKind, to: LocationKind },
    ScanStarted,
    ScanFinished,
}

pub enum FolderDelta {
    Reset,
    Items {
        added: Vec<ItemId>,
        removed: Vec<ItemId>,
        updated: Vec<ItemId>,
        order: Vec<ItemId>, // full visible order after the change
    },
}

pub struct SelectionDelta {
    pub active: bool,
    pub selected: Vec<ItemId>,
    pub changed: Vec<ItemId>,
}

pub struct FocusDelta {
    pub pane: PaneId,
    pub item: Option<ItemId>,
    pub previous: Option<ItemId>,
}
```

- Core returns `ItemId`s, not row indices. The Qt adapter maps them to rows with
  `begin_insert_rows`/`dataChanged`/reset; Slint maps them to its own model operations.
- `FolderDelta::Items` carries the full new `order`; item payloads are read with
  `Engine::item(id)`/`item_at(path)`. `updated` lists IDs whose display data changed.
- `ConfigDelta` is the one from §4.1 and carries its `ChangeScope`.
- `Engine::dispatch` returns `Outcome`; `Engine::tick` returns `TickResult` (changes plus
  effects).
- Qt model role IDs must stay unchanged: `0x0100`–`0x0111`.

### 4.9 Input commands

Core exposes semantic operations; frontends own the event loop and mapping.

```rust
pub struct PaneId(u32);

pub enum Direction { Left, Right, Up, Down }

pub enum FocusCommand {
    First,
    Last,
    Move(Direction),
    Activate,
    Set { pane: PaneId, path: PathBuf },
}

pub struct FocusSpec {
    pub pane: PaneId,
    pub item: Option<ItemId>,
    pub columns: u32,
}

impl Focus {
    fn first(&mut self);
    fn last(&mut self);
    fn move_focus(&mut self, direction: Direction);
    fn activate(&mut self) -> Outcome;
    fn set_focus(&mut self, pane: PaneId, path: &Path);
}
```

- No key codes, gamepad buttons, pointer positions, touch states, timers, or input polling
  in core.
- Text entry: the frontend gathers the string and calls `rename(path, new_name)`. The
  Qt app uses its own rename dialog. The old ClamOS keyboard request IPC is deleted from
  the shared code; a ClamOS frontend can reintroduce it.
- Drag/drop: the frontend recognises the gesture and forwards source paths, destination,
  and `DropAction`; core validates and enqueues the operation.
- Shortcuts: the frontend binds keys to `ActionId` and calls `invoke`.
- Focus repeat/acceleration, long-press, double-click suppression, and gesture thresholds
  are frontend behaviour.

### 4.10 Execution and the execution wrapper

Execution is a service owned by `Engine`, not a set of free functions:

```rust
pub struct ExecutionWrapper {
    pub command: String,
}

pub struct LaunchId(u64);

pub enum LaunchRequest {
    Item { path: PathBuf },
    App { path: PathBuf, app: AppId },
}

pub enum LaunchOutcome {
    Started,
    NeedsConfirmation { id: LaunchId, warning: LaunchWarning },
    Blocked { reason: LaunchBlockReason },
}

pub enum LaunchEvent {
    Started { id: LaunchId },
    Exited { id: LaunchId, status: ExitStatus },
    Failed { id: LaunchId, error: LaunchError },
}

pub struct Execution {
    wrapper: Option<ExecutionWrapper>,
    pending: HashMap<LaunchId, PendingLaunch>,
    active: HashMap<PathBuf, ActiveLaunch>,
    spawner: Arc<dyn Spawner>,
}

impl Execution {
    pub fn request(&mut self, request: LaunchRequest) -> Result<LaunchOutcome, LaunchError>;
    pub fn confirm(&mut self, id: LaunchId) -> Result<(), LaunchError>;
    pub fn cancel(&mut self, id: LaunchId);
    pub fn quit(&mut self, item: &Path) -> Result<(), LaunchError>;
    pub fn poll(&mut self) -> Vec<LaunchEvent>;
}
```

`hishell::execution` owns:

- `[Layout] ExecutionWrapper` and `[Layout] Screen`.
- The `--preflight` handshake and pending-confirmation state.
- `confirm` / `cancel` by `LaunchId`.
- The `HISHELL_APP_ITEM` / `HISHELL_APP_NAME` environment contract.
- Process spawning through the injected `Spawner`.
- Launch markers, announce/withdraw, `active_items`, and `quit_active`.
- The app name/title/icon/art lookups the wrapper and launch prompt need.
- `open_with_app` choice: plain command via `desktop_entry::launch_command`; only
  D-Bus/portal activation goes through `Launcher::activate`.

The frontend only:

- renders `Effect::Prompt(Prompt::Launch { id, warning })` or `Notice::LaunchBlocked`;
- dispatches `Command::ConfirmLaunch(id)` / `Command::CancelLaunch(id)`.

Preflight and spawn run as a `JobKind::Launch` on the worker pool, so the UI never blocks
on the wrapper. Tests inject a fake `Spawner` and `Clock`.

### 4.11 `SessionStore`

Session persistence is a service, not a static mutex:

```rust
pub struct SessionStore { path: PathBuf }

pub struct SessionData {
    pub schema_version: u32,
    pub location: LocationKind, // Folder | File
    pub path: PathBuf,
    pub focus: Option<PathBuf>,
    pub history: Vec<HistoryEntry>,
    pub history_index: usize,
}

impl SessionStore {
    pub fn load(&self) -> SessionData;
    pub fn save(&self, data: &SessionData) -> Result<(), Error>;
    pub fn startup_location(&self, fallback: &Path) -> Location;
}
```

- The schema is versioned; writes are atomic (`tempfile` + rename).
- The location kind is persisted, so a file location survives a restart.
- `Engine::open` uses the store; tests use a temp directory or an in-memory implementation.

Status: `hishell::session::SessionStore` has the versioned `SessionData` schema, atomic
write, `load`, `save`, and `startup_location`. The frontend uses it for the saved path.

### 4.12 Raw mode

`Mode::Raw` is an engine policy, not a frontend flag:

```rust
pub enum Mode {
    Config, // read entries and per-folder configs
    Raw,    // ignore all on-disk config
}
```

Rules:

- `Config` is the default: entries and per-folder configs are read.
- `Raw` ignores all on-disk config: no `.desktop`, `.directory`, `.cfg`, descriptors, or
  AppImage metadata. `.desktop` files and AppImages are ordinary files.
- Items resolve to `ItemKind::File` or `ItemKind::Directory` only. Symlinks resolve to the
  target kind; a broken symlink is `File`.
- Titles are file names; icons come from the physical kind/MIME; there is no `Icon=`, no
  descriptor icon, and no generator icon.
- `Config::load_for` returns defaults only: system, per-user, and per-folder configs are
  all ignored. The engine still holds an in-memory `Config` for the session.
- `Config::set` updates memory only; `set_raw` never writes a file in raw mode.
- `RuntimeSettings` supplies the execution wrapper, screen, and default layout. If
  `default_layout` is empty, core uses a single `["./"]` pane.
- Session save/restore and navigation history still work; only entry/folder config is
  ignored.
- `descriptor_generator`, AppImage integration, and entry-driven actions are disabled.
- `Engine::set_mode` reloads the current location and returns a `ChangeSet`.
- `hishell-qt` may expose `--raw` or a menu toggle; the core behaviour does not depend on
  the frontend.

Raw mode is for untrusted media, recovery, and a plain "show me exactly what is here"
file manager.

### 4.13 Path resolution and navigation plans

Path arithmetic and transition planning are core, because they are not presentation:

`hishell::path` holds the lexical helpers (`segments`, `path_for_index`,
`folder_name`, `normalize`, `parent`, `resolve`, `exists`, `complete`) and the current
JSON-shaped `navigation_plan`. `hishell-qt`'s `PathUtils` and the qtbridge `PathBridge`
both delegate to it, so the shipping frontend and the migration target share one
implementation. The typed `NavigationPlan` below is the next step; it replaces the JSON
projection without changing the arithmetic.

```rust
pub enum NavDirection { Close, Open }

pub enum PathRelation {
    Same,
    Child { distance: usize },
    Parent { distance: usize },
    Sibling { common_ancestor: PathBuf },
    Unrelated { common_ancestor: PathBuf },
}

pub struct NavigationRequest {
    pub pane: PaneId,
    pub target: PathBuf,
    pub record_history: bool,
}

pub struct NavigationPlan {
    pub pane: PaneId,
    pub requested: PathBuf,       // the original target (file or folder)
    pub from: PathBuf,
    pub to: PathBuf,              // destination folder
    pub focus: Option<PathBuf>,   // file or item to focus after landing
    pub relation: PathRelation,
    pub common_ancestor: PathBuf,
    pub close: Vec<NavStep>,      // from `from` up to the common ancestor
    pub open: Vec<NavStep>,       // from the common ancestor down to `to`
    pub animated: bool,           // config hint; the frontend may suppress it
}

pub struct NavStep {
    pub path: PathBuf,
    pub direction: NavDirection,  // Close | Open
    pub anchor: Option<PathBuf>,  // folder whose icon the transition uses
}

pub struct SlotAnchor {
    pub item: ItemId,
    pub slot: SlotId,
    pub visible: bool,
}

impl Engine {
    pub fn relation(&self, target: &Path) -> PathRelation;
    pub fn navigation_plan(&self, request: &NavigationRequest) -> NavigationPlan;
    pub fn anchor_for(&self, pane: PaneId, path: &Path) -> Option<SlotAnchor>;
    pub fn closest_visible_parent(&self, pane: PaneId, target: &Path) -> Option<SlotAnchor>;
}
```

Rules:

- `NavigationRequest.pane` and `NavigationPlan.pane` identify the pane the transition belongs
  to; multi-pane layouts use distinct `PaneId`s.
- Path comparison is lexical by default: trailing slashes and `.`/`..` are normalized;
  symlinks are not resolved. `PathRelation` describes the path strings, not the filesystem
  layout.
- `close` lists the folders to leave, one level at a time, from the current folder up to
  the common ancestor (current first). `open` lists the folders to enter, one level at a
  time, from the common ancestor down to the destination.
- A child has an empty `close`; a parent has an empty `open`; siblings/cousins have both.
- A file target resolves to its parent folder as `to`, with `focus` naming the file or item
  to focus after landing.
- `NavStep.anchor` names the folder whose icon the transition should grow from or shrink
  into. The slot is resolved after the destination folder is loaded: `anchor_for` maps the
  path to `SlotAnchor { item, slot, visible }` against the current `ViewSpec`.
- `closest_visible_parent` finds the nearest ancestor of `target` that is visible in the
  destination folder, respecting filter, stash, and grouping. This is the "close into the
  closest visible parent" anchor.
- If no visible anchor exists (hidden, filtered, offscreen, or the destination is not
  loaded yet), `anchor_for` returns `None`; the frontend skips the icon-origin animation
  and uses a plain transition.
- `animated` reflects `SmoothScrolling`. The frontend may still suppress animation while
  another transition is running.
- The frontend owns snapshots, timing, easing, transforms, cancellation, and focus/scroll
  reveal. Core owns path relation, step order, anchor selection, and history semantics.
- `Effect::Navigate(NavigationPlan)` tells the frontend what to animate;
  `Command::Navigate(NavigationRequest)` requests the destination.

Current QML mappings:

- Move to core: `parentFolder`, `folderIndex` (as `ItemId`), `navigation_plan`, step
  composition, relation, closest-visible-parent and anchor selection.
- Keep in the frontend: `grabPanel`, `FolderTransition`, `closeIntoFolder`/
  `openIntoFolder` motion, `prepareOpenMotion`/`startOpenMotion`, `revealForTransition`,
  timing/easing, and perf logging.

### 4.14 Navigation history

History lives in core, so Back/Forward behave the same in every frontend and survive a
restart:

```rust
pub struct HistoryEntry {
    pub pane: PaneId,
    pub path: PathBuf,
    pub focus: Option<PathBuf>,
}

pub enum HistoryCommand {
    Back,
    Forward,
    Clear,
}

pub struct HistoryStatus {
    pub can_back: bool,
    pub can_forward: bool,
}

pub struct History {
    back: Vec<HistoryEntry>,
    forward: Vec<HistoryEntry>,
    current: Option<HistoryEntry>,
}

impl History {
    pub fn record(&mut self, entry: HistoryEntry);
    pub fn back(&mut self) -> Option<HistoryEntry>;
    pub fn forward(&mut self) -> Option<HistoryEntry>;
    pub fn clear(&mut self);
    pub fn status(&self) -> HistoryStatus;
}
```

Rules:

- `NavigationRequest.record_history` decides whether a completed navigation becomes a new
  entry. Back/Forward replay with `record_history = false`.
- `Engine::dispatch(Command::History(Back | Forward))` returns the destination as a
  `NavigationPlan` effect; the frontend animates it like any other navigation.
- `SessionStore` persists the back/forward stacks.
- A failed or cancelled navigation is not recorded.
- Raw and Config modes share the same history behaviour.

Status: `hishell::history::History` owns the back/forward stacks and the
oldest-to-newest snapshot used by `SessionData`. `Engine::dispatch(Command::History)` and
`Engine::history` use it; the initial location is recorded on open and `Command::Navigate`
records only when `record_history` is set. Persisting the stacks through `SessionStore`
remains for the Qt startup adapter.

## 5. Qt frontend

### 5.1 Binding migration (`qmetaobject` → `qtbridge`)

| Current | Target |
|---|---|
| `#[derive(QObject)]` + `qt_base_class!` | `#[derive(Default)]` + `#[qobject] impl` |
| `qt_property!` | `#[qproperty]` / nested property struct |
| `qt_signal!` | `#[qsignal]` |
| `qt_method!` | `#[qslot]` |
| `QAbstractListModel` | `QListModel` + `#[derive(QModelItem)]` + `QListModelBase` |
| `qml_register_type` | `QApp::register::<T>()` or `linkme` |
| `qrc!` | `include_bytes_qml!` |
| `QmlEngine` created by the caller | `QApp` |
| `QObjectBox` / `borrow_mut` | `Rc<RefCell<T>>` |
| `poll_*` | `QThreadHandle` or a poll timer |

`main.rs` becomes roughly:

```rust
fn main() {
    let path = hishell::session::startup_path(&initial_path);
    // hishell-qt is a folder file manager: a file path opens its parent folder.
    let location = hishell::Location::folder_or_parent(&path);
    let engine = Rc::new(RefCell::new(
        hishell::Engine::open_location(location).expect("open location"),
    ));
    let shell = Rc::new(RefCell::new(ShellAdapter::new(engine)));

    QApp::new()
        .register::<DirectoryAdapter>()
        .register::<ConfigBridge>()
        .register::<FileManagerAdapter>()
        .register::<FocusAdapter>()
        .register::<SelectionAdapter>()
        .set_initial_object("shell", shell)
        .load_qml_from_file("qrc:/Hishell/ShellWindow.qml")
        .run();
}
```

`hishell-qt` always constructs a folder location. `Location::folder_or_parent` resolves a
file path to its parent folder; the Qt frontend never creates `Location::File`.
`ShellAdapter` is the Qt-side root that owns `Rc<RefCell<Engine>>`; the other adapters
borrow it.

`setup_process` (icon warm-up, menu-key hook) runs after `QApp::new()` and before
`load_qml` when it is still needed. Gamepad polling and key mapping are Qt input code, not
core code.

### 5.2 Adapters

- `ShellAdapter` — Qt root adapter; owns `Rc<RefCell<Engine>>` and wires the other
  adapters.
- `DirectoryAdapter` — `QListModel` view over `Engine`'s `Folder`; applies
  `ChangeSet.folder` (`FolderDelta` → rows). Only instantiated for `Location::Folder`;
  Qt never renders a file location.
- `ConfigBridge` — mirror of `hishell::config::Config`; `apply(&Config, ConfigDelta)`.
- `FileManagerAdapter` — submits `Op` through `Engine`, holds `JobHandle`, and emits
  `job_started` / `job_progress` / `job_finished` from `JobEvent`.
- `FocusAdapter` — dispatches `Command::Focus`; key/gamepad mapping in `hishell-qt`.
- `SelectionAdapter` — mirrors `SelectionStatus`; dispatches `SelectionCommand`.
- `DragDropHandler` — frontend drag gesture state (cursor, shake, tooltip, dragged slot);
  core receives source paths, destination, and `DropAction`.
- `Input` — Qt key handlers, optional gamepad, pointer/touch, shortcut registration, and
  text-entry IPC. Translates frontend events into `Command`/`ActionId`.
- `DropValidator` / `PathUtils` — deleted; core exposes the decisions directly.

### 5.3 QML changes

**Native KDE:**

- Use `Kirigami.Theme`, `Kirigami.Units`, `Kirigami.Icon`, and Qt Quick Controls with the
  Breeze style.
- Keep `Hishell/Theme/Kde.qml` as a thin facade (it already maps Kirigami) to avoid
  rewriting every `Theme.*`/`Units.*` reference at once.
- Set `QT_QUICK_CONTROLS_STYLE=org.kde.breeze` (or `QQuickStyle` in a small init) for
  native-looking controls.
- Delete `CoreTheme.qml`, `Theme/Clamos.qml`, `StyleThemeBridge.qml`.
- Delete `Theme/Icon.qml` and `ThemeIcons`; use `Kirigami.Icon` with `IconRef::Theme`, and
  `Image`/`Kirigami.Icon` with `IconRef::Path`.

**Replace custom widgets:**

| Remove | Replace with |
|---|---|
| `toolkit/ViewButton.qml` | `QQC.Button` / `QQC.ToolButton` / `Kirigami.Action` |
| `toolkit/ViewDialog.qml` | `QQC.Dialog` / `Kirigami.Dialog` |
| `toolkit/ViewMenu.qml` | `QQC.Menu` / `Kirigami.MenuDialog` driven by core actions |
| `toolkit/ViewSlider.qml` | `QQC.Slider` |
| `toolkit/ViewActions.qml` | core action registry + QQC controls |
| `SegmentedButtons*.qml` | `QQC.TabBar` or a Kirigami segmented control |
| `ToggleSwitch.qml` | `QQC.Switch` |
| `Sheet.qml` | `Kirigami.OverlaySheet` / `QQC.Dialog` |
| `WindowOverlay.qml`, `toolkit/WindowControl.qml` | native KDE titlebar |
| `FocusBorder.qml` | ordinary focus rectangle / `Rectangle` |

**ClamOS-specific removals:**

- `src/topscreen.rs`.
- `focus_manager::publish_focus`, `publish_focus_now`, `published_focus`, `focus_file`.
- `FolderView.qml` `topScreenFocusTimer` and the 2-second republish timer.
- `theme/default/focus-border.svg` and the SVG parsing/recolouring code in
  `focus_manager` (`BORDER_SOURCES`, `corner_elements`, `group_paint`, `inherit_paint`,
  `recolour`, `write_border_asset`, etc.).
- `kde_bridge::{accent_icon, set_icon_theme, warm_icons, render_pending_icon,
  has_pending_icons}` and the matching C++ functions.
- `src/theme_icons.rs`.
- `CoreTheme.accentFolderIcon` and the `FileSlot.qml` recolouring fallback.

### 5.4 Async QML contract changes

These methods change from "do the work and return bool/string" to "submit and report".
The adapter submits an `Op` through `Engine`, holds the returned `JobHandle`, and turns
`JobEvent` into signals.

| Method | New behaviour |
|---|---|
| `copy_file` | submit job; `job_finished` |
| `duplicate_file` | submit job; `job_finished` |
| `new_folder` / `new_text_file` | submit job; `job_finished` |
| `create_link` | submit job; `job_finished` |
| `trash_file` / `delete_file` | submit job; `job_finished` |
| `rotate_image` | submit job; `job_finished` |
| `paste_from_clipboard` | submit job; `job_finished` |
| `process_uris_action` | submit job; `job_finished` + `drop_declined` |
| `rename_file` | submit job; `job_finished`; keep synchronous validation |
| `quit_active` / `confirm_launch` / `cancel_launch` | core execution service; adapter delegates; completion via job/notice |
| `open_with_app` | submit; completion notice |

Keep synchronous:

- `can_*`, `is_*`, `get_mime_type`, `get_text_content` (size-capped),
  `rename_display_name`, `number_spec`, `launch_warning`, `get_default_app`,
  `get_open_with_apps`, `get_icon`, `get_item_title`, `perf_mode`.

Removed from the shared code: the ClamOS keyboard request IPC (`keyboard_available`,
`request_text_entry`, `poll_text_entry`, `cancel_text_entry`) is deleted. The Qt app
renames through its own dialog; a ClamOS frontend can reintroduce the IPC.

Update `ActionManager.qml` call sites (about 20) from:

```qml
if (fm.trash_file(path)) { ... }
```

to:

```qml
fm.trash_file(path);
// completion arrives in onJobFinished, or in a dedicated signal
```

Add a submitted/completed signal pair per operation, or one generic
`job_finished(id, outcome: JobOutcome)`. The adapter serializes the typed outcome; core
never produces JSON or error strings.

## 6. Module map

| Current file | Lines (approx.) | Target |
|---|---:|---|
| `src/config.rs` | 1219 | `hishell::config` + `hishell-qt::adapters::config` |
| `src/config_parser.rs` | 334 | `hishell::config::parser` |
| `src/directory.rs` | 2941 | `hishell::location::Folder` + `hishell-qt::adapters::directory` |
| `src/file_manager.rs` | 1858 | `hishell::ops` + `hishell-qt::adapters::file_manager` |
| `src/focus_manager.rs` | 1480 | `hishell::focus` state + `hishell-qt::input` mapping |
| `src/selection_manager.rs` | 159 | `hishell::location::Selection` + `hishell-qt::adapters::selection` |
| `src/dragdrop_handler.rs` | 255 | `hishell-qt::input` (frontend drag state) |
| `src/drop_validator.rs` | 71 | `hishell::drop` |
| `src/path_utils.rs` | 305 | `hishell::path` + `hishell::navigation` |
| `src/desktop_entry.rs` | 1235 | `hishell::desktop` |
| `src/directory_descriptor.rs` | 316 | `hishell::descriptor` |
| `src/descriptor_generator.rs` | 779 | `hishell::descriptor::generator` (optional) |
| `src/thumbnailer.rs` | 856 | `hishell::thumbnail` + platform override |
| `src/launch.rs` | 398 | `hishell::execution` |
| `src/session.rs` | 193 | `hishell::session::SessionStore` |
| `src/appimage.rs` | 259 | `hishell::appimage` |
| `src/squashfs.rs` | 529 | `hishell::squashfs` |
| `src/image_utils.rs` | 51 | `hishell::image` |
| `src/destroy.rs` | 219 | `hishell::ops::destroy` |
| `src/keyboard.rs` | 228 | delete (ClamOS keyboard IPC) |
| `src/gamepad.rs` | 325 | `hishell-qt::input` (optional) |
| `src/sound.rs` | 134 | platform + Qt adapter |
| `src/theme_icons.rs` | 78 | delete |
| `src/topscreen.rs` | 622 | delete |
| `src/kde_bridge.rs` / `.cpp` | 467 + C++ | shrink to Qt-only hooks |
| `src/lib.rs` | 185 | rewrite as `hishell-qt` app entry |
| `src/main.rs` | 86 | rewrite for `QApp` |

## 7. Phased plan

Each phase must leave the app runnable. Merge phases separately.

### Phase 0 — Repository split and removals

1. Add `IrisHormoviti/hishell` as a submodule at `hishell/`.
2. Move pure modules into the submodule; re-export them from `src/lib.rs` while the Qt
   code migrates.
3. Keep `build.rs` in `hishell-qt`; it only builds the remaining Qt hooks.
4. Delete `topscreen.rs`, `publish_focus`, `topScreenFocusTimer`, and the republish timer.
5. Delete `CoreTheme.qml`, `Theme/Clamos.qml`, `StyleThemeBridge.qml`.
6. Delete `src/keyboard.rs`, the `FileManager` keyboard request methods, and the
   `ActionManager.qml` keyboard rename polling. Rename always uses the Qt dialog.
7. Keep `Theme/Kde.qml`/`Units.qml` as the native-KDE facade for now.
8. Update `.qmlls.ini`, `project.qmlproject`, `.qmlproject`, README, AGENTS.

Checkpoint:

- `cargo run -- /tmp` works.
- No top-screen output.
- The app uses the normal KDE theme.
- Rename uses the Qt dialog; no `keyboard_available`/`poll_text_entry` calls remain.
- `cargo tree -p hishell` has no Qt dependencies.

### Phase 0.5 — `qtbridge` spike

1. Branch from Phase 0.
2. Port one singleton (`ConfigBridge` or a tiny test singleton).
3. Port `Directory` as a `QListModel` with the existing role names.
4. Load the bridge QML through `include_bytes_qml!` and `load_qml_from_file`.
5. Verify nested `directory.config`.
6. Deliver one worker event through `QThreadHandle`.
7. Build aarch64 and x86_64.
8. Confirm `build.rs`/moc for the remaining Qt hooks coexists.
9. Assess `plugins.qmltypes`/qmlls loss.

The spike passed; the bridge became the `hishell-qt` binary and the `qmetaobject`
frontend was removed.

#### Spike results

x86_64 is green. The spike crate proved, on Qt 6.11 / qtbridge 0.4.1:

- a `#[qobject(Singleton)]` singleton reachable from QML;
- a `#[qobject(Base = QListModel)]` list model with camelCase roles consumed by a
  `ListView` delegate;
- a nested object property (`directory.config.gridLines`);
- one worker event delivered on the Qt thread through `QThreadHandle::invoke_mut`;
- embedded QML through `include_bytes_qml!` and `load_qml_from_file("qrc:/res/qml/Main.qml")`;
- `QApp::register`, `set_initial_object`, and the model notification helpers.

aarch64 is blocked for cross builds. qtbridge supports Linux on x86_64 only, and a
cross build from x86_64 needs a host-side qmake for the target Qt. With the ClamOS
`forky-aarch64` sysroot, qtbridge finds Qt only through a path-rewriting qmake wrapper,
and then fails running the target `moc` because the binfmt qemu entry does not load the
sysroot's `ld-linux-aarch64.so.1`. A native aarch64 build (device or an arm64 CI runner)
remains untested.

`qtbridge` does not generate `plugins.qmltypes`, so qmlls loses Rust type information for
the ported adapters. The crate is LGPL-3.0-only or commercial; the repository still has no
license file.

`QModelItem` supports at most 15 fields. The existing `Directory` exposes 18 roles, but
QML delegates read exactly 15 of them; `group_index`, `group_label`, and `is_stashed` are
unused and move out of the model.

`include_bytes_qml!` stores the path exactly as written, so `..` ends up in the resource
name. QML embedded from a sibling directory must live under the invoking source directory
(or be passed a normalised path).

Decision: `qtbridge` is the shipping frontend. The `qmetaobject` app was deleted rather
than kept as a fallback. aarch64 remains a release-pipeline gate.

### Phase 1 — Engine facade, Config, and view layout

1. Create `hishell::Engine`, `Deps`, `Mode`, `OpenOptions`, `Command`, `Outcome`, and
   `ChangeSet`; delete the process-global platform/launch/session entry points.
2. Move config parsing/validation/writing into `hishell::config`.
3. Implement `ConfigKey`, `ConfigValue`, `ConfigLoad`, `ConfigDelta`, and `ChangeScope`.
4. Implement the config scope table and `Config::load_for(Location)`.
5. Implement `ViewSpec` as `Folder(FolderView)`/`File(FileView)`, `ViewRequest`, and
   `FolderView.revision`/`SlotSpec.id`.
6. Implement both grid sizing modes from §4.2.1 (`LINES` and `SIZE`).
7. Move grid/list metric math from `FolderGrid.qml` and `LayoutEngine.qml`.
8. Make `ConfigBridge` a mirror; QML reads the typed `ViewSpec`.

Status:

- Implemented in `hishell`: `Engine`/`Deps`/`Mode`/`OpenOptions`/`RuntimeSettings`/
  `Command`/`Outcome`/`TickResult`, `ConfigKey` (40 keys with section, scope, default, and
  change scope), `Config`, `ConfigLoad`, `ConfigDelta`, `ConfigDiagnostic`, typed enums,
  `Location` (`Folder`/`File`), `ViewSpec` (`FolderView`/`FileView`), `GridSizing`,
  `GridSpec`, list/sort/group/interaction specs, and the `LINES`/`SIZE` grid math.
- Tests cover defaults, section/scope lookup, deltas, invalid enums, config precedence,
  two engines in one process, raw mode, a file location, and both grid modes.
- The qtbridge frontend mirrors `hishell::Config` through `ConfigBridge`, feeds its grid
  from `Engine::view`, and routes view controls through `ConfigKey`.
- The shipping `Directory` adapter is backed by `Engine`; `ConfigBridge` mirrors
  `hishell::Config` and the view spec comes from `Engine::view`. No separate config or
  scan implementation remains in the frontend.

Checkpoint:

- View menu changes mode, grid lines, grid size, alignment, sorting, grouping.
- `LINES` keeps the line count and varies icon size; `SIZE` keeps the icon size and
  varies the line count; old configs stay in `LINES`.
- Grid and list modes match current behaviour.
- Free placement and grouped layouts still work.
- Edited `.cfg` files hot-reload.
- `ConfigKey` is the single source of truth for parsing, validation, and the View menu.
- Core tests cover a file location: `ViewSpec::File` has no sort/group/slots, and
  `hishell-qt` still opens the parent folder for a file argument.
- No process-global state remains.

### Phase 1.5 — Platform capabilities and execution service

1. Add `hishell::platform` capability traits (`Launcher`, `AppCatalog`, `MimeResolver`,
   `Thumbnailer`, `SoundPlayer`, `Portal`) and the `Platform` aggregate.
2. Implement `Platform::free_desktop`.
3. Inject `Platform` through `Deps`; remove `install()` and other globals.
4. Add `hishell::execution::Execution` with `LaunchId`, `PendingLaunch`, `Spawner`, and
   `Clock`; keep the execution wrapper, `--preflight`, confirm/cancel, environment,
   spawning, launch markers, and `quit_active` in it.
5. Replace `kde_bridge` calls in the moved core modules with capability calls.
6. Keep only the Qt-specific hooks in `hishell-qt`.

Checkpoint:

- Launch, open-with, default app, MIME, and clipboard work without KDE in the core path.
- The execution wrapper, preflight, confirm/cancel, and spawn work from core; the frontend
  only renders prompts and forwards confirmation.
- `cargo tree -p hishell` still has no Qt dependencies.
- File operations do not call the platform layer.
- Tests inject fake `Platform`, `Spawner`, and `Clock` implementations.

Status:

- `hishell::platform` defines `Launcher`, `AppCatalog`, `MimeResolver`, `Thumbnailer`,
  `SoundPlayer`, `Portal`, and the `Platform` aggregate. `Platform::free_desktop` supplies
  the pure-Rust MIME resolver, application catalog, and cached image thumbnailer; missing
  capabilities use the documented fallbacks.
- `FreeDesktopApps` scans the XDG application directories and reads `mimeapps.list` for
  default applications. `set_default` writes the user `mimeapps.list`; the last `gio`
  subprocess is therefore gone from the core path.
- `hishell::execution` owns `Execution`, `LaunchId`, the wrapper, `--preflight`,
  confirm/cancel, `HISHELL_APP_*`/`HISHELL_SCREEN`, launch markers, active launches, and
  `quit`. `Spawner` and `Clock` are injectable.
- `Engine` exposes `Command::Launch`, `ConfirmLaunch`, `CancelLaunch`, `QuitActive`, and
  returns `Effect::Launch` / `Effect::LaunchEvent`.
- The frontend launches through `Engine::Invoke`/`Execution`; the old `launch.rs` and
  `kde_bridge` adapters are gone.

### Phase 2 — Core `Location` and `Folder`

Status: a minimal scan is in core. `hishell::folder::Folder` lists a directory into
`Item`s (`name`, `path`, `fs_kind`, `kind`, `mime`, `icon`, sizes/times, symlink and
dotfile flags), sorts directories first, and applies the configured sort. `Engine` keeps
the folder, exposes `items`/`item`/`item_at`, and fills `FolderView.slots` from the
resolved grid (or list row height). `ItemId` is derived from the path, so ids survive a
rescan while the path remains.

Selection lives in the folder (`Selection`): `select_only`, `toggle`, `range_to`,
`select_all`, `clear`, and `retain`, with the visible order as the range order. `Engine`
exposes `selection()` and dispatches `SelectOnly`, `ToggleSelection`, `SelectRange`,
`SelectAll`, `ClearSelection`, and `SetSelectionActive`. A reload carries the selection
over and drops ids that left the folder. The qtbridge frontend renders the items, slots,
and selection.

`.desktop` items read their `[Desktop Entry]` metadata: `Name`, `Comment`, `Icon`,
`Type`, `NoDisplay`/`Hidden`, `Path`/`URL`, and `Exec`. The icon resolves to a theme name
or a path relative to the entry, and plain files get an icon from their MIME type.

`Engine::dispatch(SetConfig)` applies the key's `ChangeScope`: order-only keys re-sort the
folder, item keys rescan, and view keys only bump the revision. The qtbridge frontend
drives view mode, grid mode, lines, icon size, and labels through that path.

Plain-file icons no longer shell out to `gio`: `hishell::icon` maps extensions with
`mime_guess`, sniffs extensionless files with `infer`, and returns the themed icon name.
`directory::get_icon` uses it after the entry, AppImage, descriptor, and generator lookups.
Image detection uses the same core MIME resolver; the frontend's duplicate `image_utils`
module is gone. `gio mime` remains only in the default-application setter until
`AppCatalog` lands.

Themed lookups resolve the process icon theme to one that exists on disk. The Breeze
style can leave `QIcon::themeName()` at an internal name with no `index.theme`, which made
`KIconLoader` return null icons; `init_icon_theme` and the accent-icon renderer fall back
to `breeze`/`breeze-dark` (by palette) or `hicolor`.

Entry parsing resolves `Type=Application|Link|Directory|Button|Toggle|Number|Radio|File`.
A folder's `.directory` can make it an Application, Link, or control; a `Type=File`
descriptor or `<file>.desktop` sidecar attaches its `Name`/`Comment`/`Icon`/`MimeType` to
the file and is not listed itself. Unknown types and invalid targets produce diagnostics.
`ScanOptions` carries raw mode and the hidden-entry policy.

`Folder::apply_config` sorts by the configured key/date/name modes and assigns display
groups (date, letters, type, custom, stash). `Engine::view` returns grouped slots and header
rects, and free-placement slots when `Sort = FREE`. Free positions are persisted through
`SetFreePosition`, `SetFreePositions`, `RenameFreePosition`, and `ResetFreePositions`.
Radio membership and value helpers live in core; invoking the radio command belongs to the
execution service. Folder changes carry `FolderDelta::Reset` or an order-only `Items` delta,
and the qtbridge adapter applies them to its rows.

AppImage metadata and directory/file descriptors live in core: `appimage` reads the
embedded desktop entry and extracts its icon, `descriptor` indexes XDG and runtime
descriptor roots, and `Folder::scan` applies both when no `.directory` exists.
`descriptor_generator` discovers `hishell/descriptor-generators`, runs `Exec %i/%o` on a
worker, caches entries plus stamps, and `Folder::scan` queues requests and applies finished
results. `Directory::poll_descriptors` refreshes the panes when a batch completes.

1. Move `Item`, scan, sort, group, filter, slots, radio, icon resolution.
2. Add `Location`, `Folder`, `File`, `ItemId`, `Location::from_path`, and
   `Location::folder_or_parent`.
3. Put `Selection` inside `Folder`; the visible order is `Vec<ItemId>`.
4. Introduce `IconRef` and update the scan/icon code.
5. Add `EntryType`, `ItemKind`, `FsKind`, and `Item::kind`/`fs_kind`/`target`/`entry_path`.
6. Resolve `Type=Application|Link|Directory|Button|Toggle|Number|Radio|File`. A folder
   with `Application`/`Link` acts as that kind. `Type=File` merges `Name`/`Icon`/`Comment`/
   `MimeType` into its file, or uses `Path=` as a descriptor for a specific file in a
   general location; `Exec=` is invalid.
7. Implement `Mode::Raw`: ignore all on-disk config and resolve items to `File`/`Directory`
   only.
8. Make `DirectoryAdapter` a `QListModel` over `Folder`; apply `ChangeSet.folder`
   (`FolderDelta`) to rows.
9. Keep role IDs unchanged.
10. Preserve the deferred-load ordering in `finish_path_change`.
11. Remove `query_gio_icon` and all `gio` shell-outs; resolve plain-file icons from
    `mime_guess`/`infer` plus the built-in MIME→icon table.

Checkpoint:

- Navigation, refresh, hidden/stash, grouping, free placement, radio groups.
- Icons: theme names and file paths both resolve.
- AppImage/descriptor icons still appear.
- `Location::File` carries one item, MIME, metadata, and thumbnail; no scan, listing,
  sort, group, slots, or selection.
- `hishell-qt` resolves a file argument to its parent folder and never shows a file
  location.
- Selection/focus/slots use `ItemId`, not row indices.
- Entry types resolve correctly, including a folder acting as `Application`/`Link` and a
  `Type=File` entry attached to a file or pointing at one via `Path=`.
- Raw mode produces only `File`/`Directory` items and ignores layout/folder config.
- No `gio` subprocess is spawned for icons.

### Phase 2.5 — Path resolution and navigation plans

1. Move lexical path helpers from `path_utils.rs` into `hishell::path`:
   normalization, segments, parent/ancestor, join, relative, `is_under`.
2. Add `PathRelation`, `NavigationRequest`, `NavigationPlan`, `NavStep`, `SlotAnchor`,
   and `NavDirection`.
3. Move `navigation_plan` and the close/open step composition from QML/Rust.
4. Implement `anchor_for` and `closest_visible_parent` against `ViewSpec`/`Folder` (filter,
   stash, grouping aware). `NavStep.anchor` names the path; the slot resolves after the
   destination folder is loaded.
5. Resolve a file target to its parent folder plus a `focus` item.
6. Change `Effect::Navigate` to carry a `NavigationPlan`.
7. Keep snapshots, timing, easing, transforms, cancellation, and focus/scroll reveal in
   the frontend.

Status:

- `hishell::navigation` defines `PathRelation`, `NavigationRequest`, `NavigationPlan`,
  `NavStep`, `NavDirection`, and `SlotAnchor`.
- `Engine::relation`, `navigation_plan`, `anchor_for`, and `closest_visible_parent` query
  them; `Command::Navigate`/`Command::GoUp` reload the destination and return
  `Effect::Navigate(plan)`. `anchor_for` resolves against the last `Engine::view` result.
- The JSON helper in `hishell::path::navigation_plan` projects the typed plan for
  frontends that want a string result; it is not a second plan implementation. The
  qtbridge `PathBridge` exposes it.
- The qtbridge `FolderPane` animates the pane from the `NavigationPlan` relation returned by
  `Directory::navigate`/`go_up`; typed plans remain the contract.
- Tests cover same/child/parent/sibling/unrelated relations, child/parent/cousin steps, a
  file target landing in its parent with a focus, navigation effects, and anchor lookup.

Checkpoint:

- Child, parent, sibling, cousin, and unrelated paths produce the expected close/open
  steps.
- Root, trailing-slash, `.`/`..`, and relative inputs are normalized consistently.
- Opening a folder grows from its icon; closing shrinks into its closest visible parent;
  hidden/filtered anchors fall back to a plain transition.
- A file target lands in its parent folder with the file focused.
- The QML animation looks the same; only the plan computation moved to core.

### Phase 3 — `ops`, `jobs`, and execution

1. Move file operations into `hishell::ops`.
2. Add the chosen crates (`fs_extra`, `filetime`, `tempfile`, `infer`, ...).
3. Add `Jobs`, `JobHandle`, `JobOutcome`, `JobEvent`, explicit `Op` options, and
   `ClipboardSnapshot`.
4. Convert `FileManagerAdapter` methods to submit + signals.
5. Update `ActionManager.qml` call sites.
6. Move declined-drop waiting and execution preflight off the UI thread.

Status:

- `hishell::ops` implements copy, move (with a cross-device copy+remove fallback), link,
  paste, rename, trash, delete, new folder, new text file, duplicate, rotate image, toggle,
  and number updates. `Destroy` reports `Unsupported` until provider commands move into
  execution.
- `hishell::jobs` runs the operations on a bounded worker pool with `JobEvent`s and
  `CancelToken`; `Jobs::drain` is the frontend pump.
- `Engine::dispatch(Command::Run)` submits an operation, `Command::CancelJob` cancels it,
  and `Engine::tick` returns `Effect::Job` events.
- Tests cover copy trees, overwrite refusal, move/duplicate/rename/new/delete, cancellation,
  worker completion, and the engine job pump.

The frontend submits file operations through `Engine::Invoke` and `Command::Run`; jobs
run on `hishell::Jobs` and `Engine::tick` delivers their events. The qtbridge `Directory`
refreshes its rows after a job and resets the model. Rename, trash/delete confirmation,
open-with, and drag/drop copy/move/link are QML dialogs and `Directory` slots over those
core commands.
The frontend reads and writes its saved location and focus through
`hishell::session::SessionStore`; the ClamOS handover markers were removed with the legacy
frontend.

Checkpoint:

- Long copy/move/trash does not freeze the UI.
- Drop into a virtual folder reports declined names.
- Rename, duplicate, link, new folder, new text file, rotate, paste all work.
- Jobs are cancellable through `JobHandle`.
- No KDE calls in the operation path.

### Phase 4 — Core `Selection` and `Actions`

Status: selection state is in core (`Folder::selection`, `SelectionCommand` values in
`Engine::dispatch`). `hishell::action` defines `ActionId`, `ActionGroup`, `ActionSubjects`,
`ActionRequest`, `Target`, `MenuKind`, `ActionDescriptor`, and `ActionSpec`, with a static
descriptor table. `Engine::actions` resolves Focus/Selection/Items/Auto targets, filters by
location scope, subjects, and recommended menu, and reports `enabled`/`disabled_reason`.
`Command::Invoke(ActionId)` routes open/navigate/trash/delete/new folder/new text
file/refresh/go-up/select-all/duplicate/create-link/rotate/toggle/quit-active through the
engine, and rename/open-with/destroy/number return typed `Prompt` effects. Unimplemented
actions return `FrontendRequest`. The qtbridge `Directory` exposes
`actions_json(menu, target)` and `invoke(action)`; the QML context menu is built from
`Engine::actions` and dispatches `Command::Invoke`. Rename, trash/delete, and open-with
prompts open Qt dialogs; the old `CoreActions`/`ActionManager.qml` renderer is gone.

1. Move selection state and range/toggle semantics; dispatch `SelectionCommand`.
2. Add `ActionId` newtype, `ActionDescriptor`, `ActionRequest`, `MenuKind` (including
   `Edit` and `New`), `Target`, `ActionSubjects`, `ActionSpec`, and `Outcome`.
3. Move enablement/visibility/checked logic from `ActionManager.qml`; filter per-item
   actions by `ItemKind`, including `Application`, `Link`, `Button`, `Toggle`, `Number`,
   and `Radio`.
4. Separate `ActionSubjects::HERE` (refresh, edit path, paste, select all,
   view/sort/group) from item subjects (`Folder`, `File`, `Image`, `Audio`, `Application`,
   ...). New Folder/New Text File are Here actions recommended under `MenuKind::New`.
5. Implement `Engine::actions` and action invocation; replace string effects with typed
   `Prompt`/`Notice`.
6. Return a recommended menu; allow the frontend to hide, reorder, omit, or add its own
   actions without core failing.
7. Keep labels/icons/shortcuts in QML keyed by `ActionId`/`ActionDescriptor.i18n_key`.
8. Replace `ActionManager.qml` with a renderer plus label table.

Checkpoint:

- Menus, context menus, selection bar, and shortcuts invoke the same actions.
- Action enablement matches current behaviour.
- Here actions and item-specific actions are separated; Image/Audio/Folder/File actions
  only appear for the matching target.
- New Folder/New Text File are `Here` actions recommended in the New menu; the frontend
  can render New as a top-level menu or a submenu.
- The Qt frontend can omit `Duplicate` and add a frontend-specific action; core still works.
- `qsTr()` labels still translate.
- Prompts and notices are typed; core emits no formatted sentences.
- `disabled_reason` is available for tooltips.

### Phase 5 — Core `Focus` state

Status: `hishell::focus` owns per-pane state (`PaneFocus`: order, columns,
horizontal/free-placement positions, empty-slot cursor, and geometry) and the navigation
math. `FocusCommand` carries `Register`, `Release`, `ActivatePane`, `SetOrder`,
`SetPositions`, `SetGrid`, `SetGeometry`, `SetEmptySlots`, `SetIndex`, `SetCursor`,
`First`, `Last`, `Move`, `Set`, `Clear`, and `Activate`. `Engine::dispatch(Command::Focus)`
keeps pane 0 in sync with the folder and returns `FocusDelta`; `FocusCommand::Activate`
returns `Effect::FocusActivate`. The qtbridge `Directory` exposes `focus_first`,
`focus_last`, `move_focus`, and `focus_path` over these commands and publishes
`focused_path`; the QML delegate draws a plain focus rectangle. The two panes each own a
core `Focus`; the adapter hands input to the other pane when the core reports no movement.

1. Move pane state, navigation math, and status strings.
2. Remove top-screen publishing.
3. Keep key/gamepad mapping, repeat/acceleration, and drag gesture state in `hishell-qt`.
4. Core exposes `first`/`last`/`move_focus`/`activate`/`set_focus` and `DropAction`
   validation.
5. Keep `window`, `dragged_slot`, and other view handles in the adapter.

Checkpoint:

- Semantic focus navigation and pane switching work.
- Qt key/gamepad mapping drives those commands; core has no input polling.
- Drag gesture recognition stays in Qt; core receives and validates the drop action.
- Multi-pane navigation and focus-visible scrolling still work.

### Phase 6 — Native KDE UI cleanup

Status: done. The frontend uses Qt Quick Controls and `Kirigami.Icon`; `theme_icons.rs`,
`Theme/Icon.qml`, the focus-border SVG and parser, the accent-icon renderer, the custom
`View*`/`SegmentedButtons` stack, and the `kde_bridge` C++ hooks are deleted. The focus
border is a plain Qt rectangle.

The frontend now runs on qtbridge:

- `src/main.rs` is the `hishell-qt` binary and is built with plain
  `cargo build`.
- It mirrors the full folder config through `ConfigBridge`, exposes `Directory` as a
  15-role `QListModel`, uses `QThreadHandle` for the reload worker, and loads its QML from
  an embedded resource.
- `Directory` rows come from `Engine::items`, and `view_json` returns the slot/grid
  layout from `Engine::view`; the QML sizes its `GridView` from that result and renders
  free-placement slots at the core's rectangles.
- Selection is dispatched back into `Engine` and mirrored as `selectionActive`,
  `selectedCount`, and `selectionRevision` for QML.
- View controls dispatch `SetConfig` and re-read the spec; grid and list modes both render.
- `PathBridge` exposes the core path helpers.
- The focus border is a plain `Rectangle` in the QML delegate; there is no SVG parser.
- The old `qmetaobject` binary and its QML are gone.

1. Render with Qt Quick Controls instead of `ViewButton`, `ViewDialog`, `ViewMenu`,
   `ViewSlider`, `ViewActions`, `SegmentedButtons*`, `ToggleSwitch`, `Sheet`,
   `WindowOverlay`, and `WindowControl`. Done.
2. Use a plain focus rectangle instead of `FocusBorder`. Done.
3. Use `Kirigami.Icon` for `IconRef::Theme` and image loading for `IconRef::Path`. Done.
4. No `theme_icons.rs`, `Theme/Icon.qml`, or accent-icon C++. Done.
5. No focus-border SVG or Rust parser. Done.
6. No `kde_bridge` presentation functions. Done.
7. Rely on the host's Qt Quick Controls style (Breeze on KDE). Done.

Checkpoint:

- The app looks like a native KDE application.
- No ClamOS theme files are read.
- Icons resolve correctly for both theme names and file paths.
- Bundle still contains all required QML modules.

### Phase 7 — Slint frontend (later)

Out of scope. The core APIs above are the contract.

## 8. Verification

### Automated

- Run `HISHELL_QT_BIN=target/debug/hishell-qt scripts/smoke-test.sh`; it checks startup,
  session persistence, thumbnails, and a descriptor generator end to end.
- Run `HISHELL_QT_BIN=target/debug/hishell-qt scripts/ui-test.sh`; it drives rename,
  trash, and open-with dialogs, drag/drop copy, cross-pane hand-off, the `NavigationPlan`
  transition, and gamepad focus movement.

- `cargo test -p hishell` for config parsing, scan, sort, group, layout, selection,
  actions, icon refs, and ops.
- Move the existing 74 `#[test]` functions out of QObject modules into core modules.
- Add golden tests:
  - `Engine::open_with` with fake `Deps` (`Platform`, `Spawner`, `Clock`, `Executor`,
    `SessionStore`); two `Engine` instances in one process prove there are no globals.
  - `Engine::item`/`item_at` and `FolderDelta::Items.order` reconstruct the visible list
    and updated payloads after a rescan.
  - `tick` returns effects for a finished job/launch; `dispatch` and `tick` both carry
    changes.
  - A launch held for confirmation returns a `LaunchId`, and `Prompt::Launch` carries the
    same id through `Command::ConfirmLaunch`.
  - `.cfg` parse/validate/write, `ConfigKey` schema, and `ConfigLoad` diagnostics.
  - `ViewSpec` for grid/list/free/grouped at several viewports; `FolderView.revision`
    changes and `SlotSpec.id` stays stable across reorders.
  - Grid sizing: `LINES` keeps the line count and varies icon size; `SIZE` keeps the
    icon size and varies line count; default/absent `GridMode` stays in `LINES`; `Lines = 0`
    means 4; `GridSize` is ignored in `LINES` and `Lines` is ignored in `SIZE`.
  - `IconRef` for absolute path, relative path, `file://`, bare name, missing file.
  - Action enablement matrix for selection/focus/target combinations, including
    folder-only vs file-applicable scopes; `ActionRequest` menus and `Target`.
  - Menu composition: `ActionSubjects::HERE` vs item subjects; Image/Audio/Folder/File
    filtering; New Folder is `Here` with a recommended `New` menu; a frontend omitting
    Duplicate or adding a frontend-specific action does not affect core.
  - Focus navigation using semantic commands (`first`, `last`, `move_focus`, `activate`),
    not key codes.
  - Pane focus: per-pane order, columns, free-placement positions, empty-slot cursor, and
    edge hand-off.
  - `Location::from_path` for a folder, a file, and a symlink to each.
  - `PathRelation` for same/parent/child/sibling/cousin/unrelated, including root,
    trailing-slash, `.`/`..`, and relative inputs.
  - `NavigationPlan` close/open steps for each relation; a file target lands in its parent
    with `focus` set; `closest_visible_parent` respects filter/stash/grouping and falls
    back when no anchor is visible.
  - Icons resolve without `gio` for common extensions, extensionless files via `infer`,
    and unknown types via the fallback table.
  - Entry resolution for `Type=Application`, `Link`, `Directory`, `Button`, `Toggle`,
    `Number`, `Radio`, and `File`.
  - `Type=File` attaches its `Name`/`Icon`/`Comment`/`MimeType` to the file when attached,
    and uses `Path=` as a descriptor for a specific file in a general location. It is not
    listed as a separate item, and `Exec=` is ignored with a diagnostic.
  - A `Type=File` descriptor's copy/rename/trash act on `path`; `RemoveDescriptor` acts on
    `entry_path`.
  - Every entry's `Exec=`/`TryExec=`/`Destroy=` is honoured wherever it lives;
    `Mode::Raw` ignores entries entirely.
  - `GroupId`/`ActionGroup` order is data-driven; a new group appears without changing an
    enum.
  - A folder carrying `Type=Button/Toggle/Number/Radio` acts as that control while
    `fs_kind` stays `Directory`.
  - History records completed navigations, Back/Forward replay without recording, and
    `SessionStore` restores the stacks.
  - A folder with `Type=Application` or `Type=Link` acts as that kind while `fs_kind`
    stays `Directory`.
  - Raw mode ignores `.desktop`/`.directory`/`.cfg`/descriptors/AppImage metadata; items
    resolve to `File`/`Directory` only and the default layout applies.
  - Execution wrapper: preflight message, confirm/cancel, `HISHELL_APP_*` environment,
    `quit_active`, and no UI-thread block.
  - `JobHandle` cancellation, `JobOutcome` partial success, and explicit `Op` options.
  - Typed `Prompt`/`Notice` payloads; core never formats a sentence.
  - Copy/move/trash/link on a temp directory.
- Add a headless `hishell` example/CLI that opens a folder, prints the sorted items,
  runs a copy/trash, and exits. This is the core smoke test.

### Manual

- `timeout 30s cargo run -p hishell-qt -- /tmp` and inspect.
- Large folder on a slow target.
- Grid and list modes; the View menu changes mode, sizing (lines or icon size),
  lines/size, labels (including beside icons), list columns and their header,
  sorting, grouping, alignment, and stash and persists in General scope or the
  folder's `.directory` in Here scope.
- Grouped and stash views draw their section headers in both grid and list modes;
  the absolute grouped/free layout scrolls.
- A selection toolbar appears at the bottom of a pane while selection mode is
  active, with a tristate select-all box, the count, and Deselect.
- Typing filters the current folder; a filter bar above the view shows the text
  and match count, Backspace trims it, Escape clears it, and the view scrolls
  into the first match.
- Free placement repositions items by dragging them to another cell and persists
  `FreePlacementPositions` in the folder's `.directory`.
- Hovering a folder during a drag navigates into it (spring loading) while the
  platform drag icon stays with the pointer. The dragged folder itself never
  spring-loads, and drag sources dim instead of moving.
- Drags use Qt's platform drag image (`Drag.imageSource`), so the drag icon is
  drawn by the compositor rather than by an in-window ghost.
- The menu bar shows the old context groups: Open and Edit when there is a target,
  Image for an image target, Folder for a folder target, and New and View always.
- Here → Configure edits the layout JSON, window flags, folder title/icon, radio,
  and launch settings.
- With `OpenOnClick` (the old default), a plain click opens; press-and-hold enters
  selection mode and selects the item. Ctrl-click toggles, Shift-click ranges, Space
  toggles the focused item, Escape clears. Arrow keys move the focus rectangle; only the
  active pane draws it.
- Double-click/Return opens a folder; Backspace/Alt+Up goes up.
- New folder/new text, rotate, and toggle through the context menu.
- Trash/delete confirmation, rename, and open-with dialogs.
- Drop onto a breadcrumb to move the dragged items into that folder. The self
  test also exercises the breadcrumb drop handler on the current build.
- Right-clicking the background shows the Here actions plus the old New and
  View submenus, including the full View menu.
- Item and background menus expose Copy/Cut/Paste, Properties, and Open in New
  Window where applicable.
- Drag a file/folder onto another folder to copy, move, or link it. Drags use
  Qt's `Drag.Automatic` on every platform, with no native-drag special case.
  Same-folder and folder-into-itself drops are no-ops, existing destinations are
  never overwritten, and a failed move leaves the source in place.
- With `--features gamepad`, gamepad directions, accept, cancel, menu, select, and
  directory map to the same focus/navigation/selection actions.
- Free placement renders each slot at its stored cell.
- The Header/Top/Middle/Bottom arrays from `.cfg` are loaded through `LayoutEngine`.
- The path bar shows breadcrumbs; clicking the current crumb opens the here menu, and
  Ctrl+L edits the location in place.
- The menu bar exposes Edit/New/View and the old shortcuts (F2, Delete, F5,
  Alt+Up, Ctrl+Shift+N, Ctrl+A, Ctrl+O, Ctrl+W, …).
- A middle layout with two `./` entries keeps independent folders; an arrow at a pane
  edge hands focus to the other pane.
- Opening a folder scales the pane content in; closing it scales out, using the core
  `NavigationPlan` relation.
- A plain path, a `file://` URI, and a file argument all open the right folder.
- The saved session path restores on the next start.
- Icons and titles: themed names, file paths, cached image thumbnails, AppImage
  embedded entries/icons, and XDG directory/file descriptors.
- A file owned by a descriptor generator gets its generated title and icon after the
  descriptor poll.

Each `./` entry in the Middle layout becomes a `FolderPane` over its own
`Directory`/`Engine`; the default layout has one, and two entries create two panes.
Each pane's focus is core `Focus`; the edge hand-off is frontend input mapping.
`Directory::navigate` and `go_up` return the core `NavigationPlan` as JSON, and the pane
animates from its relation.

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| `qtbridge` is pre-1.0 and API may change | Pin the version; keep the core boundary stable |
| `qtbridge` aarch64 Linux is not officially listed | Build the spike on aarch64 before committing |
| `qtbridge` requires Qt 6.10+ private headers | Confirmed on target; verify CI and sysroot |
| `qtbridge` does not generate `plugins.qmltypes` | qmlls has no Rust type metadata; the core API and QML are small enough to keep in sync manually |
| `qtbridge` license (LGPL-3.0/commercial) | Add a LICENSE file; review static-linking compliance |
| `fs_extra` cross-device behaviour | Keep the existing copy+delete fallback; test on vfat/SD |
| QML translation breaks when actions move | Keep labels in QML keyed by `ActionId` |
| Icon resolution regressions | Pure-Rust `mime_guess`/`infer` table; `IconRef` tests; no `gio` process |
| `ViewSpec` parity with current QML math | Golden tests against current screenshots/metrics |
| Transition-plan regressions | Golden `NavigationPlan` tests plus a visual open/close checklist |
| Icon resolution without `gio` differs | Pure-Rust MIME table with `infer` fallback; tests for common and extensionless files |
| Model reset flashes | Keep row deltas and the deferred-delete ordering |
| Drag/drop lifetime crashes | Keep the existing deferred reload contract; never reset the model from inside a drag handler |
| Native KDE look differs | Accepted; ClamOS look moves to the Slint frontend |

## 10. Rollback

- Phase 0 can be reverted by dropping the submodule and restoring the moved files.
- `master` retains the old `qmetaobject` app; the `qtbridge` branch is the thin frontend.
- Each core phase is behind a working frontend, so a failed phase can be reverted without
  losing the previous ones.
- `hishell` can be versioned independently once the split stabilises.

## 11. Definition of done

- `cargo tree -p hishell` contains no Qt, Slint, KDE, or C++ dependencies.
- `hishell` contains one `Engine` facade that owns config, view layout, folder/file
  locations, selection, actions, and file operations. It contains no input handling and no
  process-global platform/launch/session state.
- The public API is typed: `ViewSpec::{Folder,File}`, `ConfigKey`, `ActionRequest`,
  `Prompt`/`Notice`, `JobHandle`/`JobOutcome`. Core returns structs, not JSON or formatted
  sentences.
- Core recommends menu contents but the frontend decides what to render; it may omit,
  reorder, or add its own actions, and `Here`/item subjects keep view actions separate from
  Image/Audio/Folder/File actions. Subject and menu placement are independent: New Folder
  is a `Here` action recommended in the New menu.
- Entry types are a superset of freedesktop: `Application`, `Link`, `Directory`, plus
  `Button`, `Toggle`, `Number`, `Radio`, and `File`. A folder can act as `Application` or
  `Link`; a `Type=File` entry supplies metadata for its attached file or a `Path=`
  descriptor for a specific file in a general location.
- `Mode::Raw` ignores all on-disk config and resolves items to `File`/`Directory` only.
- Platform capabilities are injected through `Deps`; tests use fakes.
- Execution and the execution wrapper live in `hishell::execution`; the frontend only
  renders prompts and forwards confirmation/cancellation.
- `hishell-qt` contains only adapters, QML, input handling, and Qt-only hooks.
- File operations run on workers and never block the UI thread.
- The frontend uses native KDE widgets, theme, and icons.
- The ClamOS keyboard request IPC is gone; rename uses the Qt dialog.
- `topscreen`, the ClamOS theme backend, the focus-border SVG, and the
  `View*`/`SegmentedButtons` widgets are gone.
- Icons resolve correctly as either theme names or absolute paths, with no `gio`
  subprocess.
- Path relations and navigation plans live in core; the frontend only snapshots and
  animates them.
- Navigation history lives in core and `SessionStore` restores it.
- `Type=File` descriptor actions act on the target file; `RemoveDescriptor` is separate.
- Every `.desktop`/`.directory` entry may execute `Exec=`/`TryExec=`/`Destroy=`;
  `Mode::Raw` ignores entries entirely.
- Action grouping is data-driven (`GroupId` + `ActionGroup { id, order }`).
- A directory may carry `Type=Button/Toggle/Number/Radio`; `fs_kind` remains `Directory`.
- The app runs with `cargo run -p hishell-qt -- /tmp` and passes the manual checklist.
- A future Slint frontend can depend on `hishell` without touching Qt.

## 12. Migration status

| Phase | State | Remaining |
|---|---|---|
| 0 — repository split | done | — |
| 0.5 — qtbridge spike | done on x86_64 | — |
| 1 — Engine, config, view | done (core + qtbridge) | — |
| 1.5 — platform and execution | done (core + FreeDesktop) | — |
| 2 — Location and Folder | done (core + qtbridge) | — |
| 2.5 — navigation plans | done (typed plans; legacy JSON shim) | — |
| 3 — ops, jobs, execution | done | — |
| 4 — selection and actions | done | — |
| 5 — focus state | done | — |
| 6 — native KDE cleanup | done | — |

The "Remaining" column is empty: the pure `hishell` core plus the `qtbridge` frontend is
the whole crate. `qmetaobject`, the ClamOS theme stack, and the old QML are deleted.
aarch64 certification remains a release-pipeline gate: no aarch64 cross toolchain is part
of this checkout.

## 14. External release gates

- **aarch64 core.** With `gcc-aarch64-linux-gnu` and `sysroot-aarch64-*-glibc`
  installed, `cargo build --target aarch64-unknown-linux-gnu` in `hishell/` succeeds.
  Build with `CFLAGS="" CXXFLAGS=""` when a user config injects host include paths.
- **aarch64 frontend.** `qtbridge` needs an aarch64 target sysroot with Qt 6.10+
  development files and libudev; the Fedora cross sysroot has glibc but neither, so the
  frontend build stops in `libudev-sys`. This is a release-pipeline certificate, not a
  source change. x86_64 is green.

## Appendix A — Deletion checklist

Removed during the migration:

- [x] `src/topscreen.rs`
- [x] `src/keyboard.rs`
- [x] `query_gio_icon` and every `Command::new("gio")` / GLib icon shell-out
- [x] `FileManager::{request_text_entry, poll_text_entry, cancel_text_entry, keyboard_available}`
- [x] `focus_manager::publish_focus`, `publish_focus_now`, `published_focus`, `focus_file`
- [x] `CoreTheme.qml`
- [x] `Theme/Clamos.qml`
- [x] `StyleThemeBridge.qml`
- [x] `FolderView.qml` top-screen timers
- [x] `ActionManager.qml` keyboard rename flow (`renameRequest`, `finishKeyboardRename`,
      `renameTimer`, `poll_text_entry`, `cancel_text_entry`, `keyboard_available`)
- [x] regenerate `plugins.qmltypes` after removing the keyboard methods

Removed with the `qmetaobject` frontend:

- [x] focus-border SVG parsing/recolouring functions
- [x] `src/theme_icons.rs`
- [x] `kde_bridge` and its C++ hooks
- [x] `Theme/Icon.qml`
- [x] `toolkit/ViewButton.qml`
- [x] `toolkit/ViewDialog.qml`
- [x] `toolkit/ViewMenu.qml`
- [x] `toolkit/ViewSlider.qml`
- [x] `toolkit/ViewActions.qml`
- [x] `SegmentedButtons.qml`, `SegmentedButtonsGeneric.qml`, `SegmentedButtonsStyle.qml`
- [x] `ToggleSwitch.qml`
- [x] `Sheet.qml`
- [x] `WindowOverlay.qml`
- [x] `toolkit/WindowControl.qml`
- [x] `FocusBorder.qml`
- [x] `theme/default/focus-border.svg`
- [x] `ActionManager.qml`, `FolderView.qml`, and the rest of the `Hishell/` tree

## Appendix B — Frontend modules

The frontend is:

- `src/main.rs` — `ConfigBridge`, `Directory`, `PathBridge`, and the
  `QApp` entry point.
- `src/qml/Main.qml` — the window and its Header/Top/Middle/Bottom layout engines.
- `src/qml/LayoutEngine.qml` — loads the configured layout entries.
- `src/qml/FolderView.qml` — one pane: Qt Quick Controls, the file-operation
  dialogs, and the `NavigationPlan` transition.
- `src/qml/FolderGrid.qml` — the grid, list, grouped, and free-placement views,
  their geometry, selection input, and drag/drop wiring.
- `src/qml/FileSlot.qml` — the slot rendering: icon/thumbnail (gallery-sized
  when labels are hidden), label faces and hover tooltip, selection and focus,
  selection check badges, drop highlight, control/radio plates, and the toggle
  switch.
- `src/qml/DragPreview.qml` and `src/qml/DragTooltip.qml` — the free-placement
  reposition ghost and its action tooltip.
- `src/qml/toolkit/PathBar.qml` — breadcrumbs with a slash between segments and
  the current item's icon; the current crumb opens the Here menu, which carries
  the Configure submenu.
- `src/qml/toolkit/MenuBar.qml` — Open/Edit/New menus with icons and shortcuts.
- `src/qml/toolkit/ViewMenu.qml` — the whole View menu, including its General/Here
  scope tabs, view mode, sizing mode, lines or icon size, list columns, sorting,
  grouping, labels, arrangement, navigation, wallpaper, and stash settings.
- `src/qml/toolkit/ConfigureDialog.qml` — layout, window, folder, radio, and launch
  settings reached from Here → Configure.
- `src/gamepad.rs` — gilrs polling adapted to `Directory` focus commands; built with
  `--features gamepad` so a host without libudev development files can still build.

### Spring-loaded drag

Qt Quick's drag source is the delegate `QQuickItem`. Spring navigation replaces
the folder rows and would destroy that item while Qt owns the drag. The
frontend now uses a small native `DragHelper` singleton (`native/draghelper.*`)
that owns the `QDrag` and survives the view change, like the old
`DragDropHandler`. Hovering a folder during a drag navigates into it, and the
drag continues so the drop completes there. The drag pixmap is the slot's
cached `grabToImage` result; the helper reads the grab result itself because
its URL uses the `itemgrabber` scheme, not a file path.

Free-placement drags of items already in the folder stay in the window as a
reposition gesture, like the old `DragPreview`: the selection follows the
cursor as a ghost, the `DragTooltip` shows `Reposition`, and the drop writes the
moved block plus any displaced occupants through `set_free_positions`. If the
gesture leaves the window it hands the same selection over to the platform
drag, as the old `handOffRepositionDrag` did.

During a platform drag the helper polls the cursor and keyboard modifiers, so
the `DragTooltip` follows the pointer and switches between `Copy`, `Move`, and
`Link` like the old `DragDropHandler`.

Dragging near a view edge scrolls it, faster closer to the edge, for both the
platform drag and the in-window reposition gesture. A horizontal
`ScrollDirection` uses the old `GridView.TopToBottom` flow with its edge scroll
along X; other modes scroll along Y.

`NativeDrag` keeps the old choice: by default the window draws the dragged
slot as an in-window ghost and the platform drag gets no pixmap; with
`NativeDrag=true` the ghost is hidden and the platform provides the drag
image. The ghost keeps its grab alive on the window, so spring navigation can
replace the view without losing the image.

`Directory.activeRevision` mirrors the old `focusManager.active_revision`:
a two-second refresh asks the core's execution state which items have a
running/suspended app and bumps the revision when that set changes. Grid and
free slots draw the old blinking radial active-app glow behind the icon; the
list keeps the old list layout, which had no glow.

The old `FocusBorder.qml` is ported as one shared instance in `FolderGrid`
instead of a border per slot. It uses the old bracket path and stroke, follows
the focused grid cell, list row, or free slot via `Directory.row_index`, and
keeps the two-breath pulse. The per-slot focus rectangle is gone; the old
active/selection wash sits behind the content.

`FocusEmptySlots` is wired through `Directory.focusOnEmpty`, `focusColumn`, and
`focusRow`. `view_json` feeds the core focus state its order, positions, grid
extent, and empty-slot setting, and the shared border draws over the empty free
cell the cursor rests on, like the old `onEmpty` path.

The border host keeps the old `moving` gate: the first appearance jumps to the
slot, later moves animate x/y for 160 ms with `Easing.OutCubic`. It also hides
while the user drags or flicks the view (`moving`/`flicking`), like the old
`!grid.userScrolling` condition.

Focus changes also run the old `ensureFocusVisible`: the view centres the cursor
when `CenterFocus` is on, otherwise scrolls only when it falls outside the
viewport. Geometry comes from the layout, not the delegate, so a lazy view can
reveal an item it has not built. `SmoothScrolling` animates the scroll for
110 ms with `Easing.OutCubic`.

The empty free-placement background behaves like the folder background: left
click clears selection and cursor; right click opens the copied
`ShellContextMenu` Here/New/View menu with the folder as target.

Scrolling the viewport runs the old `keepFocusInView` behaviour: a partially
clipped focused slot moves the cursor to the fully visible item nearest its
centre, without scrolling back. A 60 ms follow timer throttles wheel/flick
updates, and `movementEnded` settles it immediately.

`openFocusedMenu` is the shared context-menu path for the Menu key, Shift+F10,
and the gamepad menu button: an item gets its item actions, while focus on an
empty slot gets the folder Here/New/View menu.

Drop hover matches the old FileSlot: entering a folder arms the spring-load
timer, `onPositionChanged` keeps it alive when the drag started already inside,
and leaving clears it. A source folder rejects hovering itself or one of its
descendants before arming the timer, as the old drop validator did.

Free placement disables the per-folder DropArea, like the old FileSlot. Its
background DropArea tracks the folder under the pointer, springs into it on
hover, and resolves an external drop to that folder; same-folder drops remain
repositions. This was verified with a two-pane drag from a grid pane into a
free-placement folder.

The gamepad directory button opens the folder Here/New/View menu, matching the
old `directory_menu_requested`; it no longer selects everything.

### Clipboard, properties, and new windows

- Copy/Cut/Paste use a frontend clipboard holding a `ClipboardSnapshot`; Paste
  submits `Op::Paste` into the current folder with overwrite disabled.
- Properties opens a metadata dialog with name, path, type, size, modified time,
  and MIME type.
- Open in New Window starts another frontend process for the folder (or the
  file's parent folder).
- Drag sources stay in place and dim while the platform drag is active.

The old QML tree, `sound.rs`, and the frontend copies of `appimage.rs`,
`directory_descriptor.rs`, `descriptor_generator.rs`, and `thumbnailer.rs` were removed.
`appimage`, `descriptor`, `descriptor_generator`, and `thumbnail` now live in the core;
`gamepad.rs` remains in the frontend.

## Appendix C — API conventions

### Normative vs illustrative types

Normative types (the contract):

- `Engine`, `Deps`, `OpenOptions`, `RuntimeSettings`, `Mode`, `Command`, `Outcome`,
  `TickResult`.
- `Config`, `ConfigKey`, `ConfigValue`, `ConfigLoad`, `ConfigDelta`, `ConfigDiagnostic`,
  `LocationScope`.
- `Location`, `Folder`, `File`, `Item`, `ItemId`, `IconRef`, `Entry`, `EntryType`,
  `FsKind`, `ItemKind`.
- `ViewRequest`, `ViewSpec`, `FolderView`, `FileView`, `GridSizing`, `GridSpec`,
  `FolderMode`.
- `Selection`, `SelectionStatus`, `SelectionCommand`.
- `ActionRequest`, `ActionSpec`, `ActionDescriptor`, `ActionSubjects`, `GroupId`,
  `ActionGroup`, `MenuKind`, `Target`, `ActionId`.
- `Effect`, `Prompt`, `Notice`.
- `Op`, `JobHandle`, `JobOutcome`, `JobEvent`, `JobId`.
- `Platform` and its capability traits.
- `ChangeSet`, `FolderDelta`, `ConfigDelta`, `SelectionDelta`, `FocusDelta`,
  `LocationDelta`.
- `NavigationRequest`, `NavigationPlan`, `NavStep`, `NavDirection`, `PathRelation`,
  `SlotAnchor`, `PaneId`.
- `SessionStore`, `SessionData`.
- `History`, `HistoryEntry`, `HistoryCommand`, `HistoryStatus`.
- `LaunchRequest`, `LaunchOutcome`, `LaunchEvent`, `LaunchId`, `ExecutionWrapper`.

Supporting value types:

```rust
pub struct Mime(pub String);
pub struct MetadataRow { pub label: String, pub value: String }
pub enum Preview { None, Image, Text, Thumbnail, Custom }
pub struct Thumbnail { pub path: PathBuf, pub size: u32 }
```

Supporting types defined in core:

- `SortSpec`, `GroupingSpec`, `LabelSpec`, `InteractionSpec`, `ListSpec`, `AppId`,
  `AppEntry`, `DisabledReason`, `LaunchWarning`, `LaunchBlockReason`, `OpFailure`,
  `DeclinedDrop`, `ExitStatus`, `FrontendRequest`.

Frontend-only or future types:

- `NumberSpec`, `DestroyOption`, `DialogKind`, `LayoutDiagnostic`, `Diagnostics`,
  `Executor`, `DropAction`.

### Errors

- Use typed errors: `ConfigError`, `OpError`, `LaunchError`, `PlatformError`,
  `NotAFolder`, `NotFound`, `StaleItem`.
- Return `Result<T, E>`; do not return `bool` or error strings.
- Partial success is a normal `JobOutcome`, not an `Err`.

### Threading and ordering

- `Engine` is UI-thread-only and not `Sync`.
- `dispatch` is synchronous; `Op`/launch work is asynchronous.
- `tick` drains events in FIFO order.
- Every worker event carries the location generation that produced it; stale events are
  ignored after a navigation.
- Cancellation is best-effort; a finished event may still arrive and must be safe to drop.
- `Op`, `Platform`, and owned snapshots are `Send`.

### Versioning

- `ActionId` strings and config keys are stable; new ones are additive.
- `SessionData.schema_version` is bumped on incompatible changes.
- Growable public enums are `#[non_exhaustive]`.
- Public types are exported through a `prelude`; the crate follows semver once the split
  stabilises.

### Security

- `Exec=`, `TryExec=`, and `Destroy=` are executable behaviour carried by any entry.
  There are no trust roots; use `Mode::Raw` for untrusted media.
- `Mode::Raw` never reads entries, so it never executes entry-supplied commands.
- Descriptor `Path=` targets are outside the descriptor's own folder; actions that delete
  must be explicit about whether they act on the target or the descriptor.

## Appendix D — Resolved decisions

1. **Navigation history lives in core.** `History` owns the back/forward stacks and
   `SessionStore` persists them.
2. **`Type=File` descriptor actions act on the target file** (`path`). `RemoveDescriptor`
   is a separate action on `entry_path`.
3. **All entries may execute.** `Exec=`, `TryExec=`, and `Destroy=` are honoured
   wherever the entry lives; `Mode::Raw` ignores entries entirely.
4. **Action grouping is data-driven.** `GroupId` + `ActionGroup { id, order }`; new groups
   do not require an enum change.
5. **Control types are allowed on folders.** A directory may carry `Type=Button`,
   `Toggle`, `Number`, or `Radio`; `fs_kind` remains `Directory`.
