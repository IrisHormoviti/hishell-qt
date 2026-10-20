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
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use crate::config;
use crate::config::Config;
use crate::thumbnailer;

static ICON_CACHE: Lazy<Mutex<HashMap<String, String>>> = Lazy::new(|| Mutex::new(HashMap::new()));

/// How often the change poll may re-read desktop entries. The folder mtime check
/// runs at the timer's rate; re-resolving icons is throttled to this.
const ICON_POLL_INTERVAL: Duration = Duration::from_secs(1);

fn query_gio_icon(path: &str) -> Option<String> {
	// `gio info ""` inspects the working directory and reports a folder icon.
	if path.trim().is_empty() {
		return None;
	}

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

fn launch_desktop_entry(path: &Path) -> String {
	crate::desktop_entry::launch(path)
}

pub fn is_execute_target(path: &Path) -> bool {
	if crate::config::entry_path(path).is_some() {
		crate::desktop_entry::is_action_entry(path)
	} else if path.is_file() {
		is_executable(&path.to_string_lossy())
	} else {
		false
	}
}

/// The value a parent `[Radio]` group stores for a selected child: the folder
/// name for directories, the stem for desktop entries, the file name otherwise.
pub fn radio_value(path: &Path) -> String {
	let name = path
		.file_name()
		.and_then(|n| n.to_str())
		.unwrap_or_default()
		.to_string();
	if path.is_dir() {
		return name;
	}
	if path
		.extension()
		.and_then(|e| e.to_str())
		.is_some_and(|e| e.eq_ignore_ascii_case("desktop"))
	{
		return path
			.file_stem()
			.and_then(|s| s.to_str())
			.unwrap_or(&name)
			.to_string();
	}
	name
}

/// Run a parent folder's `[Radio] Exec`, substituting `%v` (value), `%n`
/// (display name), and `%p` (full path).  The command is tokenised without a
/// shell, and placeholders are replaced inside each argument so a value with
/// spaces stays one argument.
fn run_radio_exec(exec: &str, value: &str, name: &str, path: &str) {
	let args = split_command(exec);
	let Some((command, rest)) = args.split_first() else {
		return;
	};
	let mut final_args = Vec::with_capacity(rest.len());
	for arg in rest {
		final_args.push(
			arg.replace("%v", value)
				.replace("%n", name)
				.replace("%p", path),
		);
	}
	if let Err(error) = Command::new(command).args(final_args).spawn() {
		eprintln!("failed to run radio command {command:?}: {error}");
	}
}

fn split_command(line: &str) -> Vec<String> {
	let mut args = Vec::new();
	let mut current = String::new();
	let mut quote: Option<char> = None;
	let mut escaped = false;

	for ch in line.chars() {
		if escaped {
			current.push(ch);
			escaped = false;
			continue;
		}
		match ch {
			'\\' => escaped = true,
			'\'' | '"' => {
				if quote == Some(ch) {
					quote = None;
				} else if quote.is_none() {
					quote = Some(ch);
				} else {
					current.push(ch);
				}
			}
			c if c.is_whitespace() && quote.is_none() => {
				if !current.is_empty() {
					args.push(std::mem::take(&mut current));
				}
			}
			c => current.push(c),
		}
	}

	if !current.is_empty() {
		args.push(current);
	}
	args
}

#[derive(Default, Clone)]
pub struct FileItem {
	pub name: String,
	pub title: String,
	pub path: String,
	pub is_dir: bool,
	pub is_symlink: bool,
	pub is_dotfile: bool,
	pub icon: String,
	pub modified: u64,
	pub created: u64,
	pub accessed: u64,
}

#[derive(QObject, Default)]
pub struct Directory {
	base: qt_base_class!(trait QAbstractListModel),
	items: Vec<FileItem>,
	// Indices of `items` that pass the active filter, in display order.
	visible: Vec<usize>,

	config: QObjectBox<Config>,
	config_prop: qt_property!(QVariant; READ get_config NOTIFY config_changed ALIAS config),
	config_changed: qt_signal!(),

	// Last icon source applied to the window, so the periodic refresh does not
	// rebuild an unchanged icon.
	last_window_icon: String,

	// The folder's own mtime at the last scan, and when icons were last
	// re-resolved: the state the periodic change poll compares against.
	dir_modified: u64,
	last_icon_poll: Option<Instant>,

	title: qt_property!(String; READ get_title),
	icon: qt_property!(String; READ get_icon NOTIFY path_changed),
	has_meta: qt_property!(bool; READ get_has_meta NOTIFY path_changed),

	path: qt_property!(String; READ get_path WRITE set_path NOTIFY path_changed),
	path_str: String,
	path_changed: qt_signal!(),

	filter: qt_property!(String; READ get_filter NOTIFY filter_changed),
	filter_changed: qt_signal!(),

	#[allow(non_snake_case)]
	requestExecutePrompt: qt_signal!(path: String),

	execute_file: qt_method!(
		pub fn execute_file(&self, path: String) -> String {
			let path_buf = Path::new(&path);
			let parent = path_buf.parent();
			let name = crate::launch::app_name(&path);
			crate::launch::result(crate::launch::request(&path, &[], &path, &name, parent))
		}
	),

	is_execute_target: qt_method!(
		pub fn is_execute_target(&self, path: String) -> bool {
			is_execute_target(Path::new(&path))
		}
	),

	is_link: qt_method!(
		pub fn is_link(&self, path: String) -> bool {
			crate::desktop_entry::is_link(Path::new(&path))
		}
	),

	/// True when this folder owns a `[Radio]` group and `path` is one of its
	/// selectable children.  The parent folder — not the child — decides this.
	is_radio_member: qt_method!(
		pub fn is_radio_member(&self, path: String) -> bool {
			let config = self.config.pinned();
			let config = config.borrow();
			if !config.radio_enabled {
				return false;
			}

			let path = Path::new(&path);
			// Only a direct child of this folder is a choice in its radio
			// group.  Without this, any directory (a path-bar ancestor, say)
			// passes the `Only=Directories` test and is treated as selectable.
			let base = Path::new(self.path_str.trim_end_matches('/'));
			let parent_ok = path
				.parent()
				.is_some_and(|parent| parent == base || parent.as_os_str().is_empty() && base.as_os_str().is_empty());
			if !parent_ok {
				return false;
			}

			match config.radio_only {
				1 => path.is_dir(),
				2 => path.is_file(),
				_ => true,
			}
		}
	),

	/// The stable value stored in the parent's `[Radio] Selected`.
	radio_value: qt_method!(
		pub fn radio_value(&self, path: String) -> String {
			radio_value(Path::new(&path))
		}
	),

	/// Select a child of this folder's radio group: write `[Radio] Selected`
	/// into this folder's `.directory` and run the parent's `Exec` command.
	select_radio: qt_method!(
		pub fn select_radio(&mut self, path: String) {
			if !self.is_radio_member(path.clone()) {
				return;
			}
			let value = radio_value(Path::new(&path));
			if value.is_empty() {
				return;
			}

			let parent = self.path_str.clone();
			self.config
				.pinned()
				.borrow_mut()
				._set(Path::new(&parent), "Radio", "Selected", &value, true);

			let (exec, name) = {
				let config = self.config.pinned();
				let config = config.borrow();
				(config.radio_exec.to_string(), get_item_title(Path::new(&path)))
			};
			if !exec.trim().is_empty() {
				run_radio_exec(&exec, &value, &name, &path);
			}
			self.config_changed();
		}
	),

	/// Run this folder's own `Refresh=<command line>` when it has one: how a
	/// folder asks its provider for fresh contents (docs §4.7). Fire and forget
	/// — the provider rewrites the folder and the shell's watch picks it up.
	run_refresh_command: qt_method!(
		pub fn run_refresh_command(&self) {
			if self.path_str.is_empty() {
				return;
			}
			let entry = Path::new(&self.path_str).join(".directory");
			let Some(command) = crate::config::get_entry_string(&entry, "Refresh") else {
				return;
			};
			let command = command.trim().to_string();
			if command.is_empty() {
				return;
			}
			crate::desktop_entry::run_refresh(Path::new(&self.path_str), &command);
		}
	),

	execute_action: qt_method!(
		pub fn execute_action(&mut self, path: String) -> String {
			if self.is_radio_member(path.clone()) {
				self.select_radio(path);
				return String::new();
			}
			let path_buf = Path::new(&path);
			if crate::desktop_entry::is_action_entry(path_buf) {
				launch_desktop_entry(path_buf)
			} else if is_executable(&path) {
				self.requestExecutePrompt(path);
				String::new()
			} else {
				String::new()
			}
		}
	),

	open_path: qt_method!(
		pub fn open_path(&mut self, path: String) -> String {
			let path_buf = Path::new(&path);
			if path_buf.is_file() {
				open_file(path)
			} else {
				self.set_path(path);
				String::new()
			}
		}
	),

	/// Finish a launch the execution wrapper held back for confirmation.
	confirm_launch: qt_method!(
		pub fn confirm_launch(&self) -> bool {
			crate::launch::confirm()
		}
	),

	/// Drop a launch the execution wrapper held back for confirmation.
	cancel_launch: qt_method!(
		pub fn cancel_launch(&self) {
			crate::launch::cancel();
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
			if !thumbnailer::has_results() {
				return;
			}
			let mut updates = Vec::new();
			for (row, index) in self.visible.iter().enumerate() {
				let item = &self.items[*index];
				if let Some(uri) = thumbnailer::result_for(&item.path) {
					if item.icon != uri {
						updates.push((row, uri));
					}
				}
			}
			for (row, uri) in updates {
				let index = self.visible[row];
				self.items[index].icon = uri;
				let model_index = self.row_index(row as i32);
				self.data_changed(model_index, model_index);
			}
		}
	),

	/// Periodic poll for folders that an out-of-process provider rewrites, so a
	/// changed `Icon=` or a newly appeared entry shows up without leaving and
	/// returning. Driven by the same timer as `poll_thumbnails`.
	poll_changes: qt_method!(
		pub fn poll_changes(&mut self) {
			if self.path_str.is_empty() {
				return;
			}
			// The folder's own mtime moves when an entry is added, removed or
			// atomically replaced (a provider writes a temp file and renames it
			// over the old one), so this cheap stat gates the expensive rebuild.
			let modified = folder_modified(&self.path_str);
			if modified != 0 && modified != self.dir_modified {
				self.reload();
				return;
			}
			// The listing is unchanged, so only file contents can differ. Re-read
			// desktop entries (a tiny file each; they return before ICON_CACHE)
			// and repaint just the rows whose icon moved. Non-entries are
			// skipped, so a rendered thumbnail is never clobbered.
			if self
				.last_icon_poll
				.is_some_and(|last| last.elapsed() < ICON_POLL_INTERVAL)
			{
				return;
			}
			self.last_icon_poll = Some(Instant::now());

			let mut updates = Vec::new();
			for (row, index) in self.visible.iter().enumerate() {
				let item = &self.items[*index];
				if crate::config::entry_path(Path::new(&item.path)).is_none() {
					continue;
				}
				let icon = get_icon(&item.path);
				if icon != item.icon {
					updates.push((row, icon));
				}
			}
			for (row, icon) in updates {
				let index = self.visible[row];
				self.items[index].icon = icon;
				let model_index = self.row_index(row as i32);
				self.data_changed(model_index, model_index);
			}
		}
	),

	request_thumbnail: qt_method!(
		pub fn request_thumbnail(&mut self, path: String, size: i32) {
			let size = size.max(1) as u32;
			let folder = self.path_str.clone();
			if let Some(uri) = thumbnailer::request(Path::new(&path), size, Path::new(&folder)) {
				if let Some(idx) = self.items.iter().position(|it| it.path == path) {
					if self.items[idx].icon != uri {
						self.items[idx].icon = uri;
						if let Some(row) = self.visible.iter().position(|visible| *visible == idx) {
							let model_index = self.row_index(row as i32);
							self.data_changed(model_index, model_index);
						}
					}
				}
			}
		}
	),

	/// Points the top-level window icon at this folder's icon. A custom icon set
	/// through the folder config (or its `.directory`) wins over the default
	/// themed folder icon. Returns false when nothing could be applied.
	apply_window_icon: qt_method!(
		pub fn apply_window_icon(&mut self) -> bool {
			let source = self.icon_source();
			if source.is_empty() || source == self.last_window_icon {
				return false;
			}
			if crate::kde_bridge::set_window_icon(&source) {
				self.last_window_icon = source;
				return true;
			}
			false
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
			// Refreshing the changed config property is enough for layout-only
			// settings (grid size, spacing, alignment, ...). Sorting reorders the
			// existing items in place; keys that change which files exist emit
			// `items_changed`, which the view turns into a re-scan.
			if crate::config::key_affects_order(&section, &key) {
				self.resort_items();
			}
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
		}
	),

	reset_free_positions: qt_method!(
		pub fn reset_free_positions(&mut self) {
			let path = self.path_str.clone();
			self.config
				.pinned()
				.borrow_mut()
				.reset_free_positions(Path::new(&path));
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
			// The file itself was renamed, so the item set changed.
			self.reload();
		}
	),

	reload: qt_method!(
		pub fn reload(&mut self) {
			let path = self.path_str.clone();
			// Re-read the config first so a manual refresh also picks up edits
			// made to the folder's config file on disk.
			self.config.pinned().borrow_mut()._load(Path::new(&path));
			let include_hidden = !self.config.pinned().borrow().stash_dotfiles;
			self.load_directory(path, include_hidden);
			self.path_changed();
		}
	),

	append_filter: qt_method!(
		fn append_filter(&mut self, text: String) {
			let mut filter = self.filter.clone();
			filter.push_str(&text);
			self.set_filter_text(filter);
		}
	),

	backspace_filter: qt_method!(
		fn backspace_filter(&mut self) {
			let mut filter = self.filter.clone();
			if filter.pop().is_some() {
				self.set_filter_text(filter);
			}
		}
	),

	clear_filter: qt_method!(
		fn clear_filter(&mut self) {
			self.set_filter_text(String::new());
		}
	),

	get_all_paths: qt_method!(
		pub fn get_all_paths(&self) -> QVariantList {
			let mut list = QVariantList::default();
			for index in &self.visible {
				if let Some(item) = self.items.get(*index) {
					list.push(QString::from(item.path.as_str()).into());
				}
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
			let items: Vec<&FileItem> = self
				.visible
				.iter()
				.filter_map(|index| self.items.get(*index))
				.collect();
			Self::compute_free_layout(
				&items,
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
			// Re-reading a folder drops its pending thumbnail work; results that
			// are still in flight simply no longer match any item.
			if !self.path_str.is_empty() {
				crate::thumbnailer::cancel_folder(Path::new(&self.path_str));
			}
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
				let file_type = entry.file_type().ok();
				let is_dir = file_type.map(|t| t.is_dir()).unwrap_or(false);
				let is_symlink = file_type.map(|t| t.is_symlink()).unwrap_or(false);
				let icon = get_icon(&p);

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

				self.items.push(FileItem {
					name,
					title,
					path: p,
					is_dir,
					is_symlink,
					is_dotfile: entry_path
						.file_name()
						.and_then(|n| n.to_str())
						.is_some_and(|n| n.starts_with('.')),
					icon,
					modified,
					created,
					accessed,
				});
			}
		}

		self.sort_items();
		self.apply_filter();

		self.end_reset_model();

		// Remember the folder's mtime so `poll_changes` can tell an unchanged
		// listing from one that needs rebuilding.
		self.dir_modified = folder_modified(&self.path_str);
	}

	/// Re-sort the in-memory items after a sort-related config change, without
	/// touching the filesystem.
	fn resort_items(&mut self) {
		self.begin_reset_model();
		self.sort_items();
		self.apply_filter();
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

		let dotfile_key = |item: &FileItem| item.is_dotfile;

		match sort {
			0 => self.items.sort_by(|a, b| {
				dotfile_key(a)
					.cmp(&dotfile_key(b))
					.then_with(|| date_key(b).cmp(&date_key(a)))
					.then_with(|| name_key(a).cmp(&name_key(b)))
			}),
			1 => self.items.sort_by(|a, b| {
				dotfile_key(a)
					.cmp(&dotfile_key(b))
					.then_with(|| date_key(a).cmp(&date_key(b)))
					.then_with(|| name_key(a).cmp(&name_key(b)))
			}),
			2 => self.items.sort_by(|a, b| {
				dotfile_key(a)
					.cmp(&dotfile_key(b))
					.then_with(|| name_key(a).cmp(&name_key(b)))
			}),
			_ => self.items.sort_by(|a, b| {
				dotfile_key(a)
					.cmp(&dotfile_key(b))
					.then_with(|| b.is_dir.cmp(&a.is_dir))
					.then_with(|| a.name.cmp(&b.name))
			}),
		}
	}

	pub fn get_path(&self) -> String {
		self.path_str.clone()
	}

	pub fn get_filter(&self) -> String {
		self.filter.clone()
	}

	/// Replace the filter and rebuild the visible rows.
	fn set_filter_text(&mut self, filter: String) {
		if self.filter == filter {
			return;
		}
		self.filter = filter;
		self.begin_reset_model();
		self.apply_filter();
		self.end_reset_model();
		self.filter_changed();
	}

	/// Rebuild the row index from the current filter; the caller owns the model
	/// reset so sorting and reloads can reuse it.
	fn apply_filter(&mut self) {
		let query = self.filter.to_lowercase();
		self.visible.clear();
		for (index, item) in self.items.iter().enumerate() {
			if query.is_empty()
				|| item.name.to_lowercase().contains(&query)
				|| item.title.to_lowercase().contains(&query)
			{
				self.visible.push(index);
			}
		}
	}

	fn visible_item(&self, row: usize) -> Option<&FileItem> {
		self.visible
			.get(row)
			.and_then(|index| self.items.get(*index))
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

	/// The icon source to use for this folder's window, preferring a custom icon
	/// (from the folder's config / `.directory`) over the resolved default.
	fn icon_source(&self) -> String {
		if self.path_str.is_empty() {
			return String::new();
		}

		let custom = self.config.pinned().borrow().icon.to_string();
		if !custom.is_empty() {
			// `Config.icon` already carries a `file://` prefix for path icons.
			return custom;
		}

		let icon = get_icon(&self.path_str);
		if icon.starts_with('/') {
			format!("file://{}", icon)
		} else {
			icon
		}
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

		if !self.path_str.is_empty() && self.path_str != abs_str {
			crate::thumbnailer::cancel_folder(Path::new(&self.path_str));
		}

		// Navigating to a different folder drops the type-to-filter text.
		if self.path_str != abs_str && !self.filter.is_empty() {
			self.filter = String::new();
			self.filter_changed();
		}

		self.path_str = abs_str.clone();
		crate::session::save_path(&abs_str);

		let load_path = if abs_path.is_file() {
			abs_path
				.parent()
				.map(|p| p.to_string_lossy().to_string())
				.unwrap_or(abs_str.clone())
		} else {
			abs_str.clone()
		};

		// The config decides whether dotfiles are listed, so it has to be read
		// before the directory; otherwise the folder gets scanned twice.
		self.config.pinned().borrow_mut().load(load_path.clone());
		let include_hidden = !self.config.pinned().borrow().stash_dotfiles;
		self.load_directory(load_path, include_hidden);

		self.path_changed();
		self.config_changed();
	}

	pub fn get_title(&self) -> String {
		get_item_title(Path::new(&self.path_str))
	}

	/// Compute grid coordinates for every item in free placement mode.
	#[allow(clippy::too_many_arguments)]
	pub fn compute_free_layout(
		items: &[&FileItem],
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
		self.visible.len() as i32
	}

	fn data(&self, index: QModelIndex, role: i32) -> QVariant {
		let Some(item) = self.visible_item(index.row() as usize) else {
			return QVariant::default();
		};
		match role {
			0x0100 => QString::from(item.name.as_str()).into(),
			0x0101 => QString::from(item.path.as_str()).into(),
			0x0102 => item.is_dir.into(),
			0x0103 => QString::from(item.icon.as_str()).into(),
			0x0104 => QString::from(item.title.as_str()).into(),
			0x0105 => item.is_symlink.into(),
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
		map.insert(0x0105, "is_symlink".into());
		map
	}
}

fn time_ms(time: Option<SystemTime>) -> u64 {
	time.and_then(|t| t.duration_since(UNIX_EPOCH).ok())
		.map(|d| d.as_millis() as u64)
		.unwrap_or(0)
}

/// A folder's own modification time, in milliseconds (0 when it cannot be read).
/// Adding, removing or atomically replacing an entry bumps it.
fn folder_modified(path: &str) -> u64 {
	fs::metadata(path)
		.map(|meta| time_ms(meta.modified().ok()))
		.unwrap_or(0)
}

pub fn get_item_title(path: &Path) -> String {
	if crate::config::entry_path(path).is_some() {
		let entry = crate::desktop_entry::read(path);
		if let Some(name) = entry.name.filter(|name| !name.is_empty()) {
			return name;
		}
	}

	if let Some(descriptor) = crate::directory_descriptor::lookup(path) {
		if let Some(name) = descriptor.name.filter(|name| !name.is_empty()) {
			return name;
		}
	}

	if let Some(entry) = crate::appimage::desktop_entry(path) {
		if let Some(name) = entry.name.filter(|name| !name.is_empty()) {
			return name;
		}
	}

	path.file_name()
		.map(|name| name.to_string_lossy().to_string())
		.unwrap_or_else(|| path.to_string_lossy().to_string())
}

pub fn get_icon(path: &str) -> String {
	// An empty path would make `gio info` inspect the current working directory,
	// so bail out before any filesystem or gio lookup can happen.
	if path.trim().is_empty() {
		return "text-x-generic".to_string();
	}

	let path_buf = Path::new(path);
	let is_dir = path_buf.is_dir();

	if let Some(icon) = config::get_entry_image(path_buf, "Icon") {
		if !icon.is_empty() {
			return icon_source(icon, config::base_dir(path_buf));
		}
	}

	// AppImages carry their own desktop entry and icon.
	if let Some(icon) = crate::appimage::icon(path_buf) {
		return format!("file://{}", icon.display());
	}

	if is_dir {
		return get_folder_icon(path);
	}

	if crate::desktop_entry::is_link(path_buf) {
		return "open-link".to_string();
	}

	// Prefer system icons via `gio` when available, caching per-extension. Files
	// without an extension (README, Makefile, .bashrc, ...) are cached per-name:
	// mime_guess reports them all as application/octet-stream, so a mime-keyed
	// cache would let the first one resolved decide the icon for all the others.
	let mime = from_path(path)
		.first_or_octet_stream()
		.essence_str()
		.to_string();
	let key = if let Some(ext) = Path::new(path).extension().and_then(|e| e.to_str()) {
		format!("ext:{}", ext.to_lowercase())
	} else {
		let name = path_buf
			.file_name()
			.and_then(|n| n.to_str())
			.unwrap_or(path)
			.to_lowercase();
		format!("name:{}", name)
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
	} else {
		"text-x-generic".to_string()
	};

	ICON_CACHE.lock().unwrap().insert(key, icon.clone());
	icon
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

	// A directory descriptor supplies the name and icon from outside the
	// directory, so a mounted card that cannot carry its own `.directory`
	// still shows a device icon (see `directory_descriptor`).
	if let Some(descriptor) = crate::directory_descriptor::lookup(&abs_path) {
		if let Some(icon) = descriptor.icon {
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

pub fn open_file(path: String) -> String {
	// Prefer resolving the default application and spawning it here, so the
	// launch goes through the configured execution wrapper.
	if let Some((exec, entry)) = crate::kde_bridge::default_app_command(&path) {
		return crate::desktop_entry::launch_command(&exec, &entry, Some(&path));
	}
	if crate::kde_bridge::open_with_default(&path) {
		return String::new();
	}
	let _ = crate::launch::spawn("xdg-open", std::slice::from_ref(&path), &path, "xdg-open", None);
	String::new()
}

pub fn is_executable(path: &str) -> bool {
	// Executability is a property of the file's content, not its mode bits.
	// The ROM and SD cards are mounted vfat with `fmask=0000`, so every file
	// there reports 0755 and a permission test would call a .nds ROM (or any
	// other file) executable. A runnable program on Linux is an ELF image or a
	// script starting with "#!"; anything else is handed to its MIME handler.
	use std::io::Read;
	let Ok(mut file) = std::fs::File::open(path) else {
		return false;
	};
	let mut buffer = [0; 4];
	if file.read_exact(&mut buffer).is_err() {
		return false;
	}
	buffer == [0x7f, b'E', b'L', b'F'] || &buffer[..2] == b"#!"
}
