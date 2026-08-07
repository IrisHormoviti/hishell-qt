#![allow(dead_code)]
use mime_guess::from_path;
use std::fs;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use qmetaobject::prelude::*;
use qmetaobject::QObjectBox;
use once_cell::sync::Lazy;
use std::sync::Mutex;
use std::process::Command;

use crate::config;
use crate::config::Config;
use crate::thumbnailer;

static ICON_CACHE: Lazy<Mutex<HashMap<String, String>>> = Lazy::new(|| Mutex::new(HashMap::new()));

fn query_gio_icon(path: &str) -> Option<String> {
	if let Ok(output) = Command::new("gio").arg("info").arg(path).output() {
		if output.status.success() {
			let out = String::from_utf8_lossy(&output.stdout);
			for line in out.lines() {
				if line.contains("standard::icon") {
					// Try to extract a reasonable icon token from the line.
					// First, look for quoted tokens.
					if let Some(start) = line.find('\'') {
						if let Some(end_rel) = line[start+1..].find('\'') {
							let icon = &line[start+1..start+1+end_rel];
							if !icon.is_empty() {
								return Some(icon.to_string());
							}
						}
					}

					// If no quoted token, split the remainder into candidate tokens
					if let Some(pos) = line.find(':') {
						let rem = line[pos+1..].trim();
						// split on common separators and examine candidates
						for raw in rem.split(|c: char| c == '[' || c == ']' || c == ',' || c == ' ' || c == '\'' || c == '"') {
							let tok = raw.trim();
							if tok.is_empty() { continue; }
							// prefer tokens that look like icon names (contain '-') or short words
							if tok.contains('-') || (tok.len() <= 20 && tok.chars().all(|c| c.is_alphanumeric() || c == '.' || c == '_' )) {
								return Some(tok.to_string());
							}
						}
					}
				}
			}
		}
	}
	None
}

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
	has_meta: qt_property!(bool; READ get_has_meta NOTIFY path_changed),

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

	poll_thumbnails: qt_method!(
		pub fn poll_thumbnails(&mut self) {
			let updates = crate::thumbnailer::drain_results();
			if updates.is_empty() {
				return;
			}
			for (src, dst) in updates {
				if let Some(idx) = self.items.iter().position(|it| it.path == src) {
					self.items[idx].icon = format!("file://{}", dst);
				}
			}
			// notify QML to refresh model (use model reset to avoid triggering path reloads)
			self.begin_reset_model();
			self.end_reset_model();
		}
	),

	set_config: qt_method!(
		pub fn set_config(&mut self, section: String, key: String, value: String, local: bool) {
			self.config.pinned().borrow_mut()._set(Path::new(&self.path_str), &section, &key, &value, local);
			self.config_changed();
		}
	),

	refresh: qt_method!(
		pub fn refresh(&mut self) {
			self.path_changed()
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
				let mut icon = get_icon(&p);

				// enqueue thumbnail generation for images/videos and use cached thumbnail if available
				if !is_dir {
					let size = self.config.pinned().borrow().grid_size as u32;
					if let Some(ext) = Path::new(&p).extension().and_then(|e| e.to_str()) {
						let ext_l = ext.to_lowercase();
						let image_exts = ["png", "jpg", "jpeg", "bmp", "gif", "webp", "avif", "tiff", "svg", "kra", "desktop", "appimage"];
						let video_exts = ["mp4", "mkv", "webm", "avi", "mov", "mpeg", "mpg"];
						// also allow filenames that end with .AppImage even if ext detection fails
						let fname = Path::new(&p).file_name().and_then(|n| n.to_str()).unwrap_or("").to_lowercase();
						let is_appimage_name = fname.ends_with(".appimage");
						if image_exts.contains(&ext_l.as_str()) || video_exts.contains(&ext_l.as_str()) || is_appimage_name {
							if let Some(uri) = thumbnailer::thumbnail_uri_if_exists(Path::new(&p), size) {
								icon = uri;
							} else {
								// avoid generating thumbnails for very large files
								const MAX_BYTES: u64 = 10 * 1024 * 1024; // 10 MB
								match fs::metadata(&p) {
									Ok(meta) => {
										if meta.len() <= MAX_BYTES {
											thumbnailer::enqueue(Path::new(&p), size);
										}
									}
									Err(_) => {
										thumbnailer::enqueue(Path::new(&p), size);
									}
								}
							}
						}
					}
				}


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

	pub fn get_has_meta(&self) -> bool {
		if self.path_str.is_empty() {
			return false;
		}
		Path::new(&self.path_str).join(".meta").is_file()
	}

	pub fn set_path(&mut self, path: String) {
		if path.is_empty() {
			return;
		}

		// ignore spurious current-dir assignments coming from QML during startup
		if path == "." || path == "./" || path == "/./" {
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
		// Prefer system icons via `gio` when available, caching per-extension or per-mime.
		let mime = from_path(path).first_or_octet_stream().essence_str().to_string();
		let key = if let Some(ext) = Path::new(path).extension().and_then(|e| e.to_str()) {
			format!("ext:{}", ext.to_lowercase())
		} else {
			format!("mime:{}", mime)
		};

		if let Some(cached) = ICON_CACHE.lock().unwrap().get(&key) {
			return cached.clone();
		}

		if let Some(icon) = query_gio_icon(path) {
			ICON_CACHE.lock().unwrap().insert(key.clone(), icon.clone());
			return icon;
		}

		// fallback: map common mime types to generic icons
		let icon = if mime.starts_with("image/") {
			"image-x-generic".to_string()
		} else if mime.starts_with("video/") {
			"video-x-generic".to_string()
		} else if mime.starts_with("text/") {
			"text-x-generic".to_string()
		} else {
			"text-x-generic".to_string()
		};

		ICON_CACHE.lock().unwrap().insert(key, icon.clone());
		icon
	}
}

pub fn get_folder_icon(path: &str) -> String {
	let path_buf = Path::new(path);
	let abs_path = std::fs::canonicalize(path_buf).unwrap_or_else(|_| path_buf.to_path_buf());

	if let Some(icon) = config::get_image(&abs_path, "DISPLAY", "Icon") {
		if !icon.is_empty() {
			return icon;
		}
	}

	let dot_directory = abs_path.join(".directory");
	if let Some(icon) = crate::desktop_entry::get_icon(&dot_directory) {
		return icon;
	}

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
