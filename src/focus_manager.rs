use crate::gamepad::Input;
use once_cell::sync::Lazy;
use qmetaobject::{QVariantList, prelude::*};
use std::collections::HashMap;
use std::fs;
use std::sync::Mutex;

const FOCUS_BORDER_SVG: &str = include_str!("../theme/default/focus-border.svg");

static BORDER_SOURCES: Lazy<Mutex<HashMap<String, String>>> =
	Lazy::new(|| Mutex::new(HashMap::new()));

fn write_border_asset(color: &str) -> Option<String> {
	let color = if color.starts_with('#') && matches!(color.len(), 7 | 9) {
		color
	} else {
		"#ffffff"
	};

	let directory = dirs::cache_dir()?.join("hishell");
	fs::create_dir_all(&directory).ok()?;

	let digest = md5::compute(color.as_bytes());
	let path = directory.join(format!("focus-border-{:x}.svg", digest));
	if !path.exists() {
		fs::write(&path, FOCUS_BORDER_SVG.replace("#ffffff", color)).ok()?;
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

	focus_changed: qt_signal!(),
	accept_requested: qt_signal!(),
	cancel_requested: qt_signal!(),

	paths: Vec<String>,

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

	set_focus_path: qt_method!(
		fn set_focus_path(&mut self, path: String) {
			if let Some(index) = self.paths.iter().position(|entry| *entry == path) {
				self.set_focus_index(index as i32);
			}
		}
	),

	move_focus: qt_method!(
		fn move_focus(&mut self, direction: String) -> bool {
			if self.paths.is_empty() {
				return false;
			}
			let count = self.item_count;
			let columns = self.grid_columns.max(1);
			let current = if self.focus_active && self.focused_index >= 0 {
				self.focused_index
			} else {
				0
			};
			let current = current.clamp(0, count - 1);

			let target = match direction.as_str() {
				"left" => (current - 1).max(0),
				"right" => (current + 1).min(count - 1),
				"up" => (current - columns).max(0),
				"down" => {
					let last_row = (count - 1) / columns;
					if current / columns < last_row {
						(current + columns).min(count - 1)
					} else {
						current
					}
				}
				_ => current,
			};

			let changed = !self.focus_active || target != current;
			self.focus_active = true;
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
			if let Some(input) = crate::gamepad::poll() {
				match input {
					Input::Up | Input::Down | Input::Left | Input::Right => {
						let direction = String::from(input.as_str());
						self.move_focus(direction);
					}
					Input::Accept => self.accept_requested(),
					Input::Cancel => self.cancel_requested(),
				}
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
