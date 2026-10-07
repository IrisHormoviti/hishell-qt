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

/// Focus state of one file view. A window hosts a pane per view, and each pane
/// keeps its own cursor so that only the pane the focus is in reacts.
#[derive(Clone, Default)]
struct Pane {
	paths: Vec<String>,
	index: i32,
	active: bool,
	columns: i32,
	horizontal: bool,
	keyboard: bool,
	x: f64,
	y: f64,
	width: f64,
	height: f64,
}

impl Pane {
	fn count(&self) -> i32 {
		self.paths.len() as i32
	}

	fn path(&self) -> String {
		if self.index < 0 {
			return String::new();
		}
		self.paths
			.get(self.index as usize)
			.cloned()
			.unwrap_or_default()
	}

	fn rows(&self) -> i32 {
		let count = self.count();
		let stride = self.columns.max(1);
		if count == 0 {
			1
		} else if self.horizontal {
			stride
		} else {
			(count + stride - 1) / stride
		}
	}

	fn grid_columns(&self) -> i32 {
		let count = self.count();
		let stride = self.columns.max(1);
		if count == 0 {
			1
		} else if self.horizontal {
			(count + stride - 1) / stride
		} else {
			stride
		}
	}

	fn row_column(&self) -> (i32, i32) {
		let count = self.count();
		if count == 0 {
			return (0, 0);
		}
		let stride = self.columns.max(1);
		let index = self.index.clamp(0, count - 1);
		if self.horizontal {
			(index % stride, index / stride)
		} else {
			(index / stride, index % stride)
		}
	}

	fn index_at(&self, row: i32, column: i32) -> i32 {
		let count = self.count();
		if count == 0 {
			return -1;
		}
		let row = row.clamp(0, self.rows() - 1);
		let column = column.clamp(0, self.grid_columns() - 1);
		let stride = self.columns.max(1);
		let index = if self.horizontal {
			column * stride + row
		} else {
			row * stride + column
		};
		index.clamp(0, count - 1)
	}
}

#[derive(QObject, Default)]
pub struct FocusManager {
	base: qt_base_class!(trait QObject),

	// Mirror of the pane owning the focus, so QML bindings can stay simple.
	focus_active: qt_property!(bool; NOTIFY focus_changed),
	focused_index: qt_property!(i32; NOTIFY focus_changed),
	focused_path: qt_property!(String; NOTIFY focus_changed),
	item_count: qt_property!(i32; NOTIFY focus_changed),
	grid_columns: qt_property!(i32; NOTIFY focus_changed),
	focus_status: qt_property!(String; NOTIFY focus_changed),
	window: qt_property!(QVariant),
	view_focused: qt_property!(bool; NOTIFY focus_changed),
	current_pane: qt_property!(i32; NOTIFY focus_changed),

	focus_changed: qt_signal!(),
	accept_requested: qt_signal!(),
	cancel_requested: qt_signal!(),
	menu_requested: qt_signal!(),
	select_requested: qt_signal!(),
	directory_menu_requested: qt_signal!(),

	panes: Vec<(i32, Pane)>,
	next_id: i32,
	current: i32,

	register_pane: qt_method!(
		fn register_pane(&mut self) -> i32 {
			self.next_id += 1;
			let id = self.next_id;
			self.panes.push((id, Pane::default()));
			if self.current == 0 {
				self.current = id;
			}
			self.sync();
			id
		}
	),

	release_pane: qt_method!(
		fn release_pane(&mut self, id: i32) {
			self.panes.retain(|(pane_id, _)| *pane_id != id);
			if self.current == id {
				self.current = self.panes.first().map_or(0, |(pane_id, _)| *pane_id);
			}
			self.sync();
		}
	),

	set_pane_items: qt_method!(
		fn set_pane_items(&mut self, id: i32, paths: QVariantList, columns: i32) {
			let Some(entry) = self.panes.iter().position(|(pane_id, _)| *pane_id == id) else {
				return;
			};

			let previous_path = self.panes[entry].1.path();
			let was_active = self.panes[entry].1.active;

			let mut list = Vec::new();
			for path in &paths {
				let value = path.to_qstring().to_string();
				if !value.is_empty() {
					list.push(value);
				}
			}

			let pane = &mut self.panes[entry].1;
			pane.paths = list;
			pane.columns = columns.max(1);

			if pane.paths.is_empty() {
				pane.active = false;
				pane.index = -1;
			} else {
				let count = pane.count();
				let preserved = pane.paths.iter().position(|path| *path == previous_path);
				pane.index = match preserved {
					Some(index) => index as i32,
					None => pane.index.clamp(0, count - 1),
				};
				pane.active = was_active;
			}

			self.sync();
		}
	),

	set_pane_columns: qt_method!(
		fn set_pane_columns(&mut self, id: i32, columns: i32) {
			let Some(pane) = self.pane_mut(id) else {
				return;
			};
			let columns = columns.max(1);
			if pane.columns == columns {
				return;
			}
			pane.columns = columns;
			self.sync();
		}
	),

	set_pane_horizontal: qt_method!(
		fn set_pane_horizontal(&mut self, id: i32, horizontal: bool) {
			if let Some(pane) = self.pane_mut(id) {
				pane.horizontal = horizontal;
			}
		}
	),

	set_pane_geometry: qt_method!(
		fn set_pane_geometry(&mut self, id: i32, x: f64, y: f64, width: f64, height: f64) {
			if let Some(pane) = self.pane_mut(id) {
				pane.x = x;
				pane.y = y;
				pane.width = width;
				pane.height = height;
			}
		}
	),

	set_pane_keyboard: qt_method!(
		fn set_pane_keyboard(&mut self, id: i32, keyboard: bool) {
			if let Some(pane) = self.pane_mut(id) {
				pane.keyboard = keyboard;
			}
			self.sync();
		}
	),

	activate_pane: qt_method!(
		fn activate_pane(&mut self, id: i32) {
			if self.pane(id).is_none() {
				return;
			}
			self.current = id;
			if let Some(pane) = self.pane_mut(id) {
				pane.keyboard = true;
			}
			self.sync();
		}
	),

	set_pane_focus_path: qt_method!(
		fn set_pane_focus_path(&mut self, id: i32, path: String) -> bool {
			let found = self
				.pane(id)
				.and_then(|pane| pane.paths.iter().position(|entry| *entry == path));
			match found {
				Some(index) => {
					self.set_index(id, index as i32);
					true
				}
				None => false,
			}
		}
	),

	set_pane_active: qt_method!(
		fn set_pane_active(&mut self, id: i32, active: bool) {
			if let Some(pane) = self.pane_mut(id) {
				pane.active = active;
				if pane.index < 0 && pane.count() > 0 {
					pane.index = 0;
				}
			}
			self.sync();
		}
	),

	clear_pane: qt_method!(
		fn clear_pane(&mut self, id: i32) {
			if let Some(pane) = self.pane_mut(id) {
				pane.active = false;
				pane.index = -1;
			}
			self.sync();
		}
	),

	focus_first: qt_method!(
		fn focus_first(&mut self) {
			let id = self.current;
			self.set_index(id, 0);
		}
	),

	focus_last: qt_method!(
		fn focus_last(&mut self) {
			let id = self.current;
			let count = self.pane(id).map_or(0, |pane| pane.count());
			if count > 0 {
				self.set_index(id, count - 1);
			}
		}
	),

	move_focus: qt_method!(
		fn move_focus(&mut self, direction: String) -> bool {
			self.step(direction.as_str())
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
					self.step(direction.as_str());
				}
				Input::Accept => self.accept_requested(),
				Input::Cancel => self.cancel_requested(),
				Input::Menu => self.menu_requested(),
				Input::Select => self.select_requested(),
				Input::Directory => self.directory_menu_requested(),
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
	fn pane(&self, id: i32) -> Option<&Pane> {
		self.panes
			.iter()
			.find(|(pane_id, _)| *pane_id == id)
			.map(|(_, pane)| pane)
	}

	fn pane_mut(&mut self, id: i32) -> Option<&mut Pane> {
		self.panes
			.iter_mut()
			.find(|(pane_id, _)| *pane_id == id)
			.map(|(_, pane)| pane)
	}

	/// Copies the focused pane into the mirrored properties and notifies QML.
	fn sync(&mut self) {
		let current = self.current;
		let keyboard = self.panes.iter().any(|(_, pane)| pane.keyboard);

		let (active, index, path, count, columns) = match self.pane(current) {
			Some(pane) => (
				pane.active && pane.index >= 0,
				pane.index,
				pane.path(),
				pane.count(),
				pane.columns.max(1),
			),
			None => (false, -1, String::new(), 0, 1),
		};

		self.focus_active = active;
		self.focused_index = index;
		self.focused_path = path;
		self.item_count = count;
		self.grid_columns = columns;
		self.current_pane = current;
		self.view_focused = keyboard;

		self.update_status();
		self.focus_changed();
	}

	/// Nearest pane lying on the given side of the one the focus is leaving.
	fn neighbour(&self, from_id: i32, from: &Pane, direction: &str) -> Option<i32> {
		let overlaps = |a: f64, a_end: f64, b: f64, b_end: f64| a < b_end - 1.0 && b < a_end - 1.0;
		let from_x_end = from.x + from.width;
		let from_y_end = from.y + from.height;
		let mut best: Option<(f64, i32)> = None;

		for (id, pane) in &self.panes {
			if *id == from_id || pane.count() == 0 {
				continue;
			}
			let x_end = pane.x + pane.width;
			let y_end = pane.y + pane.height;

			let (eligible, gap, here, there) = match direction {
				"left" => (
					x_end <= from.x + 1.0 && overlaps(pane.y, y_end, from.y, from_y_end),
					from.x - x_end,
					from.y + from.height / 2.0,
					pane.y + pane.height / 2.0,
				),
				"right" => (
					pane.x >= from_x_end - 1.0 && overlaps(pane.y, y_end, from.y, from_y_end),
					pane.x - from_x_end,
					from.y + from.height / 2.0,
					pane.y + pane.height / 2.0,
				),
				"up" => (
					y_end <= from.y + 1.0 && overlaps(pane.x, x_end, from.x, from_x_end),
					from.y - y_end,
					from.x + from.width / 2.0,
					pane.x + pane.width / 2.0,
				),
				"down" => (
					pane.y >= from_y_end - 1.0 && overlaps(pane.x, x_end, from.x, from_x_end),
					pane.y - from_y_end,
					from.x + from.width / 2.0,
					pane.x + pane.width / 2.0,
				),
				_ => continue,
			};

			if !eligible {
				continue;
			}
			// Prefer the pane best aligned with the one being left, then the
			// smallest gap.
			let distance = (there - here).abs() * 1000.0 + gap.abs();
			if best.is_none_or(|(best_distance, _)| distance < best_distance) {
				best = Some((distance, *id));
			}
		}

		best.map(|(_, id)| id)
	}

	fn set_index(&mut self, id: i32, index: i32) {
		let Some(pane) = self.pane_mut(id) else {
			return;
		};
		let count = pane.count();
		if count == 0 {
			return;
		}
		pane.index = index.clamp(0, count - 1);
		pane.active = true;
		self.sync();
	}

	/// Moves the cursor inside the focused pane, handing the focus over to a
	/// neighbouring pane once the cursor cannot move any further.
	fn step(&mut self, direction: &str) -> bool {
		let current_id = self.current;
		let Some(pane) = self.pane(current_id).cloned() else {
			return false;
		};
		let count = pane.count();
		if count == 0 {
			return false;
		}

		if !pane.active {
			// The first directional input reveals the focus where it already
			// sits instead of moving it right away.
			let index = pane.index.max(0);
			self.set_index(current_id, index);
			return true;
		}

		let stride = pane.columns.max(1);
		let index = pane.index.clamp(0, count - 1);
		let target = if pane.horizontal {
			// Items fill a column first, then move on to the next column.
			let row = index % stride;
			let column = index / stride;
			match direction {
				"down" => {
					if row + 1 < stride && index + 1 < count {
						index + 1
					} else {
						index
					}
				}
				"up" => {
					if row > 0 {
						index - 1
					} else {
						index
					}
				}
				"right" => {
					if index + stride < count {
						index + stride
					} else {
						index
					}
				}
				"left" => {
					if column > 0 {
						index - stride
					} else {
						index
					}
				}
				_ => index,
			}
		} else {
			// Items fill a row first, then move on to the next row.
			let row = index / stride;
			let column = index % stride;
			match direction {
				"right" => {
					if column + 1 < stride && index + 1 < count {
						index + 1
					} else {
						index
					}
				}
				"left" => {
					if column > 0 {
						index - 1
					} else {
						index
					}
				}
				"down" => {
					if index + stride < count {
						index + stride
					} else {
						index
					}
				}
				"up" => {
					if row > 0 {
						index - stride
					} else {
						index
					}
				}
				_ => index,
			}
		};

		if target != index {
			if let Some(pane) = self.pane_mut(current_id) {
				pane.index = target;
			}
			self.sync();
			return true;
		}

		let Some(neighbour_id) = self.neighbour(current_id, &pane, direction) else {
			return false;
		};
		let Some(neighbour) = self.pane(neighbour_id).cloned() else {
			return false;
		};

		let (row, column) = pane.row_column();
		let entry = match direction {
			"right" => neighbour.index_at(row, 0),
			"left" => neighbour.index_at(row, neighbour.grid_columns() - 1),
			"down" => neighbour.index_at(0, column),
			"up" => neighbour.index_at(neighbour.rows() - 1, column),
			_ => 0,
		};

		self.current = neighbour_id;
		if let Some(pane) = self.pane_mut(neighbour_id) {
			pane.index = entry.max(0);
			pane.active = true;
		}
		self.sync();
		true
	}

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
		status.insert(
			"pane".to_string(),
			serde_json::Value::from(self.current_pane),
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
	const KEY_SPACE: i32 = 0x20;

	match input {
		Input::Up => Some(KEY_UP),
		Input::Down => Some(KEY_DOWN),
		Input::Left => Some(KEY_LEFT),
		Input::Right => Some(KEY_RIGHT),
		Input::Accept => Some(KEY_RETURN),
		Input::Cancel => Some(KEY_ESCAPE),
		Input::Select => Some(KEY_SPACE),
		Input::Menu | Input::Directory => None,
	}
}
