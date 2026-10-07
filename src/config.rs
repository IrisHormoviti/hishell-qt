use crate::config_parser::{ConfigError, ConfigParser, ConfigValue, ParseOutput};
use qmetaobject::prelude::*;
use std::collections::HashMap;
use std::path::Path;

/// Loads and combines the default config with a folder's `.directory` config,
/// keeping track of which file each value came from and any load errors.
pub fn load_path_checked(path: &Path) -> ParseOutput {
	let default_cfg = Path::new("config/default.cfg");
	let global_cfg = dirs::config_dir()
		.map(|mut p| {
			p.push("hishell");
			p.push("folder.cfg");
			p
		})
		.unwrap_or_else(|| std::path::PathBuf::from("config/default.cfg"));
	let meta_path = path.join(".directory");
	let paths: Vec<&Path> = vec![default_cfg, global_cfg.as_path(), meta_path.as_path()];
	ConfigParser::parse_files(&paths)
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
	("Desktop Entry", "Icon", ExpectedKind::Str),
	("Layout", "Top", ExpectedKind::Array),
	("Layout", "Middle", ExpectedKind::Array),
	("Layout", "Bottom", ExpectedKind::Array),
	("Layout", "Header", ExpectedKind::Array),
	("Layout", "NativeMenuBar", ExpectedKind::Bool),
	("Layout", "NativeTitleBar", ExpectedKind::Bool),
	("Folder View", "Wallpaper", ExpectedKind::Str),
	("Folder View", "GridSize", ExpectedKind::Num),
	("Folder View", "ShowLabels", ExpectedKind::Bool),
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
	("Folder View", "ViewMode", ExpectedKind::StrEnum(&["GRID", "LIST"])),
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

/// Resolves an image for a given folder path from its config.
pub fn get_image(path: &Path, section: &str, key: &str) -> Option<String> {
	if let Some(icon) = get_string(path, section, key) {
		let rel = path.join(&icon);
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
		} else {
			return Some(icon);
		}
	}
	None
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
			self.config_changed();
		}
	),
}

impl Config {
	pub fn _load(&mut self, path: &Path) {
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

		let get_str = |sec, key, default: &str| {
			if let Some(ConfigValue::String(v)) = get(sec, key) {
				v.clone()
			} else {
				default.to_string()
			}
		};
		let get_bool = |sec, key, default| {
			if let Some(ConfigValue::Boolean(b)) = get(sec, key) {
				*b
			} else {
				default
			}
		};
		let get_num = |sec, key, default| {
			if let Some(ConfigValue::Number(n)) = get(sec, key) {
				*n as i32
			} else {
				default
			}
		};
		let get_json = |sec, key, default: &str| match get(sec, key) {
			Some(v @ ConfigValue::Array(_)) | Some(v @ ConfigValue::Dictionary(_)) => {
				v.to_json_string()
			}
			_ => default.to_string(),
		};

		self.title = get_str("Desktop Entry", "Name", "").into();
		self.icon = get_image(path, "Desktop Entry", "Icon")
			.map(|p| {
				if p.starts_with('/') {
					format!("file://{}", p)
				} else {
					p
				}
			})
			.unwrap_or_default();
		self.wallpaper = get_image(path, "Folder View", "Wallpaper")
			.map(|p| {
				if p.starts_with('/') {
					format!("file://{}", p)
				} else {
					p
				}
			})
			.unwrap_or_default();

		self.top_layout = get_json("Layout", "Top", "[]").into();
		self.middle_layout = get_json("Layout", "Middle", r#"["./"]"#).into();
		self.bottom_layout = get_json("Layout", "Bottom", "[]").into();
		self.header_layout = get_json(
			"Layout",
			"Header",
			r#"["toolkit/PathBar", "toolkit/Spacer", "toolkit/MenuBar"]"#,
		)
		.into();
		self.native_menubar = get_bool("Layout", "NativeMenuBar", false);
		self.native_titlebar = get_bool("Layout", "NativeTitleBar", true);

		self.grid_size = get_num("Folder View", "GridSize", 64) as u16;
		self.show_labels = get_bool("Folder View", "ShowLabels", true);

		self.grid_horizontal_align = match get_str("Folder View", "GridHorizontalAlign", "FILL")
			.to_uppercase()
			.as_str()
		{
			"LEFT" => 1,
			"CENTER" => 2,
			"RIGHT" => 3,
			_ => 0,
		};

		self.grid_vertical_align = match get_str("Folder View", "GridVerticalAlign", "FILL")
			.to_uppercase()
			.as_str()
		{
			"TOP" => 1,
			"CENTER" => 2,
			"BOTTOM" => 3,
			_ => 0,
		};

		self.grid_lines = get_num("Folder View", "Lines", 0).max(0);
		self.scroll_horizontal =
			get_str("Folder View", "ScrollDirection", "VERTICAL").to_uppercase() == "HORIZONTAL";

		self.center_focus = get_bool("Folder Navigation", "CenterFocus", false);
		self.smooth_scrolling = get_bool("Folder Navigation", "SmoothScrolling", true);

		self.view_mode = match get_str("Folder View", "ViewMode", "GRID").to_uppercase().as_str() {
			"GRID" => 0,
			"LIST" => 1,
			_ => 0,
		};

		self.sort = match get_str("Folder View", "Sort", "NEWEST").to_uppercase().as_str() {
			"NEWEST" => 0,
			"OLDEST" => 1,
			"ALPHABETICAL" => 2,
			"FREE" => 3,
			_ => 0,
		};

		self.sort_date_mode = match get_str("Folder View", "SortDateMode", "MODIFIED")
			.to_uppercase()
			.as_str()
		{
			"MODIFIED" => 0,
			"CREATED" => 1,
			"ACCESSED" => 2,
			_ => 0,
		};

		self.sort_alpha_mode = match get_str("Folder View", "SortAlphaMode", "TITLES")
			.to_uppercase()
			.as_str()
		{
			"TITLES" => 0,
			"FILENAMES" => 1,
			_ => 0,
		};

		self.stash_shown = get_bool("Folder View", "StashShown", false);
		self.stash_dotfiles = get_bool("Folder View", "StashDotFiles", true);
		self.free_placement_positions = get_json("Folder View", "FreePlacementPositions", "{}").into();

		self.config_changed();
	}

	pub fn _set(&mut self, path: &Path, section: &str, key: &str, value: &str, local: bool) {
		let file_path = if local {
			path.join(".directory")
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

		self._load(path);
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
