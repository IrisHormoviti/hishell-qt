use crate::config_parser::{ConfigError, ConfigParser, ConfigValue, ParseOutput};
use qmetaobject::prelude::*;
use std::collections::HashMap;
use std::path::{Path, PathBuf};

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
	} else if path.is_file() && has_desktop_entry_header(path) {
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

fn load_with_override(override_path: &Path) -> ParseOutput {
	let default_cfg = Path::new("config/default.cfg");
	let global_cfg = dirs::config_dir()
		.map(|mut p| {
			p.push("hishell");
			p.push("folder.cfg");
			p
		})
		.unwrap_or_else(|| std::path::PathBuf::from("config/default.cfg"));
	let paths: Vec<&Path> = vec![default_cfg, global_cfg.as_path(), override_path];
	ConfigParser::parse_files(&paths)
}

pub fn load_entry(path: &Path) -> HashMap<String, ConfigValue> {
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
	("Folder View", "Wallpaper", ExpectedKind::Str),
	("Folder View", "GridSize", ExpectedKind::Num),
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
	("Folder View", "StashShown", ExpectedKind::Bool),
	("Folder View", "StashDotFiles", ExpectedKind::Bool),
	("Folder View", "FreePlacementPositions", ExpectedKind::Dict),
	("Folder Navigation", "CenterFocus", ExpectedKind::Bool),
	("Folder Navigation", "SmoothScrolling", ExpectedKind::Bool),
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
	pub native_titlebar: qt_property!(bool; NOTIFY config_changed),

	pub grid_size: qt_property!(u16; NOTIFY config_changed),
	pub grid_horizontal_align: qt_property!(u8; NOTIFY config_changed),
	pub grid_vertical_align: qt_property!(u8; NOTIFY config_changed),
	pub grid_lines: qt_property!(i32; NOTIFY config_changed),
	pub scroll_horizontal: qt_property!(bool; NOTIFY config_changed),
	pub center_focus: qt_property!(bool; NOTIFY config_changed),
	pub smooth_scrolling: qt_property!(bool; NOTIFY config_changed),
	pub show_labels: qt_property!(bool; NOTIFY config_changed),
	pub grid_labels_beside_icons: qt_property!(bool; NOTIFY config_changed),
	pub view_mode: qt_property!(u8; NOTIFY config_changed),
	pub sort: qt_property!(u8; NOTIFY config_changed),
	pub sort_date_mode: qt_property!(u8; NOTIFY config_changed),
	pub sort_alpha_mode: qt_property!(u8; NOTIFY config_changed),
	pub stash_shown: qt_property!(bool; NOTIFY config_changed),
	pub stash_dotfiles: qt_property!(bool; NOTIFY config_changed),
	pub free_placement_positions: qt_property!(String; NOTIFY config_changed),

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
	matches!((section, key), ("Folder View", "StashDotFiles"))
}

/// Keys whose value only reorders the existing items, so a write can update the
/// model in place instead of re-reading the folder.
pub fn key_affects_order(section: &str, key: &str) -> bool {
	matches!(
		(section, key),
		("Folder View", "Sort" | "SortDateMode" | "SortAlphaMode")
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
				r#"["toolkit/PathBar", "toolkit/Spacer", "toolkit/MenuBar"]"#,
			)
			.into();
		}
		if changed!("Layout", "NativeMenuBar") {
			self.native_menubar = bool_value(get("Layout", "NativeMenuBar"), false);
		}
		if changed!("Layout", "NativeTitleBar") {
			self.native_titlebar = bool_value(get("Layout", "NativeTitleBar"), true);
		}

		if changed!("Folder View", "GridSize") {
			self.grid_size = num_value(get("Folder View", "GridSize"), 64).max(0) as u16;
		}
		if changed!("Folder View", "ShowLabels") {
			self.show_labels = bool_value(get("Folder View", "ShowLabels"), true);
		}
		if changed!("Folder View", "GridLabelsBesidesIcons") {
			self.grid_labels_beside_icons =
				bool_value(get("Folder View", "GridLabelsBesidesIcons"), false);
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
		if changed!("Folder View", "ViewMode") {
			self.view_mode = match enum_value(get("Folder View", "ViewMode"), "GRID").as_str() {
				"LIST" => 1,
				_ => 0,
			};
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
		if changed!("Folder View", "StashShown") {
			self.stash_shown = bool_value(get("Folder View", "StashShown"), false);
		}
		if changed!("Folder View", "StashDotFiles") {
			self.stash_dotfiles = bool_value(get("Folder View", "StashDotFiles"), true);
		}
		if changed!("Folder View", "FreePlacementPositions") {
			self.free_placement_positions =
				json_value(get("Folder View", "FreePlacementPositions"), "{}").into();
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
