#![allow(dead_code)]
use crate::bridge::ffi::{
	Config, Directory, DirectoryRust, QHash_i32_QByteArray, QModelIndex, QString, QStringList, QVariant,
};
use crate::config;
use crate::thumbnailer;
use core::pin::Pin;
use cxx_qt_lib::{QByteArray, QHash, QHashPair_i32_QByteArray};
use mime_guess::from_path;
use once_cell::sync::Lazy;
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use cxx_qt::CxxQtType;

static ICON_CACHE: Lazy<Mutex<HashMap<String, String>>> = Lazy::new(|| Mutex::new(HashMap::new()));

fn query_gio_icon(path: &Path) -> Option<String> {
	if let Ok(output) = Command::new("gio").arg("info").arg(path).output() {
		if output.status.success() {
			let out = String::from_utf8_lossy(&output.stdout);
			for line in out.lines() {
				if line.contains("standard::icon") {
					if let Some(start) = line.find('\'') {
						if let Some(end_rel) = line[start + 1..].find('\'') {
							let icon = &line[start + 1..start + 1 + end_rel];
							if !icon.is_empty() {
								return Some(icon.to_string());
							}
						}
					}

					if let Some(pos) = line.find(':') {
						let rem = line[pos + 1..].trim();
						for raw in rem.split(|c: char| {
							c == '[' || c == ']' || c == ',' || c == ' ' || c == '\'' || c == '"'
						}) {
							let tok = raw.trim();
							if tok.is_empty() {
								continue;
							}
							if tok.contains('-')
								|| (tok.len() <= 20
									&& tok
										.chars()
										.all(|c| c.is_alphanumeric() || c == '.' || c == '_'))
							{
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

pub struct DirectoryRust {
	pub config: *mut Config,
	pub title: QString,
	pub icon: QString,
	pub has_meta: bool,
	pub path: QString,

	pub(crate) items: Vec<FileItem>,
	pub(crate) config_owner: Option<cxx::UniquePtr<Config>>,
	pub(crate) path_str: String,
}

impl Default for DirectoryRust {
	fn default() -> Self {
		Self {
			config: std::ptr::null_mut(),
			title: QString::default(),
			icon: QString::from("folder"),
			has_meta: false,
			path: QString::default(),
			items: Vec::new(),
			config_owner: None,
			path_str: String::new(),
		}
	}
}

impl cxx_qt::Initialize for DirectoryRust {
	fn initialize(mut self: Pin<&mut Self>) {
		// Pure Rust initialization — no C++ function needed!
		let mut config = cxx_qt::make_unique<crate::bridge::ffi::Config>();
		let config_ptr = if let Some(c) = config.as_mut() {
			unsafe { Pin::into_inner_unchecked(c) as *mut Config }
		} else {
			std::ptr::null_mut()
		};
		self.as_mut().rust_mut().config_owner = Some(config);
		self.as_mut().set_config(config_ptr);

		DirectoryRust::on_path_changed(
			self.as_mut(),
			|mut this| {
				let p = this.as_ref().path().to_string();
				this.as_mut().on_path_updated(p);
			},
		);
	}
}

impl DirectoryRust {
	pub fn on_path_updated(mut self: Pin<&mut Directory>, path: String) {
		if path.is_empty() || path == "." || path == "./" || path == "/./" {
			return;
		}

		let path_buf = Path::new(&path);
		let abs_path = std::fs::canonicalize(path_buf).unwrap_or_else(|_| path_buf.to_path_buf());
		let abs_str = abs_path.to_string_lossy().to_string();

		if self.rust().path_str == abs_str && !self.rust().items.is_empty() {
			return;
		}

		self.as_mut().rust_mut().path_str = abs_str.clone();

		let load_path = if abs_path.is_file() {
			abs_path
				.parent()
				.map(|p| p.to_path_buf())
				.unwrap_or_else(|| abs_path.clone())
		} else {
			abs_path.clone()
		};

		let include_hidden = if let Some(owner) = self.rust().config_owner.as_ref() {
			if let Some(cfg) = owner.as_ref() {
				!cfg.rust().stash_dotfiles
			} else {
				false
			}
		} else {
			false
		};

		self.as_mut().load_directory_internal(&load_path, include_hidden);

		if let Some(owner) = self.as_mut().rust_mut().config_owner.as_mut() {
			if let Some(cfg) = owner.as_mut() {
				cfg._load(&load_path);
			}
		}

		let title_str = get_item_title(&abs_path);
		let icon_str = get_icon(&abs_path);
		let has_meta = abs_path.join(".meta").is_file();

		self.as_mut().set_title(QString::from(&title_str));
		self.as_mut().set_icon(QString::from(&icon_str));
		self.as_mut().set_has_meta(has_meta);
		self.as_mut().config_changed();
	}

	pub fn load_directory_internal(mut self: Pin<&mut Directory>, path: &Path, include_hidden: bool) {
		unsafe {
			self.as_mut().begin_reset_model();
		}
		self.as_mut().rust_mut().items.clear();

		let grid_size = if let Some(owner) = self.rust().config_owner.as_ref() {
			if let Some(cfg) = owner.as_ref() {
				cfg.rust().grid_size as u32
			} else {
				64
			}
		} else {
			64
		};

		let mut new_items = Vec::new();
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
				let mut icon = get_icon(&entry_path);

				if let Some(ext) = entry_path.extension().and_then(|e| e.to_str()) {
					if ext.eq_ignore_ascii_case("desktop") {
						if let Some(desktop_icon) = crate::desktop_entry::get_icon(&entry_path) {
							if desktop_icon.contains('/') {
								let candidate = if desktop_icon.starts_with('/') {
									std::path::PathBuf::from(&desktop_icon)
								} else {
									entry_path
										.parent()
										.unwrap_or(Path::new("/"))
										.join(&desktop_icon)
								};
								if candidate.exists() {
									icon = format!("file://{}", candidate.to_string_lossy());
								} else {
									icon = desktop_icon;
								}
							} else {
								icon = desktop_icon;
							}
						}
					}
				}

				if !is_dir {
					if let Some(ext) = entry_path.extension().and_then(|e| e.to_str()) {
						let ext_l = ext.to_lowercase();
						let image_exts = [
							"png", "jpg", "jpeg", "bmp", "gif", "webp", "avif", "tiff", "svg",
							"kra", "appimage",
						];
						let video_exts = ["mp4", "mkv", "webm", "avi", "mov", "mpeg", "mpg"];
						let fname = entry_path
							.file_name()
							.and_then(|n| n.to_str())
							.unwrap_or("")
							.to_lowercase();
						let is_appimage_name = fname.ends_with(".appimage");
						if image_exts.contains(&ext_l.as_str())
							|| video_exts.contains(&ext_l.as_str())
							|| is_appimage_name
						{
							if let Some(uri) =
								thumbnailer::thumbnail_uri_if_exists(&entry_path, grid_size)
							{
								icon = uri;
							} else {
								const MAX_BYTES: u64 = 10 * 1024 * 1024;
								match fs::metadata(&entry_path) {
									Ok(meta) => {
										if meta.len() <= MAX_BYTES {
											thumbnailer::enqueue(&entry_path, grid_size);
										}
									}
									Err(_) => {
										thumbnailer::enqueue(&entry_path, grid_size);
									}
								}
							}
						}
					}
				}

				new_items.push(FileItem {
					name,
					title,
					path: p,
					is_dir,
					icon,
				});
			}
		}

		new_items.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name)));
		self.as_mut().rust_mut().items = new_items;

		unsafe {
			self.as_mut().end_reset_model();
		}
	}

	pub fn role_names(&self) -> QHash_i32_QByteArray {
		let mut map = QHash::<QHashPair_i32_QByteArray>::default();
		map.insert(0x0100, QByteArray::from("name"));
		map.insert(0x0101, QByteArray::from("path"));
		map.insert(0x0102, QByteArray::from("is_dir"));
		map.insert(0x0103, QByteArray::from("icon"));
		map.insert(0x0104, QByteArray::from("title"));
		map
	}

	pub fn row_count(&self, _parent: &QModelIndex) -> i32 {
		self.rust().items.len() as i32
	}

	pub fn data(&self, index: &QModelIndex, role: i32) -> QVariant {
		let idx = index.row() as usize;
		if let Some(item) = self.rust().items.get(idx) {
			match role {
				0x0100 => QVariant::from(&QString::from(&item.name)),
				0x0101 => QVariant::from(&QString::from(&item.path)),
				0x0102 => QVariant::from(item.is_dir),
				0x0103 => QVariant::from(&QString::from(&item.icon)),
				0x0104 => QVariant::from(&QString::from(&item.title)),
				_ => QVariant::default(),
			}
		} else {
			QVariant::default()
		}
	}

	pub fn execute_file(&self, path: &QString) {
		let path_str = path.to_string();
		let path_buf = Path::new(&path_str);
		let mut cmd = Command::new(&path_str);
		if let Some(parent) = path_buf.parent() {
			cmd.current_dir(parent);
		}
		let _ = cmd.spawn();
	}

	pub fn open_path(mut self: Pin<&mut Directory>, path: &QString) {
		let path_str = path.to_string();
		let path_buf = Path::new(&path_str);
		if path_buf.is_file() {
			if is_executable(path_buf) {
				self.as_mut().request_execute_prompt(path);
			} else {
				open_file(path_buf);
			}
		} else {
			self.as_mut().set_path(path.clone());
		}
	}

	pub fn open_in_new_window(&self, path: &QString) {
		let path_str = path.to_string();
		if let Ok(exe) = std::env::current_exe() {
			let _ = Command::new(exe).arg(&path_str).spawn();
		}
	}

	pub fn poll_thumbnails(mut self: Pin<&mut Directory>) {
		let updates = crate::thumbnailer::drain_results();
		if updates.is_empty() {
			return;
		}
		for (src, dst) in updates {
			if let Some(idx) = self.rust().items.iter().position(|it| it.path == src) {
				self.as_mut().rust_mut().items[idx].icon = format!("file://{}", dst);
			}
		}

		unsafe {
			self.as_mut().begin_reset_model();
			self.as_mut().end_reset_model();
		}
	}

	pub fn set_config_value(
		mut self: Pin<&mut Directory>,
		section: &QString,
		key: &QString,
		value: &QString,
		local: bool,
	) {
		let path_str = self.rust().path_str.clone();
		let sec = section.to_string();
		let k = key.to_string();
		let val = value.to_string();
		if let Some(owner) = self.as_mut().rust_mut().config_owner.as_mut() {
			if let Some(cfg) = owner.as_mut() {
				cfg._set(
					Path::new(&path_str),
					&sec,
					&k,
					&val,
					local,
				);
			}
		}
		self.as_mut().config_changed();
	}

	pub fn reload(mut self: Pin<&mut Directory>) {
		let path_str = self.rust().path_str.clone();
		let path_buf = PathBuf::from(&path_str);
		let include_hidden = if let Some(owner) = self.rust().config_owner.as_ref() {
			if let Some(cfg) = owner.as_ref() {
				!cfg.rust().stash_dotfiles
			} else {
				false
			}
		} else {
			false
		};
		self.as_mut().load_directory_internal(&path_buf, include_hidden);
		self.as_mut().path_changed();
	}

	pub fn get_all_paths(&self) -> QStringList {
		let mut list = QStringList::default();
		for item in &self.rust().items {
			list.append(QString::from(&item.path));
		}
		list
	}

	pub fn load_directory(mut self: Pin<&mut Directory>, path: &QString, include_hidden: bool) {
		let path_str = path.to_string();
		let path_buf = Path::new(&path_str);
		self.as_mut().load_directory_internal(path_buf, include_hidden);
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

pub fn get_icon(path: &Path) -> String {
	if path.is_dir() {
		return get_folder_icon(path);
	} else {
		let mime = from_path(path)
			.first_or_octet_stream()
			.essence_str()
			.to_string();
		let key = mime;
		let cache = ICON_CACHE.lock().unwrap();
		if let Some(icon) = cache.get(&key) {
			return icon.clone();
		}
		if let Some(gio_icon) = query_gio_icon(path) {
			return gio_icon;
		}
		"unknown".to_string()
	}
}

fn get_folder_icon(path: &Path) -> String {
	if let Some(icon) = config::get_image(path, "DISPLAY", "Icon") {
		if !icon.is_empty() {
			return icon;
		}
	}
	"folder".to_string()
}

fn is_executable(path: &Path) -> bool {
	use std::os::unix::fs::PermissionsExt;
	if let Ok(metadata) = fs::metadata(path) {
		metadata.permissions().mode() & 0o111 != 0
	} else {
		false
	}
}

fn open_file(path: &Path) {
	let _ = Command::new("xdg-open").arg(path).spawn();
}