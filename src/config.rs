use crate::config_parser::{ConfigParser, ConfigValue};
use qmetaobject::prelude::*;
use std::collections::HashMap;
use std::path::Path;

/// Loads and combines the default config with a folder's `.meta` config.
pub fn load(path: &Path) -> HashMap<String, HashMap<String, ConfigValue>> {
	let default_cfg = Path::new("config/default.cfg");
	let meta_path = path.join(".meta");
	ConfigParser::parse_files(&[default_cfg, &meta_path])
}

/// Retrieves a string property from a folder's config.
pub fn get_string(path: &Path, section: &str, key: &str) -> Option<String> {
	let parsed = load(path);
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

	title: qt_property!(String; NOTIFY config_changed),
	icon: qt_property!(String; NOTIFY config_changed),
	wallpaper: qt_property!(String; NOTIFY config_changed),

	top_layout: qt_property!(String; NOTIFY config_changed),
	middle_layout: qt_property!(String; NOTIFY config_changed),
	bottom_layout: qt_property!(String; NOTIFY config_changed),
	header_layout: qt_property!(String; NOTIFY config_changed),

	grid_size: qt_property!(i32; NOTIFY config_changed),
	stash_dotfiles: qt_property!(bool; NOTIFY config_changed),
	arbitrary_placement: qt_property!(bool; NOTIFY config_changed),
	arbitrary_positions: qt_property!(String; NOTIFY config_changed),

	config_changed: qt_signal!(),

	load: qt_method!(
		pub fn load(&mut self, path: String) {
			let path_str = path.to_string();
			let path_buf = Path::new(&path_str);
			let parsed = load(path_buf);

			self.title = "".into();
			self.icon = "./.icon".into();
			self.wallpaper = "./.wallpaper".into();

			self.top_layout = "[]".into();
			self.middle_layout = "[\"toolkit/FolderView\"]".into();
			self.bottom_layout = "[]".into();
			self.header_layout = "[\"toolkit/PathBar\", \"toolkit/Spacer\", \"toolkit/MenuBar\"]".into();

			self.grid_size = 64;
			self.stash_dotfiles = true;
			self.arbitrary_placement = false;
			self.arbitrary_positions = "{}".into();

			let get = |sec, key| parsed.get(sec)?.get(key);

			if let Some(ConfigValue::String(v)) = get("DISPLAY", "Title") { self.title = v.clone().into(); }
			if let Some(ConfigValue::String(v)) = get("DISPLAY", "Icon") { self.icon = v.clone().into(); }
			if let Some(ConfigValue::String(v)) = get("DISPLAY", "Wallpaper") { self.wallpaper = v.clone().into(); }

			if let Some(v @ ConfigValue::Array(_)) = get("LAYOUT", "Top") { self.top_layout = v.to_json_string().into(); }
			if let Some(v @ ConfigValue::Array(_)) = get("LAYOUT", "Middle") { self.middle_layout = v.to_json_string().into(); }
			if let Some(v @ ConfigValue::Array(_)) = get("LAYOUT", "Bottom") { self.bottom_layout = v.to_json_string().into(); }
			if let Some(v @ ConfigValue::Array(_)) = get("LAYOUT", "Header") { self.header_layout = v.to_json_string().into(); }

			if let Some(ConfigValue::Number(n)) = get("VIEW", "GridSize") { self.grid_size = *n as i32; }
			if let Some(ConfigValue::Boolean(b)) = get("VIEW", "StashDotFiles") { self.stash_dotfiles = *b; }
			if let Some(ConfigValue::Boolean(b)) = get("VIEW", "ArbitraryPlacement") { self.arbitrary_placement = *b; }
			if let Some(v @ ConfigValue::Dictionary(_)) = get("VIEW", "ArbitraryPlacementPositions") {
				self.arbitrary_positions = v.to_json_string().into();
			}

			self.config_changed();
		}
	),
}
