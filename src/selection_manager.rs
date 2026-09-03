use qmetaobject::prelude::*;
use serde_json;
use std::collections::HashMap;

#[derive(QObject, Default)]
pub struct SelectionManager {
	base: qt_base_class!(trait QObject),

	selection_active: qt_property!(bool; NOTIFY selection_changed),
	selected_paths: qt_property!(String; NOTIFY selection_changed),
	selected_count: qt_property!(i32; NOTIFY selection_changed),
	last_selected_index: qt_property!(i32; NOTIFY selection_changed),
    // NEW PROPERTY: Consolidated status for QML binding
    selection_status: qt_property!(String; NOTIFY selection_changed), 
	window: qt_property!(QVariant),

	selection_changed: qt_signal!(),

	enter_selection_mode: qt_method!(
		fn enter_selection_mode(&mut self) {
			if !self.selection_active {
				self.selection_active = true;
                // Update status when entering selection mode
                self.update_status(); 
				self.selection_changed();
			}
		}
	),

	exit_selection_mode: qt_method!(
		fn exit_selection_mode(&mut self) {
			if self.selection_active {
				self.selection_active = false;
				self.selected_paths = String::new();
				self.last_selected_index = -1;
                // Update status when exiting selection mode
                self.update_status();
				self.selection_changed();
			}
		}
	),

	toggle_selection: qt_method!(
		fn toggle_selection(&mut self, path: String, idx: i32) {
			if !self.selection_active {
				self.enter_selection_mode();
			}
			let mut sel = self.get_selected_paths();
			if sel.contains_key(&path) {
				sel.remove(&path);
			} else {
				sel.insert(path, true);
			}
			self.selected_paths = serde_json::to_string(&sel).unwrap_or_default();
			self.last_selected_index = idx;
            // Update status after changing selection
            self.update_status(); 

			if self.selected_count == 0 {
				self.exit_selection_mode();
			} else {
				self.selection_changed();
			}
		}
	),

	range_select: qt_method!(
		fn range_select(&mut self, from_idx: i32, to_idx: i32) {
			self.last_selected_index = from_idx.max(to_idx);
            // Update status when changing selection range
            self.update_status(); 
		}
	),

	select_all: qt_method!(
		fn select_all(&mut self) {
			self.selection_active = true;
            // Assuming 'select all' populates the paths, we just trigger update/signal
            self.update_status(); 
			self.selection_changed();
		}
	),

	deselect_all: qt_method!(
		fn deselect_all(&mut self) {
			self.exit_selection_mode();
		}
	),

	get_selected_path_list: qt_method!(
		fn get_selected_path_list(&self) -> String {
			self.get_selected_paths()
				.keys()
				.cloned()
				.collect::<Vec<_>>()
				.join("\n")
		}
	),

	clear: qt_method!(
		fn clear(&mut self) {
			self.exit_selection_mode();
		}
	),
}

impl SelectionManager {
    // Helper function to generate the consolidated status JSON
    fn update_status(&mut self) {
        let mut status = HashMap::new();
        status.insert("count".to_string(), serde_json::Value::from(self.selected_count));
        status.insert("paths".to_string(), serde_json::Value::from(self.get_selected_paths().keys().cloned().collect::<Vec<String>>()));
        // This new property will hold the consolidated status JSON string
        self.selection_status = serde_json::to_string(&status).unwrap_or_default();
    }

	fn get_selected_paths(&self) -> HashMap<String, bool> {
		if self.selected_paths.is_empty() {
			return HashMap::new();
		}
		serde_json::from_str(&self.selected_paths).unwrap_or_default()
	}
}
