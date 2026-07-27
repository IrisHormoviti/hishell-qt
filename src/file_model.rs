use qmetaobject::prelude::*;
use std::collections::HashMap;
use std::fs;

#[derive(Default, Clone)]
pub struct FileItem {
	pub name: QString,
	pub path: QString,
	pub is_dir: bool,
}

#[derive(QObject, Default)]
pub struct FileModel {
	base: qt_base_class!(trait QAbstractListModel),

	items: Vec<FileItem>,

	current_path: qt_property!(QString; READ get_current_path WRITE set_current_path NOTIFY current_path_changed),
	current_path_str: String,
	current_path_changed: qt_signal!(),
}

impl FileModel {
	pub fn get_current_path(&self) -> QString {
		self.current_path_str.clone().into()
	}

	pub fn set_current_path(&mut self, path: QString) {
		let p = path.to_string();
		self.current_path_str = p.clone();
		self.load_directory(&p);
		self.current_path_changed();
	}

	pub fn load_directory(&mut self, path: &str) {
		self.begin_reset_model();
		self.items.clear();

		if let Ok(entries) = fs::read_dir(path) {
			for entry in entries.flatten() {
				let name = entry.file_name().to_string_lossy().to_string();
				let p = entry.path().to_string_lossy().to_string();
				let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);

				self.items.push(FileItem {
					name: name.into(),
					path: p.into(),
					is_dir,
				});
			}
		}

		self.items
			.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name)));

		self.end_reset_model();
	}
}

impl QAbstractListModel for FileModel {
	fn row_count(&self) -> i32 {
		self.items.len() as i32
	}

	fn data(&self, index: QModelIndex, role: i32) -> QVariant {
		let idx = index.row() as usize;
		if idx >= self.items.len() {
			return QVariant::default();
		}
		let item = &self.items[idx];
		match role {
			0x0100 => item.name.clone().into(),
			0x0101 => item.path.clone().into(),
			0x0102 => item.is_dir.into(),
			_ => QVariant::default(),
		}
	}

	fn role_names(&self) -> HashMap<i32, QByteArray> {
		let mut map = HashMap::new();
		map.insert(0x0100, "name".into());
		map.insert(0x0101, "path".into());
		map.insert(0x0102, "is_dir".into());
		map
	}
}
