#![allow(dead_code)]
use cpp::cpp;
use std::fs;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use qmetaobject::prelude::*;
use qmetaobject::QObjectBox;

use crate::config;
use crate::config::Config;

cpp! {{
	#include <QtCore/QMimeDatabase>
	#include <QtCore/QMimeType>
	#include <QtCore/QString>
}}

#[derive(Default, Clone)]
pub struct FileItem {
	pub name: String,
	pub title: String,
	pub path: String,
	pub is_dir: bool,
	pub icon: String,
}

#[derive(QObject, Default)]
pub struct Directory {
	base: qt_base_class!(trait QAbstractListModel),
	items: Vec<FileItem>,

	config: QObjectBox<Config>,
	config_prop: qt_property!(QVariant; READ get_config NOTIFY config_changed ALIAS config),
	config_changed: qt_signal!(),

	title: qt_property!(String; READ get_title),
	icon: qt_property!(String; READ get_icon NOTIFY path_changed),

	path: qt_property!(String; READ get_path WRITE set_path NOTIFY path_changed),
	path_str: String,
	path_changed: qt_signal!(),

	open_path: qt_method!(
		pub fn open_path(&mut self, path: String) {
			let path_buf = Path::new(&path);
			if path_buf.is_file() {
				open_file(path)
			} else {
				self.set_path(path);
			}
		}
	),

	load_directory: qt_method!(
		fn load_directory(&mut self, path: String, include_hidden: bool) {
			Directory::new(self, path, include_hidden);
		}
	)
}

impl Directory {
	pub fn new(&mut self, path: String, include_hidden: bool) {
		self.begin_reset_model();
		self.items.clear();

		if let Ok(entries) = fs::read_dir(path) {
			for entry in entries.flatten() {
				let name = entry.file_name().to_string_lossy().to_string();

				if name.starts_with('.') && !include_hidden {
					continue;
				}

				let entry_path = entry.path();
				let p = entry_path.to_string_lossy().to_string();
				let title = get_item_title(&entry_path);
				let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);
				let icon = get_icon(&p);


				self.items.push(FileItem {
					name,
					title,
					path: p,
					is_dir,
					icon,
				});
			}
		}

		self.items
		.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name)));

		self.end_reset_model();
	}

	pub fn get_path(&self) -> String {
		self.path_str.clone()
	}

	pub fn get_config(&self) -> QVariant {
		QVariant::from(self.config.pinned())
	}

	pub fn get_icon(&self) -> String {
		if self.path_str.is_empty() {
			return "folder".to_string();
		}
		get_icon(&self.path_str)
	}

	pub fn set_path(&mut self, path: String) {
		if path.is_empty() {
			return;
		}

		let path_buf = Path::new(&path);
		let abs_path = std::fs::canonicalize(path_buf)
		.unwrap_or_else(|_| path_buf.to_path_buf());
		let abs_str = abs_path.to_string_lossy().to_string();

		self.path_str = abs_str.clone();

		let load_path = if abs_path.is_file() {
			abs_path.parent().map(|p| p.to_string_lossy().to_string()).unwrap_or(abs_str.clone())
		} else {
			abs_str.clone()
		};

		self.load_directory(load_path.clone(), false);
		self.config.pinned().borrow_mut().load(load_path);

		self.path_changed();
		self.config_changed();
	}

	pub fn get_title(&self) -> String {
		get_item_title(Path::new(&self.path_str))
	}
}

impl QAbstractListModel for Directory {
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
			0x0100 => QString::from(item.name.as_str()).into(),
			0x0101 => QString::from(item.path.as_str()).into(),
			0x0102 => item.is_dir.into(),
			0x0103 => QString::from(item.icon.as_str()).into(),
			0x0104 => QString::from(item.title.as_str()).into(),
			_ => QVariant::default(),
		}
	}

	fn role_names(&self) -> HashMap<i32, QByteArray> {
		let mut map = HashMap::new();
		map.insert(0x0100, "name".into());
		map.insert(0x0101, "path".into());
		map.insert(0x0102, "is_dir".into());
		map.insert(0x0103, "icon".into());
		map.insert(0x0104, "title".into());
		map
	}
}

pub fn get_item_title(path: &Path) -> String {
	if let Some(config_title) = config::get_string(path, "DISPLAY", "Title") {
		if !config_title.is_empty() {
			return config_title;
		}
	}

	path.file_name()
		.map(|name| name.to_string_lossy().to_string())
		.unwrap_or_else(|| path.to_string_lossy().to_string())
}

pub fn get_icon(path: &str) -> String {
	if Path::new(path).is_dir() {
		return get_folder_icon(path);
	} else {
		let qpath = QString::from(path);
		let icon_name = cpp!(unsafe [qpath as "QString"] -> QString as "QString" {
			QMimeDatabase db;
			return db.mimeTypeForFile(qpath).iconName();
		});

		icon_name.to_string()
	}
}

pub fn get_folder_icon(path: &str) -> String {
	let path_buf = Path::new(path);
	let abs_path = std::fs::canonicalize(path_buf).unwrap_or_else(|_| path_buf.to_path_buf());

	// Passing &abs_path (&PathBuf) auto-coerces to &Path
	if let Some(icon) = config::get_image(&abs_path, "DISPLAY", "Icon") {
		if !icon.is_empty() {
			return icon;
		}
	}

	// Check .directory
	let dot_directory = abs_path.join(".directory");
	if let Some(icon) = crate::desktop_entry::get_icon(&dot_directory) {
		return icon;
	}

	// XDG Special folders
	if let Some(home) = dirs::home_dir().and_then(|h| std::fs::canonicalize(h).ok()) {
		if abs_path == home {
			return "user-home".to_string();
		}

		let xdg_dirs: &[(fn() -> Option<PathBuf>, &str, &str)] = &[
			(dirs::desktop_dir, "Desktop", "folder-desktop"),
			(dirs::download_dir, "Downloads", "folder-download"),
			(dirs::picture_dir, "Pictures", "folder-pictures"),
			(dirs::audio_dir, "Music", "folder-music"),
			(dirs::video_dir, "Videos", "folder-videos"),
			(dirs::document_dir, "Documents", "folder-documents"),
			(dirs::template_dir, "Templates", "folder-templates"),
			(dirs::public_dir, "Public", "folder-public"),
		];

		for (get_dir, fallback_name, icon) in xdg_dirs {
			let target_path = get_dir()
			.and_then(|d| std::fs::canonicalize(d).ok())
			.unwrap_or_else(|| home.join(fallback_name));

			if abs_path == target_path {
				return icon.to_string();
			}
		}
	}

	// fallback
	"folder".to_string()
}

pub fn open_file(path: String) {
	let path_buf = Path::new(&path);

	let mut is_exec = false;
	if let Ok(mut file) = std::fs::File::open(&path_buf) {
		use std::io::Read;
		let mut buffer = [0; 4];
		if file.read_exact(&mut buffer).is_ok() {
			if buffer == [0x7f, b'E', b'L', b'F'] || (buffer[0] == b'#' && buffer[1] == b'!') {
				is_exec = true;
			}
		}
	}

	#[cfg(unix)]
	if !is_exec {
		use std::os::unix::fs::PermissionsExt;
		is_exec = std::fs::metadata(&path_buf)
		.map(|m| m.permissions().mode() & 0o111 != 0)
		.unwrap_or(false);
	}

	if is_exec {
		let _ = std::process::Command::new(&path).spawn();
		return;
	}

	let _ = std::process::Command::new("xdg-open").arg(&path).spawn();
}
