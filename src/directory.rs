#![allow(dead_code)]
use mime_guess::from_path;
use once_cell::sync::Lazy;
use qmetaobject::prelude::*;
use qmetaobject::{QObjectBox, QVariantList};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

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
						if let Some(end_rel) = line[start + 1..].find('\'') {
							let icon = &line[start + 1..start + 1 + end_rel];
							if !icon.is_empty() {
								return Some(icon.to_string());
							}
						}
					}

					// If no quoted token, split the remainder into candidate tokens
					if let Some(pos) = line.find(':') {
						let rem = line[pos + 1..].trim();
						// split on common separators and examine candidates
						for raw in rem.split(|c: char| {
							c == '[' || c == ']' || c == ',' || c == ' ' || c == '\'' || c == '"'
						}) {
							let tok = raw.trim();
							if tok.is_empty() {
								continue;
							}
							// prefer tokens that look like icon names (contain '-') or short words
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

fn normalize_path(path: &Path, current_dir: &str) -> PathBuf {
	let mut result = PathBuf::new();

	if path.is_absolute() {
		// RootDir component will set it
	} else if !current_dir.is_empty() {
		result.push(current_dir);
	} else {
		if let Ok(cwd) = std::env::current_dir() {
			result.push(cwd);
		} else {
			result.push("/");
		}
	}

	for component in path.components() {
		match component {
			std::path::Component::Prefix(p) => {
				result.push(p.as_os_str());
			}
			std::path::Component::RootDir => {
				result.clear();
				result.push("/");
			}
			std::path::Component::CurDir => {}
			std::path::Component::ParentDir => {
				result.pop();
			}
			std::path::Component::Normal(c) => {
				result.push(c);
			}
		}
	}
	result
}

#[derive(Default, Clone)]
pub struct FileItem {
	pub name: String,
	pub title: String,
	pub path: String,
	pub is_dir: bool,
	pub icon: String,
	pub modified: u64,
	pub created: u64,
	pub accessed: u64,
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

	#[allow(non_snake_case)]
	requestExecutePrompt: qt_signal!(path: String),

	execute_file: qt_method!(
		pub fn execute_file(&self, path: String) {
			let path_buf = Path::new(&path);
			let mut cmd = Command::new(&path);
			if let Some(parent) = path_buf.parent() {
				cmd.current_dir(parent);
			}
			let _ = cmd.spawn();
		}
	),

	open_path: qt_method!(
		pub fn open_path(&mut self, path: String) {
			let path_buf = Path::new(&path);
			if path_buf.is_file() {
				if is_executable(&path) {
					self.requestExecutePrompt(path);
				} else {
					open_file(path);
				}
			} else {
				self.set_path(path);
			}
		}
	),

	go_up: qt_method!(
		pub fn go_up(&mut self) {
			let current = Path::new(&self.path_str);
			if let Some(parent) = current.parent() {
				let parent_str = parent.to_string_lossy().to_string();
				if !parent_str.is_empty() && parent_str != self.path_str {
					self.set_path(parent_str);
				}
			}
		}
	),

	open_in_new_window: qt_method!(
		pub fn open_in_new_window(&self, path: String) {
			if let Ok(exe) = std::env::current_exe() {
				let _ = Command::new(exe).arg(&path).spawn();
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

			self.begin_reset_model();
			self.end_reset_model();
		}
	),

	set_config: qt_method!(
		pub fn set_config(&mut self, section: String, key: String, value: String, local: bool) {
			self.config.pinned().borrow_mut()._set(
				Path::new(&self.path_str),
				&section,
				&key,
				&value,
				local,
			);
			self.config_changed();
		}
	),

	set_free_position: qt_method!(
		pub fn set_free_position(&mut self, name: String, col: i32, row: i32) {
			let path = self.path_str.clone();
			self.config
				.pinned()
				.borrow_mut()
				.set_free_position(Path::new(&path), &name, col, row);
			self.config_changed();
			self.reload();
		}
	),

	reset_free_positions: qt_method!(
		pub fn reset_free_positions(&mut self) {
			let path = self.path_str.clone();
			self.config
				.pinned()
				.borrow_mut()
				.reset_free_positions(Path::new(&path));
			self.config_changed();
			self.reload();
		}
	),

	rename_free_position: qt_method!(
		pub fn rename_free_position(&mut self, old_name: String, new_name: String) {
			let path = self.path_str.clone();
			self.config.pinned().borrow_mut().rename_free_position(
				Path::new(&path),
				&old_name,
				&new_name,
			);
			self.config_changed();
			self.reload();
		}
	),

	reload: qt_method!(
		pub fn reload(&mut self) {
			let path = self.path_str.clone();
			let include_hidden = !self.config.pinned().borrow().stash_dotfiles;
			self.load_directory(path, include_hidden);
			self.path_changed();
		}
	),

	get_all_paths: qt_method!(
		pub fn get_all_paths(&self) -> QVariantList {
			let mut list = QVariantList::default();
			for item in &self.items {
				list.push(QString::from(item.path.as_str()).into());
			}
			list
		}
	),

	free_layout: qt_method!(
		pub fn free_layout(
			&self,
			positions_json: String,
			lines: i32,
			horizontal: bool,
			view_width: f64,
			view_height: f64,
			item_width: f64,
			item_height: f64,
			gap: f64,
		) -> String {
			Self::compute_free_layout(
				&self.items,
				&positions_json,
				lines,
				horizontal,
				view_width,
				view_height,
				item_width,
				item_height,
				gap,
			)
		}
	),

	load_directory: qt_method!(
		fn load_directory(&mut self, path: String, include_hidden: bool) {
			Directory::new(self, path, include_hidden);
		}
	),
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

				let (modified, created, accessed) = entry
					.metadata()
					.map(|meta| {
						(
							time_ms(meta.modified().ok()),
							time_ms(meta.created().ok()),
							time_ms(meta.accessed().ok()),
						)
					})
					.unwrap_or((0, 0, 0));

				// If this is a .desktop file, prefer the Icon= value from the desktop entry
				if let Some(ext) = Path::new(&p).extension().and_then(|e| e.to_str()) {
					if ext.eq_ignore_ascii_case("desktop") {
						if let Some(desktop_icon) = crate::desktop_entry::get_icon(Path::new(&p)) {
							// If the icon looks like a path, prefer an absolute/relative file if it exists
							if desktop_icon.contains('/') {
								let candidate = if desktop_icon.starts_with('/') {
									std::path::PathBuf::from(&desktop_icon)
								} else {
									Path::new(&p)
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
								// treat as theme icon name
								icon = desktop_icon;
							}
						}
					}
				}

				// enqueue thumbnail generation for images/videos and use cached thumbnail if available
				if !is_dir {
					let size = self.config.pinned().borrow().grid_size as u32;
					if let Some(ext) = Path::new(&p).extension().and_then(|e| e.to_str()) {
						let ext_l = ext.to_lowercase();
						let image_exts = [
							"png", "jpg", "jpeg", "bmp", "gif", "webp", "avif", "tiff", "svg",
							"kra", "appimage",
						];
						let video_exts = ["mp4", "mkv", "webm", "avi", "mov", "mpeg", "mpg"];
						// also allow filenames that end with .AppImage even if ext detection fails
						let fname = Path::new(&p)
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
								thumbnailer::thumbnail_uri_if_exists(Path::new(&p), size)
							{
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
					modified,
					created,
					accessed,
				});
			}
		}

		self.sort_items();

		self.end_reset_model();
	}

	fn sort_items(&mut self) {
		let (sort, date_mode, alpha_mode) = {
			let pinned = self.config.pinned();
			let config = pinned.borrow();
			(config.sort, config.sort_date_mode, config.sort_alpha_mode)
		};

		let date_key = |item: &FileItem| match date_mode {
			1 => item.created,
			2 => item.accessed,
			_ => item.modified,
		};
		let name_key = |item: &FileItem| match alpha_mode {
			1 => item.name.to_lowercase(),
			_ => item.title.to_lowercase(),
		};

		match sort {
			0 => self.items.sort_by(|a, b| {
				date_key(b)
					.cmp(&date_key(a))
					.then_with(|| name_key(a).cmp(&name_key(b)))
			}),
			1 => self.items.sort_by(|a, b| {
				date_key(a)
					.cmp(&date_key(b))
					.then_with(|| name_key(a).cmp(&name_key(b)))
			}),
			2 => self.items.sort_by(|a, b| name_key(a).cmp(&name_key(b))),
			_ => self
				.items
				.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then(a.name.cmp(&b.name))),
		}
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
		Path::new(&self.path_str).join(".directory").is_file()
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
		let abs_path = normalize_path(path_buf, &self.path_str);
		let abs_str = abs_path.to_string_lossy().to_string();

		self.path_str = abs_str.clone();

		let load_path = if abs_path.is_file() {
			abs_path
				.parent()
				.map(|p| p.to_string_lossy().to_string())
				.unwrap_or(abs_str.clone())
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

	/// Compute grid coordinates for every item in free placement mode.
	#[allow(clippy::too_many_arguments)]
	pub fn compute_free_layout(
		items: &[FileItem],
		positions_json: &str,
		lines: i32,
		horizontal: bool,
		view_width: f64,
		view_height: f64,
		item_width: f64,
		item_height: f64,
		gap: f64,
	) -> String {
		let count = items.len();
		if count == 0 {
			return serde_json::json!({
				"columns": 0,
				"rows": 0,
				"slots": [],
				"naturalWidth": view_width.max(0.0),
				"naturalHeight": view_height.max(0.0),
			})
			.to_string();
		}

		let mut positions: HashMap<String, (i32, i32)> = HashMap::new();
		if let Ok(value) = serde_json::from_str::<serde_json::Value>(positions_json)
			&& let Some(obj) = value.as_object()
		{
			for (name, pos) in obj {
				if let Some(arr) = pos.as_array() {
					let col = arr.get(0).and_then(|v| v.as_i64()).unwrap_or(0) as i32;
					let row = arr.get(1).and_then(|v| v.as_i64()).unwrap_or(0) as i32;
					positions.insert(name.clone(), (col, row));
				}
			}
		}

		let item_main = if horizontal { item_height } else { item_width };
		let view_main = if horizontal { view_height } else { view_width };
		let auto_stride = (((view_main + gap) / (item_main + gap)).floor() as i32).max(1);

		let mut min_cols = 1;
		let mut min_rows = 1;
		for item in items {
			if let Some(&(col, row)) = positions.get(&item.name) {
				min_cols = min_cols.max(col + 1);
				min_rows = min_rows.max(row + 1);
			}
		}

		let cross_fill =
			|view: f64, item: f64| -> i32 { (((view + gap) / (item + gap)).floor() as i32).max(1) };

		let (columns, rows) = if horizontal {
			let rows = if lines > 0 {
				lines
			} else {
				auto_stride.max(min_rows)
			}
			.max(1);
			let mut cols = ((count as f64 / rows as f64).ceil() as i32).max(min_cols);
			cols = cols.max(cross_fill(view_width, item_width));
			(cols.max(1), rows)
		} else {
			let cols = if lines > 0 {
				lines
			} else {
				auto_stride.max(min_cols)
			}
			.max(1);
			let mut rows = ((count as f64 / cols as f64).ceil() as i32).max(min_rows);
			rows = rows.max(cross_fill(view_height, item_height));
			(cols, rows.max(1))
		};

		let columns = columns.max(1);
		let rows = rows.max(1);

		let mut occupied = vec![vec![false; columns as usize]; rows as usize];
		let mut slots = vec![(0i32, 0i32); count];

		for (i, item) in items.iter().enumerate() {
			let Some(&(mut col, mut row)) = positions.get(&item.name) else {
				continue;
			};
			col = col.clamp(0, columns - 1);
			row = row.clamp(0, rows - 1);
			if occupied[row as usize][col as usize] {
				let (c, r) = nearest_available(&occupied, columns, rows, col, row);
				col = c;
				row = r;
			}
			occupied[row as usize][col as usize] = true;
			slots[i] = (col, row);
		}

		for (i, item) in items.iter().enumerate() {
			if positions.contains_key(&item.name) {
				continue;
			}
			let (col, row) = first_available(&occupied, columns, rows, horizontal);
			occupied[row as usize][col as usize] = true;
			slots[i] = (col, row);
		}

		let natural_width = columns as f64 * item_width + (columns - 1) as f64 * gap;
		let natural_height = rows as f64 * item_height + (rows - 1) as f64 * gap;

		let slots_json: Vec<serde_json::Value> = slots
			.iter()
			.map(|&(c, r)| serde_json::json!({ "c": c, "r": r }))
			.collect();

		serde_json::json!({
			"columns": columns,
			"rows": rows,
			"slots": slots_json,
			"naturalWidth": natural_width,
			"naturalHeight": natural_height,
		})
		.to_string()
	}
}

fn first_available(
	occupied: &[Vec<bool>],
	columns: i32,
	rows: i32,
	horizontal: bool,
) -> (i32, i32) {
	if horizontal {
		for col in 0..columns {
			for row in 0..rows {
				if !occupied[row as usize][col as usize] {
					return (col, row);
				}
			}
		}
	} else {
		for row in 0..rows {
			for col in 0..columns {
				if !occupied[row as usize][col as usize] {
					return (col, row);
				}
			}
		}
	}
	(0, 0)
}

fn nearest_available(
	occupied: &[Vec<bool>],
	columns: i32,
	rows: i32,
	col: i32,
	row: i32,
) -> (i32, i32) {
	let mut best = (0, 0);
	let mut best_dist = i64::MAX;
	for r in 0..rows {
		for c in 0..columns {
			if occupied[r as usize][c as usize] {
				continue;
			}
			let dr = (r - row) as i64;
			let dc = (c - col) as i64;
			let dist = dr.abs() + dc.abs();
			if dist < best_dist {
				best_dist = dist;
				best = (c, r);
			}
		}
	}
	best
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

fn time_ms(time: Option<SystemTime>) -> u64 {
	time.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
		.map(|d| d.as_millis() as u64)
		.unwrap_or(0)
}

pub fn get_item_title(path: &Path) -> String {
	if let Some(config_title) = config::get_string(path, "Desktop Entry", "Name") {
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
		let mime = from_path(path)
			.first_or_octet_stream()
			.essence_str()
			.to_string();
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

fn icon_source(icon: String, base: &Path) -> String {
	let path = if icon.starts_with('/') {
		PathBuf::from(&icon)
	} else if icon.contains('/') {
		base.join(&icon)
	} else {
		return icon;
	};

	match std::fs::canonicalize(&path) {
		Ok(resolved) => format!("file://{}", resolved.to_string_lossy()),
		Err(_) => icon,
	}
}

pub fn get_folder_icon(path: &str) -> String {
	let path_buf = Path::new(path);
	let abs_path = std::fs::canonicalize(path_buf).unwrap_or_else(|_| path_buf.to_path_buf());

	if let Some(icon) = config::get_image(&abs_path, "Desktop Entry", "Icon") {
		if !icon.is_empty() {
			return icon_source(icon, &abs_path);
		}
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
	if crate::kde_bridge::open_with_default(&path) {
		return;
	}
	let _ = Command::new("xdg-open").arg(&path).spawn();
}

pub fn is_executable(path: &str) -> bool {
	let path_buf = Path::new(path);

	if let Ok(mut file) = std::fs::File::open(&path_buf) {
		use std::io::Read;
		let mut buffer = [0; 4];
		if file.read_exact(&mut buffer).is_ok() {
			if buffer == [0x7f, b'E', b'L', b'F'] || (buffer[0] == b'#' && buffer[1] == b'!') {
				return true;
			}
		}
	}

	#[cfg(unix)]
	{
		use std::os::unix::fs::PermissionsExt;
		if let Ok(meta) = std::fs::metadata(&path_buf) {
			if meta.permissions().mode() & 0o111 != 0 {
				return true;
			}
		}
	}

	false
}
