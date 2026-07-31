use crate::config_parser::{ConfigParser, ConfigValue};
use qmetaobject::prelude::*;
use std::collections::HashMap;
use std::path::Path;
use dirs

/// Loads and combines the default config with a folder's `.meta` config.
pub fn load_path(path: &Path) -> HashMap<String, HashMap<String, ConfigValue>> {
	let default_cfg = Path::new("config/default.cfg");
	let meta_path = path.join(".meta");
	ConfigParser::parse_files(&[default_cfg, &meta_path])
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

	pub grid_size: qt_property!(i32; NOTIFY config_changed),
	pub show_labels: qt_property!(bool; NOTIFY config_changed),
	pub view_mode: qt_property!(i16; NOTIFY config_changed),
	pub stash_dotfiles: qt_property!(bool; NOTIFY config_changed),
	pub arbitrary_placement: qt_property!(bool; NOTIFY config_changed),
	pub arbitrary_positions: qt_property!(String; NOTIFY config_changed),

	config_changed: qt_signal!(),

	load: qt_method!(
		pub fn load(&mut self, path: String) {
			let path_str = path.to_string();
			let path_buf = Path::new(&path_str);
			let parsed = load_path(path_buf);

			let get = |sec, key| parsed.get(sec).and_then(|s| s.get(key));

			let get_str = |sec, key, default: &str| {
				if let Some(ConfigValue::String(v)) = get(sec, key) { v.clone() } else { default.to_string() }
			};
			let get_bool = |sec, key, default| {
				if let Some(ConfigValue::Boolean(b)) = get(sec, key) { *b } else { default }
			};
			let get_num = |sec, key, default| {
				if let Some(ConfigValue::Number(n)) = get(sec, key) { *n as i32 } else { default }
			};
			let get_json = |sec, key, default: &str| {
				match get(sec, key) {
					Some(v @ ConfigValue::Array(_)) | Some(v @ ConfigValue::Dictionary(_)) => v.to_json_string(),
					 _ => default.to_string(),
				}
			};

			self.title = get_str("DISPLAY", "Title", "").into();
			self.icon = get_image(path_buf, "DISPLAY", "Icon")
				.map(|p| if p.starts_with('/') { format!("file://{}", p) } else { p })
				.unwrap_or_default();
			self.wallpaper = get_image(path_buf, "DISPLAY", "Wallpaper")
				.map(|p| if p.starts_with('/') { format!("file://{}", p) } else { p })
				.unwrap_or_default();

			self.top_layout = get_json("LAYOUT", "Top", "[]").into();
			self.middle_layout = get_json("LAYOUT", "Middle", r#"["./"]"#).into();
			self.bottom_layout = get_json("LAYOUT", "Bottom", "[]").into();
			self.header_layout = get_json("LAYOUT", "Header", r#"["toolkit/PathBar, "toolkit/Spacer", "toolkit/MenuBar"]"#).into();

			self.grid_size = get_num("VIEW", "GridSize", 64);
			self.show_labels = get_bool("VIEW", "ShowLabels", true);

			self.view_mode = match get_str("VIEW", "ViewMode", "GRID").to_uppercase().as_str() {
				"LIST" => 1,
				_ => 0,
			};

			self.stash_dotfiles = get_bool("VIEW", "StashDotFiles", true);
			self.arbitrary_placement = get_bool("VIEW", "ArbitraryPlacement", false);
			self.arbitrary_positions = get_json("VIEW", "ArbitraryPlacementPositions", "{}").into();

			self.config_changed();
		}
	),


}
