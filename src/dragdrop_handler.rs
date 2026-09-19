use crate::bridge::ffi::{DragDropHandler, QString, QStringList, QVariant};
use core::pin::Pin;
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

pub struct DragDropHandlerRust {
	pub drag_action: QString,
	pub drag_cursor_x: f64,
	pub drag_cursor_y: f64,
	pub tooltip_active: bool,
	pub active_dragged_paths: QStringList,
	pub drag_icon_width: f64,
	pub drag_icon_height: f64,
	pub drag_uris: QStringList,
	pub drag_source_paths: QStringList,
	pub item_count: i32,
	pub file_title: QString,
	pub file_icon: QString,
	pub dragged_slot: QVariant,
	pub shake_history_json: QString,
	pub window: QVariant,
}

impl Default for DragDropHandlerRust {
	fn default() -> Self {
		Self {
			drag_action: QString::from("copy"),
			drag_cursor_x: 0.0,
			drag_cursor_y: 0.0,
			tooltip_active: false,
			active_dragged_paths: QStringList::default(),
			drag_icon_width: 0.0,
			drag_icon_height: 0.0,
			drag_uris: QStringList::default(),
			drag_source_paths: QStringList::default(),
			item_count: 0,
			file_title: QString::default(),
			file_icon: QString::default(),
			dragged_slot: QVariant::default(),
			shake_history_json: QString::default(),
			window: QVariant::default(),
		}
	}
}

impl DragDropHandler {
	pub fn track_mouse_shake(mut self: Pin<&mut Self>, x: f64, y: f64) {
		self.as_mut().set_drag_cursor_x(x);
		self.as_mut().set_drag_cursor_y(y);
		self.as_mut().drag_cursor_changed();

		let now = Self::now_ms();
		let mut history: Vec<ShakePosition> = self.get_shake_positions();
		history.push(ShakePosition { x, y, time: now });

		history.retain(|p| now.saturating_sub(p.time) <= 450);
		self.as_mut().set_shake_positions(&history);

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
			self.as_mut().cycle_drag_action();
			self.as_mut().set_shake_positions(&[]);
		}
	}

	pub fn cycle_drag_action(mut self: Pin<&mut Self>) {
		let current = self.get_drag_action_enum();
		let next = current.next();
		self.as_mut().set_drag_action(QString::from(next.as_str()));
		self.as_mut().drag_action_changed();
	}

	pub fn reset(mut self: Pin<&mut Self>) {
		self.as_mut().set_active_dragged_paths(QStringList::default());
		self.as_mut().active_dragged_paths_changed();
		self.as_mut().set_tooltip_active(false);
		self.as_mut().tooltip_active_changed();
		self.as_mut().set_shake_positions(&[]);
	}

	pub fn set_drag_data(
		mut self: Pin<&mut Self>,
		_main_path: &QString,
		uris: &QStringList,
		source_paths: &QStringList,
		item_count: i32,
		file_title: &QString,
		file_icon: &QString,
	) {
		self.as_mut().set_drag_uris(uris.clone());
		self.as_mut().set_drag_source_paths(source_paths.clone());
		self.as_mut().set_item_count(item_count);
		self.as_mut().set_file_title(file_title.clone());
		self.as_mut().set_file_icon(file_icon.clone());
		self.as_mut().set_drag_action(QString::from("copy"));
		self.as_mut().drag_action_changed();
	}

	pub fn begin_drag(mut self: Pin<&mut Self>, _image_url: &QString, width: f64, height: f64) {
		self.as_mut().set_drag_icon_width(width);
		self.as_mut().set_drag_icon_height(height);
		let sources = self.rust().drag_source_paths.clone();
		self.as_mut().set_active_dragged_paths(sources);
		self.as_mut().active_dragged_paths_changed();
		self.as_mut().set_tooltip_active(true);
		self.as_mut().tooltip_active_changed();
	}

	pub fn end_drag(mut self: Pin<&mut Self>) {
		self.as_mut().set_active_dragged_paths(QStringList::default());
		self.as_mut().active_dragged_paths_changed();
		self.as_mut().set_tooltip_active(false);
		self.as_mut().tooltip_active_changed();
		self.as_mut().set_drag_icon_width(0.0);
		self.as_mut().set_drag_icon_height(0.0);
	}

	fn now_ms() -> u64 {
		SystemTime::now()
			.duration_since(UNIX_EPOCH)
			.unwrap_or_default()
			.as_millis() as u64
	}

	fn get_drag_action_enum(&self) -> DragAction {
		match self.drag_action().to_string().as_str() {
			"move" => DragAction::Move,
			"link" => DragAction::Link,
			_ => DragAction::Copy,
		}
	}

	fn get_shake_positions(&self) -> Vec<ShakePosition> {
		let json = self.shake_history_json().to_string();
		if json.is_empty() {
			return Vec::new();
		}
		serde_json::from_str(&json).unwrap_or_default()
	}

	fn set_shake_positions(mut self: Pin<&mut Self>, positions: &[ShakePosition]) {
		let json = serde_json::to_string(positions).unwrap_or_default();
		self.as_mut().set_shake_history_json(QString::from(&json));
	}
}
