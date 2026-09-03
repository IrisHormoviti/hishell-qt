use qmetaobject::{QStringList, prelude::*};
use serde_json;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy, Debug, PartialEq, serde::Serialize, serde::Deserialize)]
pub enum DragAction {
	Copy,
	Move,
	Link,
}

impl Default for DragAction {
	fn default() -> Self {
		DragAction::Copy
	}
}

impl DragAction {
	fn as_str(&self) -> &'static str {
		match self {
			DragAction::Copy => "copy",
			DragAction::Move => "move",
			DragAction::Link => "link",
		}
	}

	fn next(&self) -> Self {
		match self {
			DragAction::Copy => DragAction::Move,
			DragAction::Move => DragAction::Link,
			DragAction::Link => DragAction::Copy,
		}
	}
}

#[derive(Clone, Copy, Debug, serde::Serialize, serde::Deserialize)]
struct ShakePosition {
	x: f64,
	y: f64,
	time: u64,
}

#[derive(QObject, Default)]
pub struct DragDropHandler {
	base: qt_base_class!(trait QObject),

	drag_action: qt_property!(String; NOTIFY drag_action_changed),
	drag_cursor_x: qt_property!(f64; NOTIFY drag_cursor_changed),
	drag_cursor_y: qt_property!(f64; NOTIFY drag_cursor_changed),
	tooltip_active: qt_property!(bool; NOTIFY tooltip_active_changed),
	active_dragged_paths: qt_property!(QStringList; NOTIFY active_dragged_paths_changed),
	drag_icon_width: qt_property!(f64),
	drag_icon_height: qt_property!(f64),
	drag_uris: qt_property!(QStringList),
	drag_source_paths: qt_property!(QStringList),
	item_count: qt_property!(i32),
	file_title: qt_property!(String),
	file_icon: qt_property!(String),
	dragged_slot: qt_property!(QVariant),
	shake_history_json: qt_property!(String),
	window: qt_property!(QVariant),

	drag_action_changed: qt_signal!(),
	drag_cursor_changed: qt_signal!(),
	tooltip_active_changed: qt_signal!(),
	active_dragged_paths_changed: qt_signal!(),

	track_mouse_shake: qt_method!(
		fn track_mouse_shake(&mut self, x: f64, y: f64) {
			self.drag_cursor_x = x;
			self.drag_cursor_y = y;
			self.drag_cursor_changed();

			let now = Self::now_ms();
			let mut history: Vec<ShakePosition> = self.get_shake_positions();
			history.push(ShakePosition { x, y, time: now });

			history.retain(|p| now.saturating_sub(p.time) <= 450);
			self.set_shake_positions(&history);

			if history.len() < 5 {
				return;
			}

			let mut reversals = 0;
			let mut last_dx = 0.0;
			let mut last_dy = 0.0;
			let mut total_distance = 0.0;

			for i in 1..history.len() {
				let dx = history[i].x - history[i - 1].x;
				let dy = history[i].y - history[i - 1].y;
				let dist = (dx * dx + dy * dy).sqrt();
				total_distance += dist;

				if (dx > 3.0 && last_dx < -3.0) || (dx < -3.0 && last_dx > 3.0) {
					reversals += 1;
				} else if (dy > 3.0 && last_dy < -3.0) || (dy < -3.0 && last_dy > 3.0) {
					reversals += 1;
				}

				if dx.abs() > 2.0 {
					last_dx = dx;
				}
				if dy.abs() > 2.0 {
					last_dy = dy;
				}
			}

			if reversals >= 3 && total_distance > 50.0 {
				self.cycle_drag_action();
				self.set_shake_positions(&[]);
			}
		}
	),

	cycle_drag_action: qt_method!(
		fn cycle_drag_action(&mut self) {
			let current = self.get_drag_action_enum();
			let next = current.next();
			self.drag_action = next.as_str().into();
			self.drag_action_changed();
		}
	),

	reset: qt_method!(
		fn reset(&mut self) {
			self.active_dragged_paths = QStringList::new();
			self.active_dragged_paths_changed();
			self.tooltip_active = false;
			self.tooltip_active_changed();
			self.set_shake_positions(&[]);
		}
	),

	set_drag_data: qt_method!(
		fn set_drag_data(
			&mut self,
			_main_path: String,
			uris: QStringList,
			source_paths: QStringList,
			item_count: i32,
			file_title: String,
			file_icon: String,
		) {
			self.drag_uris = uris;
			self.drag_source_paths = source_paths;
			self.item_count = item_count;
			self.file_title = file_title.into();
			self.file_icon = file_icon.into();
			self.drag_action = "copy".into();
			self.drag_action_changed();
		}
	),

	begin_drag: qt_method!(
		fn begin_drag(&mut self, _image_url: String, width: f64, height: f64) {
			self.drag_icon_width = width;
			self.drag_icon_height = height;
			self.active_dragged_paths = self.drag_source_paths.clone();
			self.active_dragged_paths_changed();
			self.tooltip_active = true;
			self.tooltip_active_changed();
		}
	),

	end_drag: qt_method!(
		fn end_drag(&mut self) {
			self.active_dragged_paths = QStringList::new();
			self.active_dragged_paths_changed();
			self.tooltip_active = false;
			self.tooltip_active_changed();
			self.drag_icon_width = 0.0;
			self.drag_icon_height = 0.0;
		}
	),
}

impl DragDropHandler {
	fn now_ms() -> u64 {
		SystemTime::now()
			.duration_since(UNIX_EPOCH)
			.unwrap_or_default()
			.as_millis() as u64
	}

	fn get_drag_action_enum(&self) -> DragAction {
		match self.drag_action.to_string().as_str() {
			"move" => DragAction::Move,
			"link" => DragAction::Link,
			_ => DragAction::Copy,
		}
	}

	fn get_shake_positions(&self) -> Vec<ShakePosition> {
		if self.shake_history_json.is_empty() {
			return Vec::new();
		}
		serde_json::from_str(&self.shake_history_json).unwrap_or_default()
	}

	fn set_shake_positions(&mut self, positions: &[ShakePosition]) {
		self.shake_history_json = serde_json::to_string(positions).unwrap_or_default();
	}
}
