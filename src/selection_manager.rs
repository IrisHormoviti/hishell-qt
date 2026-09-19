use cxx_qt_lib::{QStringList, QString, QVariant};
use std::collections::HashMap;

pub struct SelectionManagerRust {
	pub selection_active: bool,
	pub selected_paths: QString,
	pub selected_count: i32,
	pub last_selected_index: i32,
	pub selection_status: QString,
	pub window: QVariant,
}

impl Default for SelectionManagerRust {
	fn default() -> Self {
		Self {
			selection_active: false,
			selected_paths: QString::default(),
			selected_count: 0,
			last_selected_index: -1,
			selection_status: QString::default(),
			window: QVariant::default(),
		}
	}
}

impl SelectionManagerRust {
	fn get_selected_paths(&self) -> HashMap<String, bool> {
		let s = self.selected_paths.to_string();
		if s.is_empty() {
			return HashMap::new();
		}
		serde_json::from_str(&s).unwrap_or_default()
	}

	fn update_status(&mut self) {
		let paths: Vec<String> = self.get_selected_paths().into_keys().collect();
		let mut status = serde_json::Map::new();
		status.insert("count".to_string(), serde_json::Value::from(self.selected_count));
		status.insert("paths".to_string(), serde_json::Value::from(paths));
		let json = serde_json::to_string(&status).unwrap_or_default();
		self.selection_status = QString::from(json.as_str());
	}
}

use crate::bridge::ffi::SelectionManager;
use std::pin::Pin;

impl SelectionManager {
	pub fn enter_selection_mode(mut self: Pin<&mut Self>) {
		if !*self.selection_active() {
			self.as_mut().set_selection_active(true);
			self.rust_mut().update_status();
			self.as_mut().selection_changed();
		}
	}

	pub fn exit_selection_mode(mut self: Pin<&mut Self>) {
		if *self.selection_active() {
			self.as_mut().set_selection_active(false);
			self.as_mut().set_selected_paths(QString::default());
			self.as_mut().set_selected_count(0);
			self.as_mut().set_last_selected_index(-1);
			self.rust_mut().update_status();
			self.as_mut().selection_changed();
		}
	}

	pub fn toggle_selection(mut self: Pin<&mut Self>, path: &QString, idx: i32) {
		if !*self.selection_active() {
			self.as_mut().enter_selection_mode();
		}
		let mut sel = self.rust().get_selected_paths();
		let path_str = path.to_string();
		if sel.contains_key(&path_str) {
			sel.remove(&path_str);
		} else {
			sel.insert(path_str, true);
		}
		let count = sel.len() as i32;
		let json = serde_json::to_string(&sel).unwrap_or_default();
		self.as_mut().set_selected_count(count);
		self.as_mut().set_selected_paths(QString::from(json.as_str()));
		self.as_mut().set_last_selected_index(idx);
		self.rust_mut().update_status();
		if count == 0 {
			self.exit_selection_mode();
		} else {
			self.as_mut().selection_changed();
		}
	}

	pub fn range_select(mut self: Pin<&mut Self>, from_idx: i32, to_idx: i32) {
		self.as_mut().set_last_selected_index(from_idx.max(to_idx));
		self.rust_mut().update_status();
	}

	pub fn select_all(mut self: Pin<&mut Self>, paths: &QStringList) {
		self.as_mut().set_selection_active(true);
		let mut sel = HashMap::new();
        
		for path in paths.into_iter() {
			let path_str = path.to_string();
			if !path_str.is_empty() {
				sel.insert(path_str, true);
			}
		}

		let count = sel.len() as i32;
		let json = serde_json::to_string(&sel).unwrap_or_default();
		self.as_mut().set_selected_count(count);
		self.as_mut().set_selected_paths(QString::from(json.as_str()));
		self.rust_mut().update_status();
		self.as_mut().selection_changed();
	}

	pub fn deselect_all(self: Pin<&mut Self>) {
		self.exit_selection_mode();
	}

	pub fn get_selected_path_list(&self) -> QStringList {
		let mut list = QStringList::default();
		for key in self.rust().get_selected_paths().into_keys() {
			list.append(QString::from(key.as_str()));
		}
		list
	}

	pub fn clear(self: Pin<&mut Self>) {
		self.exit_selection_mode();
	}
}
