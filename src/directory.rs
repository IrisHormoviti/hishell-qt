#![allow(dead_code)]
use cpp::cpp;
use std::fs;
use std::collections::HashMap;
use std::path::PathBuf;
use qmetaobject::prelude::*;
use qmetaobject::QObjectBox;

use crate::config;
use crate::config::Config;

cpp! {{
	#include <QtCore/QMimeDatabase>
	#include <QtCore/QMimeType>
	#include <QtCore/QString>
}}

pub fn get_icon(path: &str) -> String {
	if std::path::Path::new(path).is_dir() {
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
	let path_buf = std::path::Path::new(path);
	let abs_path = std::fs::canonicalize(path_buf).unwrap_or_else(|_| path_buf.to_path_buf());

	// Check folder config
	if let Some(icon) = config::get_image(&abs_path, "DISPLAY", "Iocn") {
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
	let path_buf = std::path::Path::new(&path);

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

#[derive(Default, Clone)]
pub struct FileItem {
	pub name: QString,
	pub path: QString,
	pub is_dir: bool,
	pub icon: QString,
}

#[derive(QObject, Default)]
pub struct Directory {
	base: qt_base_class!(trait QAbstractListModel),
	items: Vec<FileItem>,
	config: QObjectBox<Config>,
	config_changed: qt_signal!(),

	path: qt_property!(String; READ get_path WRITE set_path NOTIFY path_changed),
	path_str: String,
	path_changed: qt_signal!(),

	get_icon: qt_method!(
		fn get_icon(&self, path: QString) -> QString {
			get_icon(&path.to_string()).into()
		}
	),

	open_path: qt_method!(
		pub fn open_path(&mut self, path: String) {
			let path_buf = std::path::Path::new(&path);
			if path_buf.is_file() {
				open_file(path)
			} else {
				self.set_path(path.into());
			}
		}
	),

	load_directory: qt_method!(
		pub fn load_directory(&mut self, path: String, include_hidden: bool) {
			self.begin_reset_model();
			self.items.clear();

			if let Ok(entries) = fs::read_dir(path) {
				for entry in entries.flatten() {
					let name = entry.file_name().to_string_lossy().to_string();

					if name.starts_with('.') && !include_hidden {
						continue;
					}

					let p = entry.path().to_string_lossy().to_string();
					let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);
					let icon = get_icon(&p).into();

					self.items.push(FileItem {
						name: name.into(),
									path: p.into(),
									is_dir,
									icon,
					});
				}
			}

			self.items
			.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name)));

			self.end_reset_model();
		}
	)
}

impl Directory {
	pub fn get_path(&self) -> String {
		self.path_str.clone().into()
	}

	pub fn set_path(&mut self, path: String) {
		let path_buf = std::path::Path::new(&path);

		let abs_path = std::fs::canonicalize(path_buf)
		.unwrap_or_else(|_| path_buf.to_path_buf());

		let abs_str = abs_path.to_string_lossy().to_string();

		self.path_str = abs_str.clone();
		self.load_directory(abs_str, false);
		self.config.pinned().borrow_mut().load(path);

		self.path_changed();
		self.config_changed();
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
			0x0100 => item.name.clone().into(),
			0x0101 => item.path.clone().into(),
			0x0102 => item.is_dir.into(),
			0x0103 => item.icon.clone().into(),
			_ => QVariant::default(),
		}
	}

	fn role_names(&self) -> HashMap<i32, QByteArray> {
		let mut map = HashMap::new();
		map.insert(0x0100, "name".into());
		map.insert(0x0101, "path".into());
		map.insert(0x0102, "is_dir".into());
		map.insert(0x0103, "icon".into());
		map
	}
}
