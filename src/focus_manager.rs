use crate::gamepad::Input;
use once_cell::sync::Lazy;
use qmetaobject::{QVariantList, prelude::*};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::Mutex;

const FOCUS_BORDER_SVG: &str = include_str!("../theme/default/focus-border.svg");

static BORDER_SOURCES: Lazy<Mutex<HashMap<String, String>>> =
	Lazy::new(|| Mutex::new(HashMap::new()));

fn focus_border_svg() -> String {
	// Prefer the asset on disk so that edits show up without a rebuild, and
	// fall back to the copy baked into the binary for installed builds.
	let candidates = [
		PathBuf::from("theme/default/focus-border.svg"),
		PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("theme/default/focus-border.svg"),
	];
	for path in candidates {
		if let Ok(source) = fs::read_to_string(&path) {
			return source;
		}
	}

	FOCUS_BORDER_SVG.to_string()
}

fn write_border_asset(color: &str) -> Option<String> {
	let color = if color.starts_with('#') && matches!(color.len(), 7 | 9) {
		color
	} else {
		"#ffffff"
	};

	let source = focus_border_svg();
	let directory = dirs::cache_dir()?.join("hishell");
	fs::create_dir_all(&directory).ok()?;

	// Keyed by content as well as colour, so editing the asset yields a new
	// file and URL, which also invalidates the image cache on the QML side.
	let digest = md5::compute(format!("{color}:{source}").as_bytes());
	let path = directory.join(format!("focus-border-{:x}.svg", digest));
	if !path.exists() {
		fs::write(&path, source.replace("#ffffff", color)).ok()?;
	}

	Some(format!("file://{}", path.to_string_lossy()))
}

#[derive(QObject, Default)]
pub struct FocusManager {
	base: qt_base_class!(trait QObject),

	focus_active: qt_property!(bool; NOTIFY focus_changed),
	focused_index: qt_property!(i32; NOTIFY focus_changed),
	focused_path: qt_property!(String; NOTIFY focus_changed),
	item_count: qt_property!(i32; NOTIFY focus_changed),
	grid_columns: qt_property!(i32; NOTIFY focus_changed),
	focus_status: qt_property!(String; NOTIFY focus_changed),
	window: qt_property!(QVariant),
	view_focused: qt_property!(bool; NOTIFY focus_changed),

	focus_changed: qt_signal!(),
	accept_requested: qt_signal!(),
	cancel_requested: qt_signal!(),
	menu_requested: qt_signal!(),

	paths: Vec<String>,
	horizontal: bool,

	set_items: qt_method!(
		fn set_items(&mut self, paths: QVariantList, columns: i32) {
			let previous_path = self.focused_path.clone();
			let was_active = self.focus_active;

			self.paths.clear();
			for path in &paths {
				let value = path.to_qstring().to_string();
				if !value.is_empty() {
					self.paths.push(value);
				}
			}
			self.item_count = self.paths.len() as i32;
			self.grid_columns = columns.max(1);

			if self.paths.is_empty() {
				self.focus_active = false;
				self.focused_index = -1;
				self.focused_path = String::new();
			} else {
				let preserved = self.paths.iter().position(|path| *path == previous_path);
				let index = match preserved {
					Some(index) => index as i32,
					None => self.focused_index.clamp(0, self.item_count - 1),
				};
				self.focus_active = was_active;
				self.focused_index = index;
				self.focused_path = self.paths[index as usize].clone();
			}

			self.update_status();
			self.focus_changed();
		}
	),

	set_columns: qt_method!(
		fn set_columns(&mut self, columns: i32) {
			let columns = columns.max(1);
			if self.grid_columns != columns {
				self.grid_columns = columns;
				self.update_status();
				self.focus_changed();
			}
		}
	),

	set_horizontal: qt_method!(
		fn set_horizontal(&mut self, horizontal: bool) {
			self.horizontal = horizontal;
		}
	),

	set_focus_index: qt_method!(
		fn set_focus_index(&mut self, index: i32) {
			if self.paths.is_empty() {
				return;
			}
			let index = index.clamp(0, self.item_count - 1);
			self.focus_active = true;
			self.focused_index = index;
			self.focused_path = self.paths[index as usize].clone();
			self.update_status();
			self.focus_changed();
		}
	),

	enter_focus: qt_method!(
		fn enter_focus(&mut self) {
			if self.paths.is_empty() {
				return;
			}
			if self.focused_index < 0 {
				self.focused_index = 0;
				self.focused_path = self.paths[0].clone();
			}
			self.focus_active = true;
			self.update_status();
			self.focus_changed();
		}
	),

	set_focus_path: qt_method!(
		fn set_focus_path(&mut self, path: String) -> bool {
			match self.paths.iter().position(|entry| *entry == path) {
				Some(index) => {
					self.set_focus_index(index as i32);
					true
				}
				None => false,
			}
		}
	),

	move_focus: qt_method!(
		fn move_focus(&mut self, direction: String) -> bool {
			if self.paths.is_empty() {
				return false;
			}
			if !self.focus_active {
				// The first directional input reveals the focus where it
				// already sits instead of moving it right away.
				self.set_focus_index(self.focused_index.max(0));
				return true;
			}
			let count = self.item_count;
			let stride = self.grid_columns.max(1);
			let current = self.focused_index.clamp(0, count - 1);

			let target = if self.horizontal {
				match direction.as_str() {
					"up" => (current - 1).max(0),
					"down" => (current + 1).min(count - 1),
					"left" => (current - stride).max(0),
					"right" => {
						let last_column = (count - 1) / stride;
						if current / stride < last_column {
							(current + stride).min(count - 1)
						} else {
							current
						}
					}
					_ => current,
				}
			} else {
				match direction.as_str() {
					"left" => (current - 1).max(0),
					"right" => (current + 1).min(count - 1),
					"up" => (current - stride).max(0),
					"down" => {
						let last_row = (count - 1) / stride;
						if current / stride < last_row {
							(current + stride).min(count - 1)
						} else {
							current
						}
					}
					_ => current,
				}
			};

			let changed = target != current;
			self.focused_index = target;
			self.focused_path = self.paths[target as usize].clone();
			self.update_status();
			self.focus_changed();
			changed
		}
	),

	focus_first: qt_method!(
		fn focus_first(&mut self) {
			if !self.paths.is_empty() {
				self.set_focus_index(0);
			}
		}
	),

	focus_last: qt_method!(
		fn focus_last(&mut self) {
			if !self.paths.is_empty() {
				self.set_focus_index(self.item_count - 1);
			}
		}
	),

	clear: qt_method!(
		fn clear(&mut self) {
			if self.focus_active || self.focused_index != -1 {
				self.focus_active = false;
				self.focused_index = -1;
				self.focused_path = String::new();
				self.update_status();
				self.focus_changed();
			}
		}
	),

	poll_gamepad: qt_method!(
		fn poll_gamepad(&mut self) {
			let Some(input) = crate::gamepad::poll() else {
				return;
			};

			if !self.view_focused {
				if let Some(key) = qt_key(input) {
					crate::kde_bridge::send_key(key);
				}
				return;
			}

			match input {
				Input::Up | Input::Down | Input::Left | Input::Right => {
					let direction = String::from(input.as_str());
					self.move_focus(direction);
				}
				Input::Accept => self.accept_requested(),
				Input::Cancel => self.cancel_requested(),
				Input::Menu => self.menu_requested(),
			}
		}
	),

	border_source: qt_method!(
		fn border_source(&self, color: String) -> String {
			let color = color.to_string();
			if let Ok(cache) = BORDER_SOURCES.lock()
				&& let Some(source) = cache.get(&color)
			{
				return source.clone();
			}

			let source = write_border_asset(&color).unwrap_or_default();
			if let Ok(mut cache) = BORDER_SOURCES.lock() {
				cache.insert(color, source.clone());
			}
			source
		}
	),
}

impl FocusManager {
	fn update_status(&mut self) {
		let mut status = HashMap::new();
		status.insert(
			"active".to_string(),
			serde_json::Value::from(self.focus_active),
		);
		status.insert(
			"index".to_string(),
			serde_json::Value::from(self.focused_index),
		);
		status.insert(
			"path".to_string(),
			serde_json::Value::from(self.focused_path.as_str()),
		);
		status.insert(
			"count".to_string(),
			serde_json::Value::from(self.item_count),
		);
		status.insert(
			"columns".to_string(),
			serde_json::Value::from(self.grid_columns),
		);
		self.focus_status = serde_json::to_string(&status).unwrap_or_default();
	}
}

fn qt_key(input: Input) -> Option<i32> {
	const KEY_ESCAPE: i32 = 0x0100_0000;
	const KEY_RETURN: i32 = 0x0100_0004;
	const KEY_LEFT: i32 = 0x0100_0012;
	const KEY_UP: i32 = 0x0100_0013;
	const KEY_RIGHT: i32 = 0x0100_0014;
	const KEY_DOWN: i32 = 0x0100_0015;

	match input {
		Input::Up => Some(KEY_UP),
		Input::Down => Some(KEY_DOWN),
		Input::Left => Some(KEY_LEFT),
		Input::Right => Some(KEY_RIGHT),
		Input::Accept => Some(KEY_RETURN),
		Input::Cancel => Some(KEY_ESCAPE),
		Input::Menu => None,
	}
}
