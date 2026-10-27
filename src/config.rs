use crate::config_parser::{ConfigError, ConfigParser, ConfigValue, ParseOutput};
use once_cell::sync::Lazy;
use qmetaobject::prelude::*;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

/// A desktop entry larger than this is not an entry: the spec's files are a few
/// kilobytes, and the header sniff below has to open the file. Without a size
/// gate, scanning a folder of ROMs opened every multi-megabyte file to read
/// 512 bytes just to discover it is not a desktop entry.
const MAX_ENTRY_SNIFF_LEN: u64 = 256 * 1024;

/// A parsed desktop entry / folder config, keyed by the path it was loaded for.
/// Every view asks the same entry for its type, icon and name several times per
/// item (title, icon, control kind, ...); each ask used to re-read and re-parse
/// the default config, the system config, the user config and the entry itself.
/// A folder of a thousand files paid that thousands of times per scan and again
/// for every delegate the view created.
///
/// The stamp is the item's own mtime/size (and a directory's `.directory`
/// stamp), so an entry rewritten in place is picked up without an invalidation
/// call. The map is small and bounded: entries are tiny, and a listing only
/// holds a folder's worth at a time.
type EntryStamp = (u64, u64, bool, u64, u64);
static ENTRY_CACHE: Lazy<Mutex<HashMap<PathBuf, (EntryStamp, HashMap<String, ConfigValue>)>>> =
	Lazy::new(|| Mutex::new(HashMap::new()));
const ENTRY_CACHE_LIMIT: usize = 8192;

fn file_stamp(path: &Path) -> (u64, u64, bool) {
	match std::fs::metadata(path) {
		Ok(meta) => {
			let modified = meta
				.modified()
				.ok()
				.and_then(|time| time.duration_since(UNIX_EPOCH).ok())
				.map(|duration| duration.as_nanos() as u64)
				.unwrap_or(0);
			(modified, meta.len(), meta.is_dir())
		}
		Err(_) => (0, 0, false),
	}
}

fn entry_stamp(path: &Path) -> EntryStamp {
	let (modified, len, is_dir) = file_stamp(path);
	let (dir_modified, dir_len) = if is_dir {
		let (modified, len, _) = file_stamp(&path.join(".directory"));
		(modified, len)
	} else {
		(0, 0)
	};
	(modified, len, is_dir, dir_modified, dir_len)
}

/// Returns the config / desktop entry file associated with a given path.
/// - For a directory, this is `<path>/.directory`.
/// - For a `.desktop` file (or `.directory` file), this is the file itself.
/// - Otherwise, returns None.
fn has_desktop_entry_header(path: &Path) -> bool {
	use std::io::Read;
	if let Ok(mut file) = std::fs::File::open(path) {
		let mut buf = [0u8; 512];
		if let Ok(n) = file.read(&mut buf) {
			let slice = &buf[..n];
			let text = String::from_utf8_lossy(slice);
			for line in text.lines() {
				let trimmed = line.trim_start_matches('\u{feff}').trim();
				if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with(';') {
					continue;
				}
				return trimmed == "[Desktop Entry]";
			}
		}
	}
	false
}

pub fn entry_path(path: &Path) -> Option<PathBuf> {
	if path.is_dir() {
		Some(path.join(".directory"))
	} else if path
		.extension()
		.and_then(|ext| ext.to_str())
		.is_some_and(|ext| {
			ext.eq_ignore_ascii_case("desktop")
				|| ext.eq_ignore_ascii_case("directory")
				|| ext.eq_ignore_ascii_case("cfg")
		}) || path
		.file_name()
		.and_then(|n| n.to_str())
		.is_some_and(|n| n.eq_ignore_ascii_case(".directory"))
	{
		Some(path.to_path_buf())
	} else if path
		.metadata()
		.is_ok_and(|meta| meta.is_file() && meta.len() <= MAX_ENTRY_SNIFF_LEN)
		&& has_desktop_entry_header(path)
	{
		Some(path.to_path_buf())
	} else {
		None
	}
}

/// Returns the base directory for resolving relative paths (icons, wallpapers, working dir)
/// associated with a given path.
/// - For a directory, this is the directory itself.
/// - For a file, this is its parent directory (or current directory if none).
pub fn base_dir(path: &Path) -> &Path {
	if path.is_dir() {
		path
	} else {
		path.parent().unwrap_or(Path::new("."))
	}
}

/// Loads and combines the default config with a target path's desktop entry / `.directory` config,
/// keeping track of which file each value came from and any load errors.
pub fn load_path_checked(path: &Path) -> ParseOutput {
	let Some(override_path) = entry_path(path) else {
		return ParseOutput {
			sections: HashMap::new(),
			origins: HashMap::new(),
			errors: Vec::new(),
		};
	};
	load_with_override(&override_path)
}

/// Loads desktop-entry metadata with the same defaults and validation as folder configs.
#[allow(dead_code)]
pub fn load_entry_checked(path: &Path) -> ParseOutput {
	load_path_checked(path)
}

/// System-wide config files, lowest priority first.
///
/// `XDG_CONFIG_DIRS` lists directories with the leftmost having the highest
/// priority, but `ConfigParser` lets later files override earlier ones, so the
/// list is reversed. The spec's default is `/etc/xdg`. This gives a host a place
/// for device policy (ClamOS sets its `ExecutionWrapper` here) while the bundled
/// `config/default.cfg` stays generic and the user's
/// `$XDG_CONFIG_HOME/hishell/folder.cfg` can still override both.
fn system_config_paths() -> Vec<PathBuf> {
	let dirs = std::env::var("XDG_CONFIG_DIRS")
		.ok()
		.filter(|value| !value.is_empty())
		.unwrap_or_else(|| String::from("/etc/xdg"));
	system_config_paths_from(&dirs)
}

fn system_config_paths_from(dirs: &str) -> Vec<PathBuf> {
	let mut paths: Vec<PathBuf> = dirs
		.split(':')
		.filter(|dir| !dir.is_empty())
		.map(|dir| Path::new(dir).join("hishell").join("folder.cfg"))
		.collect();
	paths.reverse();
	paths
}

fn default_config_path() -> PathBuf {
	PathBuf::from("config/default.cfg")
}

fn global_config_path() -> PathBuf {
	dirs::config_dir()
		.map(|mut p| {
			p.push("hishell");
			p.push("folder.cfg");
			p
		})
		.unwrap_or_else(default_config_path)
}

/// The config files shared by every entry: the bundled defaults, the system
/// policy and the user's global folder.cfg. They do not depend on the item
/// being loaded, so parsing them once per entry re-read and re-parsed the same
/// five kilobytes for every file in a folder. Cached with a stamp of their
/// sizes and mtimes so an edit on disk is still seen.
static BASE_CONFIG: Lazy<Mutex<Option<(u64, ParseOutput)>>> = Lazy::new(|| Mutex::new(None));

fn base_config_stamp(paths: &[PathBuf]) -> u64 {
	let mut stamp = 0u64;
	for path in paths {
		let (modified, len, _) = file_stamp(path);
		stamp = stamp
			.wrapping_mul(1099511628211)
			.wrapping_add(modified ^ len.rotate_left(17));
	}
	stamp
}

fn base_config() -> ParseOutput {
	let default_cfg = default_config_path();
	let global_cfg = global_config_path();
	let system_cfg = system_config_paths();
	let mut paths: Vec<PathBuf> = Vec::with_capacity(2 + system_cfg.len());
	paths.push(default_cfg);
	paths.extend(system_cfg);
	paths.push(global_cfg);

	let stamp = base_config_stamp(&paths);
	if let Ok(cache) = BASE_CONFIG.lock()
		&& let Some((cached_stamp, output)) = cache.as_ref()
		&& *cached_stamp == stamp
	{
		return output.clone();
	}

	let path_refs: Vec<&Path> = paths.iter().map(PathBuf::as_path).collect();
	let output = ConfigParser::parse_files(&path_refs);
	if let Ok(mut cache) = BASE_CONFIG.lock() {
		*cache = Some((stamp, output.clone()));
	}
	output
}

fn load_with_override(override_path: &Path) -> ParseOutput {
	let mut output = base_config();
	let over = ConfigParser::parse_files(&[override_path]);
	for (key, origin) in over.origins {
		output.origins.insert(key, origin);
	}
	for (section, items) in over.sections {
		for (key, value) in items {
			output
				.sections
				.entry(section.clone())
				.or_default()
				.insert(key, value);
		}
	}
	output.errors.extend(over.errors);
	output
}

pub fn load_entry(path: &Path) -> HashMap<String, ConfigValue> {
	let stamp = entry_stamp(path);
	if let Ok(cache) = ENTRY_CACHE.lock()
		&& let Some((cached_stamp, value)) = cache.get(path)
		&& *cached_stamp == stamp
	{
		return value.clone();
	}

	let value = load_entry_uncached(path);
	if let Ok(mut cache) = ENTRY_CACHE.lock() {
		if cache.len() >= ENTRY_CACHE_LIMIT {
			cache.clear();
		}
		cache.insert(path.to_path_buf(), (stamp, value.clone()));
	}
	value
}

fn load_entry_uncached(path: &Path) -> HashMap<String, ConfigValue> {
	let mut load = load_path_checked(path);
	let mut errors = std::mem::take(&mut load.errors);
	errors.extend(validate_values(&load.sections, &load.origins));
	for error in errors {
		eprintln!("{}", error.message);
	}
	load.sections.remove("Desktop Entry").unwrap_or_default()
}

pub fn string_value(value: &ConfigValue) -> Option<String> {
	match value {
		ConfigValue::String(value) => Some(value.clone()),
		ConfigValue::Number(value) => Some(value.to_string()),
		_ => None,
	}
}

/// Reads a string option, falling back to `default`.
fn opt_string(value: Option<&ConfigValue>, default: &str) -> String {
	match value {
		Some(ConfigValue::String(v)) => v.clone(),
		_ => default.to_string(),
	}
}

/// Reads an upper-cased enum option, falling back to `default`.
fn enum_value(value: Option<&ConfigValue>, default: &str) -> String {
	opt_string(value, default).to_uppercase()
}

/// Reads a boolean option, falling back to `default`.
fn bool_value(value: Option<&ConfigValue>, default: bool) -> bool {
	match value {
		Some(ConfigValue::Boolean(b)) => *b,
		_ => default,
	}
}

/// Reads an integer option, falling back to `default`.
fn num_value(value: Option<&ConfigValue>, default: i32) -> i32 {
	match value {
		Some(ConfigValue::Number(n)) => *n as i32,
		_ => default,
	}
}

/// Reads an array / dictionary option as its JSON form, falling back to `default`.
fn json_value(value: Option<&ConfigValue>, default: &str) -> String {
	match value {
		Some(v @ ConfigValue::Array(_)) | Some(v @ ConfigValue::Dictionary(_)) => {
			v.to_json_string()
		}
		_ => default.to_string(),
	}
}

pub fn entry_string(values: &HashMap<String, ConfigValue>, key: &str) -> Option<String> {
	values.get(key).and_then(string_value)
}

/// Loads and combines the default config with a folder's `.directory` config.
pub fn load_path(path: &Path) -> HashMap<String, HashMap<String, ConfigValue>> {
	load_path_checked(path).sections
}

enum ExpectedKind {
	Str,
	StrEnum(&'static [&'static str]),
	Bool,
	Num,
	Array,
	Dict,
}

/// Every key the `Config` object reads, with the kind of value it expects.
const EXPECTED_KEYS: &[(&str, &str, ExpectedKind)] = &[
	("Desktop Entry", "Name", ExpectedKind::Str),
	("Desktop Entry", "Comment", ExpectedKind::Str),
	("Desktop Entry", "Type", ExpectedKind::Str),
	("Desktop Entry", "Exec", ExpectedKind::Str),
	("Desktop Entry", "URL", ExpectedKind::Str),
	("Desktop Entry", "Icon", ExpectedKind::Str),
	("Desktop Entry", "DynamicIcon", ExpectedKind::Str),
	("Desktop Entry", "Terminal", ExpectedKind::Bool),
	("Desktop Entry", "NoDisplay", ExpectedKind::Bool),
	("Layout", "Top", ExpectedKind::Array),
	("Layout", "Middle", ExpectedKind::Array),
	("Layout", "Bottom", ExpectedKind::Array),
	("Layout", "Header", ExpectedKind::Array),
	("Layout", "NativeMenuBar", ExpectedKind::Bool),
	("Layout", "NativeTitleBar", ExpectedKind::Bool),
	("Layout", "NativeDrag", ExpectedKind::Bool),
	("Layout", "ShowShortcuts", ExpectedKind::Bool),
	("Layout", "ExecutionWrapper", ExpectedKind::Str),
	("Layout", "Screen", ExpectedKind::Str),
	("Folder View", "Wallpaper", ExpectedKind::Str),
	("Folder View", "GridSize", ExpectedKind::Num),
	("Folder View", "Maximized", ExpectedKind::Bool),
	("Folder View", "ShowLabels", ExpectedKind::Bool),
	("Folder View", "GridLabelsBesidesIcons", ExpectedKind::Bool),
	(
		"Folder View",
		"GridHorizontalAlign",
		ExpectedKind::StrEnum(&["FILL", "LEFT", "CENTER", "RIGHT"]),
	),
	(
		"Folder View",
		"GridVerticalAlign",
		ExpectedKind::StrEnum(&["FILL", "TOP", "CENTER", "BOTTOM"]),
	),
	("Folder View", "Lines", ExpectedKind::Num),
	(
		"Folder View",
		"ScrollDirection",
		ExpectedKind::StrEnum(&["VERTICAL", "HORIZONTAL"]),
	),
	(
		"Folder View",
		"ViewMode",
		ExpectedKind::StrEnum(&["GRID", "LIST"]),
	),
	// Ordered columns shown in LIST view. TITLE and FILENAME are the name
	// columns; at least one of them is always kept, so a list always has a
	// label. The array's order is the left-to-right display order.
	("Folder View", "ListColumns", ExpectedKind::Array),
	// Show the sticky column header above a list view.
	("Folder View", "ListHeader", ExpectedKind::Bool),
	(
		"Folder View",
		"Sort",
		ExpectedKind::StrEnum(&["NEWEST", "OLDEST", "ALPHABETICAL", "FREE"]),
	),
	(
		"Folder View",
		"SortDateMode",
		ExpectedKind::StrEnum(&["MODIFIED", "CREATED", "ACCESSED"]),
	),
	(
		"Folder View",
		"SortAlphaMode",
		ExpectedKind::StrEnum(&["TITLES", "FILENAMES"]),
	),
	// How the folder is divided into labelled sections. Custom groups are
	// defined by the folder (and by each item's own Group= key), so the user
	// cannot change that mode from the view controls.
	(
		"Folder View",
		"Group",
		ExpectedKind::StrEnum(&["NONE", "DATE", "LETTERS", "TYPE", "CUSTOM"]),
	),
	// Ordered custom groups:
	// [{"name": "Clock", "files": ["datetime.desktop", "timezone"]}, ...]
	("Folder View", "Groups", ExpectedKind::Array),
	("Folder View", "ShowStash", ExpectedKind::Bool),
	// Kept as an alias for older folder configs.
	("Folder View", "StashShown", ExpectedKind::Bool),
	("Folder View", "StashDotFiles", ExpectedKind::Bool),
	("Folder View", "FreePlacementPositions", ExpectedKind::Dict),
	("Folder Navigation", "CenterFocus", ExpectedKind::Bool),
	("Folder Navigation", "SmoothScrolling", ExpectedKind::Bool),
	("Folder Navigation", "OpenOnClick", ExpectedKind::Bool),
	("Folder Navigation", "FocusEmptySlots", ExpectedKind::Bool),
	// A folder-owned single-selection group.  The children carry only display
	// metadata; the parent owns the group, its selection, and the command that
	// runs when the selection changes (ClamOS extension).
	("Radio", "Enabled", ExpectedKind::Bool),
	(
		"Radio",
		"Only",
		ExpectedKind::StrEnum(&["ALL", "DIRECTORIES", "FILES"]),
	),
	("Radio", "Selected", ExpectedKind::Str),
	("Radio", "Exec", ExpectedKind::Str),
];

/// Flags configured keys whose value does not match the expected kind.
fn validate_values(
	parsed: &HashMap<String, HashMap<String, ConfigValue>>,
	origins: &HashMap<(String, String), String>,
) -> Vec<ConfigError> {
	let mut errors = Vec::new();

	for (section, key, expected) in EXPECTED_KEYS {
		let Some(value) = parsed.get(*section).and_then(|s| s.get(*key)) else {
			continue;
		};

		let message = match expected {
			ExpectedKind::Str => {
				(!matches!(value, ConfigValue::String(_) | ConfigValue::Number(_))).then(|| {
					format!(
						"[{}] {}: expected a string, got {}",
						section,
						key,
						value.to_json_string()
					)
				})
			}
			ExpectedKind::StrEnum(allowed) => {
				let valid = matches!(
					value,
					ConfigValue::String(s) if allowed.iter().any(|a| a.eq_ignore_ascii_case(s))
				);
				(!valid).then(|| {
					format!(
						"[{}] {}: expected one of [{}], got {}",
						section,
						key,
						allowed.join(", "),
						value.to_json_string()
					)
				})
			}
			ExpectedKind::Bool => (!matches!(value, ConfigValue::Boolean(_))).then(|| {
				format!(
					"[{}] {}: expected true or false, got {}",
					section,
					key,
					value.to_json_string()
				)
			}),
			ExpectedKind::Num => (!matches!(value, ConfigValue::Number(_))).then(|| {
				format!(
					"[{}] {}: expected a number, got {}",
					section,
					key,
					value.to_json_string()
				)
			}),
			ExpectedKind::Array => (!matches!(value, ConfigValue::Array(_))).then(|| {
				format!(
					"[{}] {}: expected a JSON array, got {}",
					section,
					key,
					value.to_json_string()
				)
			}),
			ExpectedKind::Dict => (!matches!(value, ConfigValue::Dictionary(_))).then(|| {
				format!(
					"[{}] {}: expected a dictionary, got {}",
					section,
					key,
					value.to_json_string()
				)
			}),
		};

		if let Some(message) = message {
			errors.push(ConfigError {
				file: origins
					.get(&(section.to_string(), key.to_string()))
					.cloned(),
				message,
			});
		}
	}

	errors
}

/// Retrieves a string property from a folder's config.
pub fn get_string(path: &Path, section: &str, key: &str) -> Option<String> {
	let parsed = load_path(path);
	if let Some(ConfigValue::String(val)) = parsed.get(section).and_then(|sec| sec.get(key)) {
		Some(val.clone())
	} else {
		None
	}
}

#[allow(dead_code)]
pub fn get_entry_string(path: &Path, key: &str) -> Option<String> {
	entry_string(&load_entry(path), key)
}

/// Resolves an image for a given folder path from its config.
pub fn get_image(path: &Path, section: &str, key: &str) -> Option<String> {
	if let Some(icon) = get_string(path, section, key) {
		return resolve_image(base_dir(path), &icon);
	}
	None
}

pub fn get_entry_image(path: &Path, key: &str) -> Option<String> {
	let icon = entry_string(&load_entry(path), key)?;
	resolve_image(base_dir(path), &icon)
}

fn resolve_image(path: &Path, icon: &str) -> Option<String> {
	if icon.is_empty() {
		return Some(String::new());
	}

	let rel = path.join(icon);
	let is_path = icon.contains('/') || icon.starts_with('.');

	if rel.exists() {
		return Some(rel.to_string_lossy().to_string());
	}

	if is_path {
		let extensions = ["png", "svg", "jpg", "jpeg", "bmp", "avif", "webp"];
		for ext in extensions {
			let candidate = rel.with_extension(ext);
			if candidate.exists() {
				return Some(candidate.to_string_lossy().to_string());
			}
		}
		return Some(String::new());
	}

	Some(icon.to_string())
}

#[derive(QObject, Default)]
pub struct Config {
	base: qt_base_class!(trait QObject),

	pub title: qt_property!(String; NOTIFY config_changed),
	pub icon: qt_property!(String; NOTIFY config_changed),
	pub wallpaper: qt_property!(String; NOTIFY config_changed),

	pub top_layout: qt_property!(String; NOTIFY config_changed),
	pub middle_layout: qt_property!(String; NOTIFY config_changed),
	pub bottom_layout: qt_property!(String; NOTIFY config_changed),
	pub header_layout: qt_property!(String; NOTIFY config_changed),
	pub native_menubar: qt_property!(bool; NOTIFY config_changed),
	// Draw menus as native platform popups instead of in-window ones. Off by
	// default: a native popup is a separate window the compositor places on its
	// own, which on multi-output setups lands on the wrong output and can crash
	// when reopened.
	pub native_menus: qt_property!(bool; NOTIFY config_changed),
	pub native_titlebar: qt_property!(bool; NOTIFY config_changed),
	// Use the compositor's own drag icon instead of the shell's ghost of the
	// dragged item. Off by default: the compositor's drag icon does not render
	// on some targets (the RG DS Plus), so the shell draws its own.
	pub native_drag: qt_property!(bool; NOTIFY config_changed),
	// Show and register the keyboard shortcuts next to menu items. Off on the
	// RG DS Plus, which has no keyboard.
	pub show_shortcuts: qt_property!(bool; NOTIFY config_changed),
	// Command that everything launched from the shell is run through, so a host
	// can wrap starts with its own supervisor (session, transition, suspend).
	// The launched program and its arguments are appended, and the launched
	// item's path is exported as HISHELL_APP_ITEM. Empty means launch directly.
	pub execution_wrapper: qt_property!(String; NOTIFY config_changed),
	// Name of the screen/output to open on (e.g. "DSI-2" on the RG DS Plus, whose
	// bottom touch panel is the second output). Empty means the platform default.
	pub screen_name: qt_property!(String; NOTIFY config_changed),
	// Open the window fullscreen. Set from the "Maximized" folder option; used
	// on kiosk-style targets (e.g. the RG DS Plus) where the app has to cover
	// the launcher.
	pub maximized: qt_property!(bool; NOTIFY config_changed),

	pub grid_size: qt_property!(u16; NOTIFY config_changed),
	pub grid_horizontal_align: qt_property!(u8; NOTIFY config_changed),
	pub grid_vertical_align: qt_property!(u8; NOTIFY config_changed),
	pub grid_lines: qt_property!(i32; NOTIFY config_changed),
	pub scroll_horizontal: qt_property!(bool; NOTIFY config_changed),
	pub center_focus: qt_property!(bool; NOTIFY config_changed),
	pub smooth_scrolling: qt_property!(bool; NOTIFY config_changed),
	// Whether a click/tap on an item opens it. When false the first click only
	// focuses the item and a second click (while it is focused) opens it.
	pub open_on_click: qt_property!(bool; NOTIFY config_changed),
	// Whether the cursor may rest on an empty grid cell. Empty cells only exist
	// in free placement, so this has no effect elsewhere.
	pub focus_empty_slots: qt_property!(bool; NOTIFY config_changed),
	pub show_labels: qt_property!(bool; NOTIFY config_changed),
	pub grid_labels_beside_icons: qt_property!(bool; NOTIFY config_changed),
	pub label_text: qt_property!(u8; NOTIFY config_changed),
	pub view_mode: qt_property!(u8; NOTIFY config_changed),
	// JSON array of list columns, in display order.
	pub list_columns: qt_property!(String; NOTIFY config_changed),
	// Whether the list view draws its sticky column header.
	pub list_header: qt_property!(bool; NOTIFY config_changed),
	pub sort: qt_property!(u8; NOTIFY config_changed),
	pub sort_date_mode: qt_property!(u8; NOTIFY config_changed),
	pub sort_alpha_mode: qt_property!(u8; NOTIFY config_changed),
	// 0 = no grouping, 1 = date, 2 = first letter, 3 = type, 4 = custom.
	pub group_mode: qt_property!(u8; NOTIFY config_changed),
	// Ordered JSON array of custom group definitions.
	pub groups: qt_property!(String; NOTIFY config_changed),
	// Show normally hidden items in a final Stash group. `stash_shown` is the
	// old name for the same switch.
	pub show_stash: qt_property!(bool; NOTIFY config_changed),
	pub stash_shown: qt_property!(bool; NOTIFY config_changed),
	pub stash_dotfiles: qt_property!(bool; NOTIFY config_changed),
	pub free_placement_positions: qt_property!(String; NOTIFY config_changed),

	// Parent-owned radio group ([Radio] in this folder's .directory).  Children
	// are selected by name and the parent `Exec` runs on a change.
	pub radio_enabled: qt_property!(bool; NOTIFY config_changed),
	// 0 = all children, 1 = directories only, 2 = files only.
	pub radio_only: qt_property!(u8; NOTIFY config_changed),
	pub radio_selected: qt_property!(String; NOTIFY config_changed),
	pub radio_exec: qt_property!(String; NOTIFY config_changed),

	pub error: qt_property!(String; NOTIFY config_changed),
	pub error_file: qt_property!(String; NOTIFY config_changed),

	config_changed: qt_signal!(),

	/// Emitted instead of `config_changed` when a written key changes which
	/// files the folder contains (e.g. toggling dotfile stashing). Listeners use
	/// this to do a full directory re-scan, while layout-only changes are handled
	/// by re-evaluating the `config_changed` bindings.
	items_changed: qt_signal!(),

	load: qt_method!(
		pub fn load(&mut self, path: String) {
			self._load(Path::new(&path));
		}
	),

	set: qt_method!(
		pub fn set(
			&mut self,
			path: String,
			section: String,
			key: String,
			value: String,
			local: bool,
		) {
			self._set(Path::new(&path), &section, &key, &value, local);
		}
	),
}

/// Which properties a config write should refresh. Full loads refresh every
/// property; a partial write refreshes only the one that changed, so that
/// adjusting a view setting never has to re-read the folder from disk.
#[derive(Clone)]
enum ChangedKeys {
	All,
	Only(String, String),
}

impl ChangedKeys {
	/// True when the property for `section`/`key` should be (re)derived.
	fn includes(&self, section: &str, key: &str) -> bool {
		match self {
			ChangedKeys::All => true,
			ChangedKeys::Only(s, k) => s == section && k == key,
		}
	}
}

/// Keys whose value decides which files appear in the folder. Writing one of
/// these requires a directory re-scan, so `items_changed` is emitted instead of
/// a layout-only refresh.
pub fn key_affects_items(section: &str, key: &str) -> bool {
	matches!(
		(section, key),
		(
			"Folder View",
			"StashDotFiles" | "ShowStash" | "StashShown"
		)
	)
}

/// Keys whose value only reorders the existing items, so a write can update the
/// model in place instead of re-reading the folder.
pub fn key_affects_order(section: &str, key: &str) -> bool {
	matches!(
		(section, key),
		(
			"Folder View",
			"Sort" | "SortDateMode" | "SortAlphaMode" | "Group" | "Groups"
		)
	)
}

impl Config {
	pub fn _load(&mut self, path: &Path) {
		self._apply(path, ChangedKeys::All);
	}

	/// Re-derive and assign the config properties selected by `changed` from the
	/// folder's combined config, then notify listeners. Only the requested
	/// properties are recomputed, letting view-only changes (grid size, sorting,
	/// free placement, ...) skip the expensive directory reload entirely.
	fn _apply(&mut self, path: &Path, changed: ChangedKeys) {
		let load = load_path_checked(path);
		let mut errors = load.errors;
		errors.extend(validate_values(&load.sections, &load.origins));

		self.error_file = errors
			.iter()
			.find_map(|e| e.file.clone())
			.unwrap_or_default()
			.into();
		self.error = errors
			.iter()
			.map(|e| e.message.as_str())
			.collect::<Vec<_>>()
			.join("\n")
			.into();

		let parsed = load.sections;
		let get = |sec, key| parsed.get(sec).and_then(|s| s.get(key));

		macro_rules! changed {
			($sec:literal, $key:literal) => {
				changed.includes($sec, $key)
			};
		}

		if changed!("Desktop Entry", "Name") {
			self.title = match get("Desktop Entry", "Name") {
				Some(ConfigValue::String(v)) => v.clone(),
				_ => String::new(),
			}
			.into();
		}
		if changed!("Desktop Entry", "Icon") {
			self.icon = get_image(path, "Desktop Entry", "Icon")
				.map(|p| {
					if p.starts_with('/') {
						format!("file://{}", p)
					} else {
						p
					}
				})
				.unwrap_or_default()
				.into();
		}
		if changed!("Folder View", "Wallpaper") {
			self.wallpaper = get_image(path, "Folder View", "Wallpaper")
				.map(|p| {
					if p.starts_with('/') {
						format!("file://{}", p)
					} else {
						p
					}
				})
				.unwrap_or_default()
				.into();
		}

		if changed!("Layout", "Top") {
			self.top_layout = json_value(get("Layout", "Top"), "[]").into();
		}
		if changed!("Layout", "Middle") {
			self.middle_layout = json_value(get("Layout", "Middle"), r#"["./"]"#).into();
		}
		if changed!("Layout", "Bottom") {
			self.bottom_layout = json_value(get("Layout", "Bottom"), "[]").into();
		}
		if changed!("Layout", "Header") {
			self.header_layout = json_value(
				get("Layout", "Header"),
				r#"["toolkit/PathBar", "toolkit/Spacer", "toolkit/ViewButton", "toolkit/MenuBar"]"#,
			)
			.into();
		}
		if changed!("Layout", "NativeMenuBar") {
			self.native_menubar = bool_value(get("Layout", "NativeMenuBar"), false);
		}
		if changed!("Layout", "NativeMenus") {
			self.native_menus = bool_value(get("Layout", "NativeMenus"), false);
		}
		if changed!("Layout", "NativeTitleBar") {
			self.native_titlebar = bool_value(get("Layout", "NativeTitleBar"), true);
		}
		if changed!("Layout", "NativeDrag") {
			self.native_drag = bool_value(get("Layout", "NativeDrag"), false);
		}
		if changed!("Layout", "ShowShortcuts") {
			self.show_shortcuts = bool_value(get("Layout", "ShowShortcuts"), false);
		}
		if changed!("Layout", "ExecutionWrapper") {
			self.execution_wrapper = match get("Layout", "ExecutionWrapper") {
				Some(ConfigValue::String(v)) => v.clone(),
				_ => String::new(),
			}
			.into();
			crate::launch::set_wrapper(&self.execution_wrapper.to_string());
		}
		if changed!("Layout", "Screen") {
			self.screen_name = match get("Layout", "Screen") {
				Some(ConfigValue::String(v)) => v.clone(),
				_ => String::new(),
			}
			.into();
			// Launched programs open on the same output as the shell (docs §5.6).
			crate::launch::set_screen(&self.screen_name.to_string());
		}

		if changed!("Folder View", "GridSize") {
			self.grid_size = num_value(get("Folder View", "GridSize"), 64).max(0) as u16;
		}
		if changed!("Folder View", "Maximized") {
			self.maximized = bool_value(get("Folder View", "Maximized"), false);
		}
		if changed!("Folder View", "ShowLabels") {
			self.show_labels = bool_value(get("Folder View", "ShowLabels"), true);
		}
		if changed!("Folder View", "GridLabelsBesidesIcons") {
			self.grid_labels_beside_icons =
				bool_value(get("Folder View", "GridLabelsBesidesIcons"), false);
		}
		if changed!("Folder View", "LabelText") {
			self.label_text = match enum_value(get("Folder View", "LabelText"), "TITLE").as_str() {
				"FILENAME" => 1,
				_ => 0,
			};
		}
		if changed!("Folder View", "GridHorizontalAlign") {
			self.grid_horizontal_align =
				match enum_value(get("Folder View", "GridHorizontalAlign"), "FILL").as_str() {
					"LEFT" => 1,
					"CENTER" => 2,
					"RIGHT" => 3,
					_ => 0,
				};
		}
		if changed!("Folder View", "GridVerticalAlign") {
			self.grid_vertical_align =
				match enum_value(get("Folder View", "GridVerticalAlign"), "FILL").as_str() {
					"TOP" => 1,
					"CENTER" => 2,
					"BOTTOM" => 3,
					_ => 0,
				};
		}
		if changed!("Folder View", "Lines") {
			self.grid_lines = num_value(get("Folder View", "Lines"), 0).max(0);
		}
		if changed!("Folder View", "ScrollDirection") {
			self.scroll_horizontal =
				enum_value(get("Folder View", "ScrollDirection"), "VERTICAL") == "HORIZONTAL";
		}
		if changed!("Folder Navigation", "CenterFocus") {
			self.center_focus = bool_value(get("Folder Navigation", "CenterFocus"), false);
		}
		if changed!("Folder Navigation", "SmoothScrolling") {
			self.smooth_scrolling = bool_value(get("Folder Navigation", "SmoothScrolling"), true);
		}
		if changed!("Folder Navigation", "OpenOnClick") {
			self.open_on_click = bool_value(get("Folder Navigation", "OpenOnClick"), true);
		}
		if changed!("Folder Navigation", "FocusEmptySlots") {
			self.focus_empty_slots = bool_value(get("Folder Navigation", "FocusEmptySlots"), false);
		}
		if changed!("Folder View", "ViewMode") {
			self.view_mode = match enum_value(get("Folder View", "ViewMode"), "GRID").as_str() {
				"LIST" => 1,
				_ => 0,
			};
		}
		if changed!("Folder View", "ListColumns") {
			self.list_columns = json_value(
				get("Folder View", "ListColumns"),
				r#"["TITLE", "SIZE", "MODIFIED"]"#,
			)
			.into();
		}
		if changed!("Folder View", "ListHeader") {
			self.list_header = bool_value(get("Folder View", "ListHeader"), true);
		}
		if changed!("Folder View", "Sort") {
			self.sort = match enum_value(get("Folder View", "Sort"), "NEWEST").as_str() {
				"OLDEST" => 1,
				"ALPHABETICAL" => 2,
				"FREE" => 3,
				_ => 0,
			};
		}
		if changed!("Folder View", "SortDateMode") {
			self.sort_date_mode =
				match enum_value(get("Folder View", "SortDateMode"), "MODIFIED").as_str() {
					"CREATED" => 1,
					"ACCESSED" => 2,
					_ => 0,
				};
		}
		if changed!("Folder View", "SortAlphaMode") {
			self.sort_alpha_mode =
				match enum_value(get("Folder View", "SortAlphaMode"), "TITLES").as_str() {
					"FILENAMES" => 1,
					_ => 0,
				};
		}
		if changed!("Folder View", "Group") {
			self.group_mode = match enum_value(get("Folder View", "Group"), "NONE").as_str() {
				"DATE" => 1,
				"LETTERS" => 2,
				"TYPE" => 3,
				"CUSTOM" => 4,
				_ => 0,
			};
		}
		if changed!("Folder View", "Groups") {
			self.groups = json_value(get("Folder View", "Groups"), "[]").into();
		}
		if changed!("Folder View", "ShowStash") || changed!("Folder View", "StashShown") {
			// ShowStash is the current key; StashShown is what older configs
			// and the pre-grouping view controls wrote.
			let value = get("Folder View", "ShowStash")
				.or_else(|| get("Folder View", "StashShown"));
			self.show_stash = bool_value(value, false);
			self.stash_shown = self.show_stash;
		}
		if changed!("Folder View", "StashDotFiles") {
			self.stash_dotfiles = bool_value(get("Folder View", "StashDotFiles"), true);
		}
		if changed!("Folder View", "FreePlacementPositions") {
			self.free_placement_positions =
				json_value(get("Folder View", "FreePlacementPositions"), "{}").into();
		}

		if changed!("Radio", "Enabled") {
			self.radio_enabled = bool_value(get("Radio", "Enabled"), false);
		}
		if changed!("Radio", "Only") {
			self.radio_only = match enum_value(get("Radio", "Only"), "ALL").as_str() {
				"DIRECTORIES" => 1,
				"FILES" => 2,
				_ => 0,
			};
		}
		if changed!("Radio", "Selected") {
			self.radio_selected = match get("Radio", "Selected") {
				Some(ConfigValue::String(v)) => v.clone(),
				_ => String::new(),
			}
			.into();
		}
		if changed!("Radio", "Exec") {
			self.radio_exec = match get("Radio", "Exec") {
				Some(ConfigValue::String(v)) => v.clone(),
				_ => String::new(),
			}
			.into();
		}

		self.config_changed();
	}

	pub fn _set(&mut self, path: &Path, section: &str, key: &str, value: &str, local: bool) {
		let file_path = if local {
			entry_path(path).unwrap_or_else(|| path.join(".directory"))
		} else {
			dirs::config_dir()
				.map(|mut p| {
					p.push("hishell");
					p.push("folder.cfg");
					p
				})
				.unwrap_or_else(|| std::path::PathBuf::from("config/default.cfg"))
		};

		crate::config_parser::ConfigParser::set_value(&file_path, section, key, value);

		// Refresh only the written key; layout-only settings therefore skip the
		// full config re-derivation (and, downstream, the directory re-scan).
		self._apply(
			path,
			ChangedKeys::Only(section.to_string(), key.to_string()),
		);
		if key_affects_items(section, key) {
			self.items_changed();
		}
	}

	/// Record a manually placed item coordinate (column, row) in the folder's
	/// `.directory` config under `FreePlacementPositions`.
	pub fn set_free_position(&mut self, path: &Path, name: &str, col: i32, row: i32) {
		let mut positions = self.parse_free_positions();
		positions.insert(name.to_string(), (col, row));
		self.write_free_positions(path, &positions);
	}

	/// Record several manually placed coordinates at once. The entries being
	/// placed win their cells: a saved position for any other item in the same
	/// cell is dropped, including a stashed dotfile that is not on screen. That
	/// keeps a drop where the user put it instead of letting an older saved
	/// position (or an off-screen entry) push it aside.
	pub fn set_free_positions(&mut self, path: &Path, entries: &[(String, i32, i32)]) {
		let mut positions = self.parse_free_positions();
		for (name, col, row) in entries {
			positions.retain(|existing, value| {
				let (c, r) = *value;
				existing == name || c != *col || r != *row
			});
		}
		for (name, col, row) in entries {
			positions.insert(name.clone(), (*col, *row));
		}
		self.write_free_positions(path, &positions);
	}

	/// Move a saved coordinate to a new filename after a rename, keeping the
	/// manually placed item in position.
	pub fn rename_free_position(&mut self, path: &Path, old_name: &str, new_name: &str) {
		let mut positions = self.parse_free_positions();
		let Some(position) = positions.remove(old_name) else {
			return;
		};
		positions.insert(new_name.to_string(), position);
		self.write_free_positions(path, &positions);
	}

	/// Erase all manually placed coordinates for this folder.
	pub fn reset_free_positions(&mut self, path: &Path) {
		self.write_free_positions(path, &HashMap::new());
	}

	fn parse_free_positions(&self) -> HashMap<String, (i32, i32)> {
		let mut map = HashMap::new();
		let Ok(value) =
			serde_json::from_str::<serde_json::Value>(&self.free_placement_positions.to_string())
		else {
			return map;
		};
		let Some(obj) = value.as_object() else {
			return map;
		};
		for (name, pos) in obj {
			let Some(arr) = pos.as_array() else {
				continue;
			};
			let col = arr.get(0).and_then(|v| v.as_i64()).unwrap_or(0) as i32;
			let row = arr.get(1).and_then(|v| v.as_i64()).unwrap_or(0) as i32;
			map.insert(name.clone(), (col, row));
		}
		map
	}

	fn write_free_positions(&mut self, path: &Path, positions: &HashMap<String, (i32, i32)>) {
		let mut obj = serde_json::Map::new();
		for (name, (col, row)) in positions {
			obj.insert(name.clone(), serde_json::json!([col, row]));
		}
		let json = serde_json::Value::Object(obj).to_string();
		self._set(path, "Folder View", "FreePlacementPositions", &json, true);
	}
}

#[cfg(test)]
mod system_config_tests {
	use super::system_config_paths_from;
	use std::path::PathBuf;

	#[test]
	fn earlier_xdg_dirs_take_priority() {
		// XDG_CONFIG_DIRS is highest-priority-first; the parser wants the
		// lowest-priority file first, so the list is reversed.
		assert_eq!(
			system_config_paths_from("/etc/xdg:/usr/local/etc/xdg"),
			vec![
				PathBuf::from("/usr/local/etc/xdg/hishell/folder.cfg"),
				PathBuf::from("/etc/xdg/hishell/folder.cfg"),
			]
		);
	}

	#[test]
	fn empty_entries_are_skipped() {
		assert_eq!(
			system_config_paths_from(":/etc/xdg:"),
			vec![PathBuf::from("/etc/xdg/hishell/folder.cfg")]
		);
	}
}
