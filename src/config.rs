use crate::bridge::ffi::{Config, QString};
use crate::config_parser::{ConfigParser, ConfigValue};
use core::pin::Pin;
use std::collections::HashMap;
use std::path::Path;

/// Loads and combines the default config with a folder's `.meta` config.
pub fn load_path(path: &Path) -> HashMap<String, HashMap<String, ConfigValue>> {
	let default_cfg = Path::new("config/default.cfg");
	let global_cfg = dirs::config_dir()
		.map(|mut p| {
			p.push("hishell");
			p.push("folder.cfg");
			p
		})
		.unwrap_or_else(|| std::path::PathBuf::from("config/default.cfg"));
	let meta_path = path.join(".meta");
	let paths: Vec<&Path> = vec![default_cfg, global_cfg.as_path(), meta_path.as_path()];
	ConfigParser::parse_files(&paths)
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

pub struct ConfigRust {
	pub title: QString,
	pub icon: QString,
	pub wallpaper: QString,
	pub top_layout: QString,
	pub middle_layout: QString,
	pub bottom_layout: QString,
	pub header_layout: QString,
	pub grid_size: u16,
	pub show_labels: bool,
	pub view_mode: u8,
	pub sort: u8,
	pub sort_date_mode: u8,
	pub sort_alpha_mode: u8,
	pub stash_shown: bool,
	pub stash_dotfiles: bool,
	pub arbitrary_placement: bool,
	pub arbitrary_positions: QString,
}

impl Default for ConfigRust {
	fn default() -> Self {
		Self {
			title: QString::default(),
			icon: QString::default(),
			wallpaper: QString::default(),
			top_layout: QString::from("[]"),
			middle_layout: QString::from(r#"["./"]"#),
			bottom_layout: QString::from("[]"),
			header_layout: QString::from(r#"["toolkit/PathBar", "toolkit/Spacer", "toolkit/MenuBar"]"#),
			grid_size: 64,
			show_labels: true,
			view_mode: 0,
			sort: 0,
			sort_date_mode: 0,
			sort_alpha_mode: 0,
			stash_shown: false,
			stash_dotfiles: true,
			arbitrary_placement: false,
			arbitrary_positions: QString::from("{}"),
		}
	}
}

impl ConfigRust {
	pub fn load(self: Pin<&mut Config>, path: &QString) {
		let path_str = path.to_string();
		self._load(Path::new(&path_str));
	}

	pub fn set(
		mut self: Pin<&mut Config>,
		path: &QString,
		section: &QString,
		key: &QString,
		value: &QString,
		local: bool,
	) {
		let path_str = path.to_string();
		let sec_str = section.to_string();
		let key_str = key.to_string();
		let val_str = value.to_string();
		self.as_mut()._set(
			Path::new(&path_str),
			&sec_str,
			&key_str,
			&val_str,
			local,
		);
		self.config_changed();
	}

	pub fn _load(mut self: Pin<&mut Config>, path: &Path) {
		let parsed = load_path(path);

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

		let title_val = QString::from(&get_str("DISPLAY", "Title", ""));
		let icon_val = QString::from(
			&get_image(path, "DISPLAY", "Icon")
				.map(|p| {
					if p.starts_with('/') {
						format!("file://{}", p)
					} else {
						p
					}
				})
				.unwrap_or_default(),
		);
		let wallpaper_val = QString::from(
			&get_image(path, "DISPLAY", "Wallpaper")
				.map(|p| {
					if p.starts_with('/') {
						format!("file://{}", p)
					} else {
						p
					}
				})
				.unwrap_or_default(),
		);

		let top_layout_val = QString::from(&get_json("LAYOUT", "Top", "[]"));
		let middle_layout_val = QString::from(&get_json("LAYOUT", "Middle", r#"["./"]"#));
		let bottom_layout_val = QString::from(&get_json("LAYOUT", "Bottom", "[]"));
		let header_layout_val = QString::from(&get_json(
			"LAYOUT",
			"Header",
			r#"["toolkit/PathBar", "toolkit/Spacer", "toolkit/MenuBar"]"#,
		));

		let grid_size_val = get_num("VIEW", "GridSize", 64) as u16;
		let show_labels_val = get_bool("VIEW", "ShowLabels", true);

		let view_mode_val = match get_str("VIEW", "ViewMode", "GRID").to_uppercase().as_str() {
			"GRID" => 0,
			"LIST" => 1,
			_ => 0,
		};

		let sort_val = match get_str("VIEW", "Sort", "NEWEST").to_uppercase().as_str() {
			"NEWEST" => 0,
			"OLDEST" => 1,
			"ALPHABETICAL" => 2,
			_ => 0,
		};

		let sort_date_mode_val = match get_str("VIEW", "SortDateMode", "MODIFIED")
			.to_uppercase()
			.as_str()
		{
			"MODIFIED" => 0,
			"CREATED" => 1,
			"ACCESSED" => 2,
			_ => 0,
		};

		let sort_alpha_mode_val = match get_str("VIEW", "SortAlphaMode", "TITLES")
			.to_uppercase()
			.as_str()
		{
			"TITLES" => 0,
			"FILENAMES" => 1,
			_ => 0,
		};

		let stash_shown_val = get_bool("VIEW", "StashShown", false);
		let stash_dotfiles_val = get_bool("VIEW", "StashDotFiles", true);
		let arbitrary_placement_val = get_bool("VIEW", "ArbitraryPlacement", false);
		let arbitrary_positions_val = QString::from(&get_json("VIEW", "ArbitraryPlacementPositions", "{}"));

		self.as_mut().set_title(title_val);
		self.as_mut().set_icon(icon_val);
		self.as_mut().set_wallpaper(wallpaper_val);
		self.as_mut().set_top_layout(top_layout_val);
		self.as_mut().set_middle_layout(middle_layout_val);
		self.as_mut().set_bottom_layout(bottom_layout_val);
		self.as_mut().set_header_layout(header_layout_val);
		self.as_mut().set_grid_size(grid_size_val);
		self.as_mut().set_show_labels(show_labels_val);
		self.as_mut().set_view_mode(view_mode_val);
		self.as_mut().set_sort(sort_val);
		self.as_mut().set_sort_date_mode(sort_date_mode_val);
		self.as_mut().set_sort_alpha_mode(sort_alpha_mode_val);
		self.as_mut().set_stash_shown(stash_shown_val);
		self.as_mut().set_stash_dotfiles(stash_dotfiles_val);
		self.as_mut().set_arbitrary_placement(arbitrary_placement_val);
		self.as_mut().set_arbitrary_positions(arbitrary_positions_val);

		self.config_changed();
	}

	pub fn _set(mut self: Pin<&mut Config>, path: &Path, section: &str, key: &str, value: &str, local: bool) {
		let file_path = if local {
			path.join(".meta")
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
}