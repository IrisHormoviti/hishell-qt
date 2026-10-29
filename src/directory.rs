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
use std::sync::mpsc;
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
	// The selected entry's path still has to travel with the command.  It is
	// how a provider action finds the live file, including through a user-moved
	// symlink; without it `clam-connect` has only the bare MAC/UUID and would
	// fall back to guessing a folder (docs `clam-configd.md` §5.3).
	let item = Path::new(path);
	let cwd = crate::config::base_dir(item);
	if let Err(error) = crate::launch::spawn_direct(command, &final_args, path, name, Some(cwd)) {
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
	/// `Comment=` from the item's desktop entry or descriptor: secondary data
	/// for the settings list view (`Connected`, a kernel version, …).
	pub comment: String,
	pub path: String,
	pub is_dir: bool,
	pub is_symlink: bool,
	pub is_dotfile: bool,
	pub icon: String,
	/// Whether this item carries a desktop entry / `.directory` config. The
	/// change poll uses it to skip plain files without a stat per item.
	pub is_entry: bool,
	/// 0 = ordinary item, 1 = Type=Button, 2 = Type=Toggle, 3 = Type=Number.
	/// Resolved during the scan so a delegate does not re-read the entry for
	/// each of the four control questions.
	pub control_kind: u8,
	pub toggle_on: bool,
	/// Type=Number's field values, joined for display.
	pub number_value: String,
	pub size: u64,
	pub modified: u64,
	pub created: u64,
	pub accessed: u64,
	/// The group this item belongs to, in display order. Empty when the folder
	/// is not grouped.
	pub group: u16,
	pub group_label: String,
	/// A dotfile or `NoDisplay` entry: what the Stash group collects.
	pub is_stashed: bool,
	/// `Group=` from the item's own desktop entry, for custom grouping.
	pub custom_group: String,
}

#[derive(QObject, Default)]
pub struct Directory {
	base: qt_base_class!(trait QAbstractListModel),
	items: Vec<FileItem>,
	// Indices of `items` that pass the active filter, in display order.
	visible: Vec<usize>,
	// Label of each group, indexed by `FileItem::group`. An empty label is the
	// custom untitled group and draws no header.
	group_labels: Vec<String>,

	config: QObjectBox<Config>,
	config_prop: qt_property!(QVariant; READ get_config NOTIFY config_changed ALIAS config),
	config_changed: qt_signal!(),

	// Last icon source applied to the window, so the periodic refresh does not
	// rebuild an unchanged icon.
	last_window_icon: String,

	// How many of `visible` the model exposes to the view yet. A new folder
	// opens with a couple of rows and grows over the next frames: the view
	// builds a delegate per exposed item, and building a whole screen at once
	// is the one long stall left in opening a folder.
	exposed: usize,
	exposing: qt_property!(bool; NOTIFY exposure_changed),
	exposure_changed: qt_signal!(),

	// The scan runs on a worker: reading a cold vfat directory and its metadata
	// can take most of a second, and waiting for it on the GUI thread froze the
	// folder open. `poll_scan` applies the result when it arrives.
	scanning: qt_property!(bool; NOTIFY scanning_changed),
	scanning_changed: qt_signal!(),
	scan_rx: Option<mpsc::Receiver<(u64, String, Vec<FileItem>)>>,
	scan_generation: u64,

	// The folder's own mtime at the last scan, and when icons were last
	// re-resolved: the state the periodic change poll compares against.
	dir_modified: u64,
	last_icon_poll: Option<Instant>,
	last_descriptor_epoch: u64,

	title: qt_property!(String; READ get_title),
	icon: qt_property!(String; READ get_icon NOTIFY path_changed),
	has_meta: qt_property!(bool; READ get_has_meta NOTIFY path_changed),

	path: qt_property!(String; READ get_path WRITE set_path NOTIFY path_changed),
	path_str: String,
	path_changed: qt_signal!(),

	filter: qt_property!(String; READ get_filter NOTIFY filter_changed),
	filter_changed: qt_signal!(),

	/// Apply a finished worker scan, if there is one. The view polls this while
	/// `scanning` is true.
	poll_scan: qt_method!(
		fn poll_scan(&mut self) {
			let Some(rx) = self.scan_rx.as_ref() else {
				return;
			};
			let received = rx.try_recv();
			match received {
				Ok((generation, path, items)) => {
					self.scan_rx = None;
					if generation != self.scan_generation || path != self.path_str {
						return;
					}
					self.apply_scan(items);
				}
				Err(mpsc::TryRecvError::Empty) => {}
				Err(mpsc::TryRecvError::Disconnected) => {
					self.scan_rx = None;
					if self.scanning {
						self.scanning = false;
						self.scanning_changed();
					}
				}
			}
		}
	),

	/// Expose the next couple of rows of a just-opened folder. The view's timer
	/// calls this while `exposing` is true.
	expose_rows: qt_method!(
		fn expose_rows(&mut self) {
			self.expose_more();
		}
	),

	/// Expose every row up to `row`, so a restored cursor in a large folder is
	/// reachable immediately instead of waiting for the gradual fill.
	expose_to: qt_method!(
		fn expose_to(&mut self, row: i32) {
			let target = (row.max(0) as usize + 1).min(self.visible.len());
			if target <= self.exposed {
				return;
			}
			self.begin_insert_rows(self.exposed as i32, (target - 1) as i32);
			self.exposed = target;
			self.end_insert_rows();
			if self.exposed >= self.visible.len() {
				self.exposing = false;
				self.exposure_changed();
			}
		}
	),

	#[allow(non_snake_case)]
	requestExecutePrompt: qt_signal!(path: String),

	execute_file: qt_method!(
		pub fn execute_file(&self, path: String) -> String {
			let path_buf = Path::new(&path);
			let parent = path_buf.parent();
			let name = crate::launch::app_name(&path);
			crate::launch::result(crate::launch::request(&path, &[], &path, &name, "", parent))
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
			let parent_ok = path.parent().is_some_and(|parent| {
				parent == base || parent.as_os_str().is_empty() && base.as_os_str().is_empty()
			});
			if !parent_ok {
				return false;
			}

			// Metadata is not a choice.  `Only=Files` otherwise makes the
			// folder's own `.directory` a radio child, so selecting it would
			// write `Selected=.directory` and run `Exec` with that stem.
			if path
				.file_name()
				.and_then(|name| name.to_str())
				.is_some_and(|name| name.starts_with('.'))
			{
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
			self.config.pinned().borrow_mut()._set(
				Path::new(&parent),
				"Radio",
				"Selected",
				&value,
				true,
			);

			let (exec, name) = {
				let config = self.config.pinned();
				let config = config.borrow();
				(
					config.radio_exec.to_string(),
					get_item_title(Path::new(&path)),
				)
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
			self.run_refresh_if_configured();
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
				// `result_for` itself hides thumbnails for descriptor-owned
				// items, so the two systems cannot fight over the slot.
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

	/// Move finished descriptor-generator results (a ROM's title and icon, for
	/// example) into the model. Titles are updated for every item, not only the
	/// visible ones, so scrolling to an item generated minutes ago still shows
	/// its proper name; rows that are visible are repainted.
	poll_descriptors: qt_method!(
		pub fn poll_descriptors(&mut self) -> bool {
			let epoch = crate::descriptor_generator::results_epoch();
			if epoch == self.last_descriptor_epoch {
				return false;
			}
			// Apply a folder's results only after its queue has drained: one
			// repaint for the whole batch, rather than one per ROM while the
			// workers are still producing them.
			if crate::descriptor_generator::folder_busy(Path::new(&self.path_str)) {
				return false;
			}
			self.last_descriptor_epoch = epoch;
			if !crate::descriptor_generator::has_results() {
				return false;
			}
			let mut applied = false;
			for index in 0..self.items.len() {
				let item = &self.items[index];
				let Some(generated) = crate::descriptor_generator::result_for(&item.path) else {
					continue;
				};
				let title = generated
					.name
					.filter(|name| !name.trim().is_empty())
					.unwrap_or_else(|| item.title.clone());
				let icon = generated.icon.unwrap_or_else(|| item.icon.clone());
				// Do not skip an unchanged title/icon: a generator that was
				// asked again may have rewritten the same image path after
				// the file had disappeared, and the view needs a repaint to
				// load it again.
				self.items[index].title = title;
				self.items[index].icon = icon;
				applied = true;
				if let Some(row) = self.visible.iter().position(|visible| *visible == index) {
					let model_index = self.row_index(row as i32);
					self.data_changed(model_index, model_index);
				}
			}
			applied
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
				// Plain files have no entry to re-read; skipping them here used
				// to mean a stat (and, before the size gate, a header read) for
				// every ROM in the folder every second.
				if !item.is_entry {
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

	/// Ask for a generated descriptor (a ROM's title and artwork) for one
	/// visible item. Requesting used to happen for every file during the scan,
	/// which queued a thousand generator runs when a ROM folder was opened and
	/// left the background workers saturating the CPU and SD card while the
	/// user was trying to scroll. The grid asks for the items it is showing,
	/// exactly like thumbnails.
	request_descriptor: qt_method!(
		pub fn request_descriptor(&mut self, path: String) {
			if self.path_str.is_empty() {
				return;
			}
			crate::descriptor_generator::request(Path::new(&path), Path::new(&self.path_str));
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

	set_free_positions: qt_method!(
		pub fn set_free_positions(&mut self, positions_json: String) {
			let path = self.path_str.clone();
			let entries = parse_free_position_entries(&positions_json);
			self.config
				.pinned()
				.borrow_mut()
				.set_free_positions(Path::new(&path), &entries);
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
			let include_hidden = {
				let config = self.config.pinned();
				let config = config.borrow();
				!config.stash_dotfiles || config.show_stash
			};
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

	/// Lay out a grouped folder. Returns item slots (with both a logical cell
	/// for focus navigation and a pixel position) and the group headers. Free
	/// placement has its own layout and never reaches this.
	group_layout: qt_method!(
		fn group_layout(
			&self,
			horizontal: bool,
			view_width: f64,
			view_height: f64,
			item_width: f64,
			item_height: f64,
			gap: f64,
			header_size: f64,
			lines: i32,
			list_mode: bool,
		) -> String {
			self.compute_group_layout(
				horizontal,
				view_width,
				view_height,
				item_width,
				item_height,
				gap,
				header_size,
				lines,
				list_mode,
			)
		}
	),

	load_directory: qt_method!(
		fn load_directory(&mut self, path: String, include_hidden: bool) {
			// Re-reading a folder drops its pending preview and descriptor work;
			// results that are still in flight simply no longer match any item.
			if !self.path_str.is_empty() {
				crate::thumbnailer::cancel_folder(Path::new(&self.path_str));
				crate::descriptor_generator::cancel_folder(Path::new(&self.path_str));
			}
			Directory::new(self, path, include_hidden);
		}
	),
}

impl Directory {
	pub fn new(&mut self, path: String, include_hidden: bool) {
		// First pass: names and kinds only. It is the cheap half of the scan
		// (readdir already has the names), and it lets the view reserve every
		// cell at once instead of showing an empty folder while the worker
		// reads metadata from a cold card.
		let placeholder_start = Instant::now();
		let placeholders = placeholder_items(&path, include_hidden);
		let placeholder_ms = placeholder_start.elapsed().as_millis();
		self.begin_reset_model();
		self.items = placeholders;
		self.sort_items();
		self.apply_filter();
		self.exposed = self.visible.len();
		self.exposing = false;
		self.end_reset_model();
		self.exposure_changed();
		if crate::file_manager::perf_mode() > 0 {
			eprintln!(
				"hishell-perf: placeholders {} items from {} in {} ms",
				self.items.len(),
				self.path_str,
				placeholder_ms
			);
		}

		self.scan_generation = self.scan_generation.wrapping_add(1);
		let generation = self.scan_generation;
		self.scanning = true;
		self.scanning_changed();
		self.dir_modified = folder_modified(&self.path_str);

		let (tx, rx) = mpsc::channel();
		self.scan_rx = Some(rx);
		let scan_path = path.clone();
		let spawned = std::thread::Builder::new()
			.name("directory-scan".into())
			.spawn(move || {
				let items = scan_items(&scan_path, include_hidden);
				let _ = tx.send((generation, scan_path, items));
			});
		if spawned.is_err() {
			self.scan_rx = None;
			self.scanning = false;
			self.scanning_changed();
		}
	}

	/// Install a finished worker scan on the GUI thread. The placeholder pass
	/// already put every path in the model; if the final sort keeps that order,
	/// only the row data changes, so the scroll position and delegates survive.
	fn apply_scan(&mut self, items: Vec<FileItem>) {
		let reset_start = Instant::now();
		let old_visible: Vec<String> = self
			.visible
			.iter()
			.filter_map(|index| self.items.get(*index))
			.map(|item| item.path.clone())
			.collect();
		self.items = items;
		self.sort_items();
		self.apply_filter();
		let same_order = self.visible.len() == old_visible.len()
			&& self
				.visible
				.iter()
				.zip(old_visible.iter())
				.all(|(index, path)| self.items[*index].path == *path);
		if same_order {
			self.exposed = self.visible.len();
			self.exposing = false;
			if !self.visible.is_empty() {
				let last = self.visible.len() as i32 - 1;
				self.data_changed(self.row_index(0), self.row_index(last));
			}
		} else {
			self.begin_reset_model();
			self.start_exposure();
			self.end_reset_model();
		}
		self.scanning = false;
		self.scanning_changed();
		self.exposure_changed();
		self.dir_modified = folder_modified(&self.path_str);
		if crate::file_manager::perf_mode() > 0 {
			eprintln!(
				"hishell-perf: reset {} items from {} in {} ms{}",
				self.items.len(),
				self.path_str,
				reset_start.elapsed().as_millis(),
				if same_order { " (data)" } else { "" }
			);
		}
	}

	/// Re-sort the in-memory items after a sort-related config change, without
	/// touching the filesystem.
	fn resort_items(&mut self) {
		self.begin_reset_model();
		self.sort_items();
		self.apply_filter();
		self.exposed = self.visible.len();
		self.exposing = false;
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

		self.assign_groups();
	}

	/// Put the sorted items into their display groups. The sort inside a group
	/// is the order the folder already chose; grouping only moves whole blocks
	/// of items around. Free placement is never grouped.
	fn assign_groups(&mut self) {
		let (sort, group_mode, show_stash, stash_dotfiles, groups_json) = {
			let pinned = self.config.pinned();
			let config = pinned.borrow();
			(
				config.sort,
				config.group_mode,
				config.show_stash,
				config.stash_dotfiles,
				config.groups.to_string(),
			)
		};

		self.group_labels.clear();
		for item in &mut self.items {
			item.group = 0;
			item.group_label.clear();
		}

		// Free placement owns its cells, so a group header could not move the
		// items around it. The two features are mutually exclusive.
		if sort == 3 {
			return;
		}

		const UNTITLED_RANK: i64 = 1_000_000;
		const STASH_RANK: i64 = 1_000_001;

		let stash_active = show_stash;
		if group_mode == 0 && !stash_active {
			return;
		}

		let now = date_context();
		let custom = parse_custom_groups(&groups_json);
		let mut custom_names: Vec<String> = custom.iter().map(|group| group.name.clone()).collect();
		let mut file_groups: HashMap<String, usize> = HashMap::new();
		for (index, group) in custom.iter().enumerate() {
			for file in &group.files {
				file_groups.insert(file.clone(), index);
			}
		}

		let mut keyed: Vec<((i64, String), usize)> = Vec::with_capacity(self.items.len());
		for (index, item) in self.items.iter().enumerate() {
			let key = if stash_active && stash_dotfiles && item.is_stashed {
				(STASH_RANK, "Stash".to_string())
			} else {
				match group_mode {
					1 => date_group_key(item.modified, now.as_ref()),
					2 => letter_group_key(item),
					3 => type_group_key(item),
					4 => {
						let explicit = item.custom_group.trim();
						let name = if !explicit.is_empty() {
							explicit.to_string()
						} else {
							file_groups
								.get(&item.name)
								.or_else(|| file_groups.get(&item.title))
								.and_then(|index| custom_names.get(*index))
								.cloned()
								.unwrap_or_default()
						};
						if name.is_empty() {
							(UNTITLED_RANK, String::new())
						} else {
							let rank = match custom_names.iter().position(|known| known == &name) {
								Some(position) => position as i64,
								None => {
									custom_names.push(name.clone());
									(custom_names.len() - 1) as i64
								}
							};
							(rank, name)
						}
					}
					_ => (0, String::new()),
				}
			};
			keyed.push((key, index));
		}

		let mut order: Vec<(i64, String)> = Vec::new();
		{
			let mut seen = std::collections::BTreeMap::new();
			for (key, _) in &keyed {
				seen.insert(key.clone(), ());
			}
			order.extend(seen.into_keys());
		}
		self.group_labels = order.iter().map(|(_, label)| label.clone()).collect();
		let mut positions = HashMap::new();
		for (index, key) in order.iter().enumerate() {
			positions.insert(key.clone(), index as u16);
		}
		for (key, item_index) in keyed {
			if let Some(&group) = positions.get(&key) {
				self.items[item_index].group = group;
				self.items[item_index].group_label = key.1;
			}
		}
		self.items.sort_by_key(|item| item.group);
	}

	/// Expose the whole listing at once. The view needs the final row count to
	/// have stable scroll geometry while the cursor is placed on entry; growing
	/// the model a row at a time made the content height move under the view.
	/// The delegates themselves defer their content, so a large folder still
	/// fills its visible slots over a few frames instead of building them all in
	/// one reset.
	fn start_exposure(&mut self) {
		self.exposed = self.visible.len();
		self.exposing = false;
	}

	/// Expose the next rows. The listing is now exposed in full on load, so
	/// this returns false; it remains for older views and tests.
	pub fn expose_more(&mut self) -> bool {
		let total = self.visible.len();
		if self.exposed >= total {
			if self.exposing {
				self.exposing = false;
				self.exposure_changed();
			}
			return false;
		}
		let target = if self.exposed < total.min(48) {
			(self.exposed + 1).min(total)
		} else {
			total
		};
		if target > self.exposed {
			self.begin_insert_rows(self.exposed as i32, (target - 1) as i32);
			self.exposed = target;
			self.end_insert_rows();
		}
		if self.exposed >= total {
			self.exposing = false;
			self.exposure_changed();
		}
		true
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
		self.exposed = self.visible.len();
		self.exposing = false;
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

	/// Run this folder's `Refresh=` command, when it has one.  Entering a
	/// folder calls this once; the manual Refresh action calls it too.  A plain
	/// read never scans (docs §4.3).
	fn run_refresh_if_configured(&self) {
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
		let entered = self.path_str != abs_str;

		if !self.path_str.is_empty() && self.path_str != abs_str {
			crate::thumbnailer::cancel_folder(Path::new(&self.path_str));
			crate::descriptor_generator::cancel_folder(Path::new(&self.path_str));
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
		let include_hidden = {
			let config = self.config.pinned();
			let config = config.borrow();
			!config.stash_dotfiles || config.show_stash
		};

		// The provider hook can create or rewrite the entries the scan is about
		// to read, so it has to run first. The scan itself is asynchronous.
		if entered {
			self.run_refresh_if_configured();
		}
		self.load_directory(load_path, include_hidden);

		self.path_changed();
		self.config_changed();
	}

	pub fn get_title(&self) -> String {
		get_item_title(Path::new(&self.path_str))
	}

	/// Grouped layout: labels reserve space of their own, then the items flow
	/// in rows (vertical scrolling) or columns (horizontal scrolling).  The
	/// returned positions are absolute because a header is not the same size
	/// as an item, so a plain row/column modulo cannot place an item.
	#[allow(clippy::too_many_arguments)]
	fn compute_group_layout(
		&self,
		horizontal: bool,
		view_width: f64,
		view_height: f64,
		item_width: f64,
		item_height: f64,
		gap: f64,
		header_size: f64,
		lines: i32,
		list_mode: bool,
	) -> String {
		let count = self.visible.len();
		if count == 0 {
			return serde_json::json!({
				"grouped": true,
				"horizontal": horizontal,
				"stride": 1,
				"columns": 0,
				"rows": 0,
				"slots": [],
				"groups": [],
				"naturalWidth": view_width.max(0.0),
				"naturalHeight": view_height.max(0.0),
			})
			.to_string();
		}

		let item_width = item_width.max(1.0);
		let item_height = item_height.max(1.0);
		let gap = gap.max(0.0);
		let header_size = header_size.max(0.0);

		// Contiguous runs in the already-grouped `visible` order. Keeping the
		// item indices lets the layout place the actual model rows.
		let mut runs: Vec<(String, Vec<usize>)> = Vec::new();
		for &index in &self.visible {
			let item = &self.items[index];
			let label = self
				.group_labels
				.get(item.group as usize)
				.cloned()
				.unwrap_or_else(|| item.group_label.clone());
			match runs.last_mut() {
				Some((last, indices)) if *last == label => indices.push(index),
				_ => runs.push((label, vec![index])),
			}
		}

		if list_mode {
			let mut y = 0.0;
			let mut row = 0;
			let mut slots = Vec::with_capacity(count);
			let mut groups = Vec::new();
			for (label, indices) in runs {
				if !label.is_empty() {
					groups.push(serde_json::json!({
						"label": label,
						"x": 0.0,
						"y": y,
						"width": item_width,
						"height": header_size,
						"horizontal": false,
					}));
					y += header_size + gap;
					row += 1;
				}
				for _ in indices {
					slots.push(serde_json::json!({
						"c": 0,
						"r": row,
						"x": 0.0,
						"y": y,
					}));
					y += item_height + gap;
					row += 1;
				}
			}
			return serde_json::json!({
				"grouped": true,
				"horizontal": false,
				"stride": 1,
				"columns": 1,
				"rows": row.max(1),
				"slots": slots,
				"groups": groups,
				"naturalWidth": item_width,
				"naturalHeight": (y - gap).max(0.0),
			})
			.to_string();
		}

		if horizontal {
			let fitting = (((view_height + gap) / (item_height + gap)).floor() as i32).max(1);
			let stride = if lines > 0 {
				lines.clamp(1, fitting)
			} else {
				fitting
			};
			let group_height = stride as f64 * item_height + (stride - 1) as f64 * gap;
			let mut x = 0.0;
			let mut column = 0;
			let mut slots = Vec::with_capacity(count);
			let mut groups = Vec::new();
			for (label, indices) in runs {
				let has_header = !label.is_empty();
				let item_columns = ((indices.len() as f64 / stride as f64).ceil() as i32).max(1);
				if has_header {
					groups.push(serde_json::json!({
						"label": label,
						"x": x,
						"y": 0.0,
						"width": header_size,
						"height": group_height,
						"horizontal": true,
					}));
				}
				let header_columns = i32::from(has_header);
				let items_x = x + header_columns as f64 * (header_size + gap);
				for (offset, _) in indices.iter().enumerate() {
					let item_column = offset as i32 / stride;
					let row = offset as i32 % stride;
					slots.push(serde_json::json!({
						"c": column + header_columns + item_column,
						"r": row,
						"x": items_x + item_column as f64 * (item_width + gap),
						"y": row as f64 * (item_height + gap),
					}));
				}
				let span = header_columns + item_columns;
				x += span as f64 * item_width
					+ header_columns as f64 * (header_size - item_width)
					+ span as f64 * gap;
				column += span;
			}
			return serde_json::json!({
				"grouped": true,
				"horizontal": true,
				"stride": stride,
				"columns": column.max(1),
				"rows": stride,
				"slots": slots,
				"groups": groups,
				"naturalWidth": (x - gap).max(0.0),
				"naturalHeight": group_height.max(0.0),
			})
			.to_string();
		}

		let fitting = (((view_width + gap) / (item_width + gap)).floor() as i32).max(1);
		let stride = if lines > 0 {
			lines.clamp(1, fitting)
		} else {
			fitting
		};
		let natural_width = stride as f64 * item_width + (stride - 1) as f64 * gap;
		let mut y = 0.0;
		let mut row = 0;
		let mut slots = Vec::with_capacity(count);
		let mut groups = Vec::new();
		for (label, indices) in runs {
			if !label.is_empty() {
				groups.push(serde_json::json!({
					"label": label,
					"x": 0.0,
					"y": y,
					"width": natural_width,
					"height": header_size,
					"horizontal": false,
				}));
				y += header_size + gap;
				row += 1;
			}
			let rows = ((indices.len() as f64 / stride as f64).ceil() as i32).max(1);
			for (offset, _) in indices.iter().enumerate() {
				let column = offset as i32 % stride;
				let item_row = offset as i32 / stride;
				slots.push(serde_json::json!({
					"c": column,
					"r": row + item_row,
					"x": column as f64 * (item_width + gap),
					"y": y + item_row as f64 * (item_height + gap),
				}));
			}
			y += rows as f64 * item_height + (rows - 1) as f64 * gap + gap;
			row += rows;
		}
		serde_json::json!({
			"grouped": true,
			"horizontal": false,
			"stride": stride,
			"columns": stride,
			"rows": row.max(1),
			"slots": slots,
			"groups": groups,
			"naturalWidth": natural_width,
			"naturalHeight": (y - gap).max(0.0),
		})
		.to_string()
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

/// A local-time snapshot used to place a folder's items into date groups.
struct DateContext {
	tm: libc::tm,
	days: i64,
}

fn local_tm(ms: u64) -> Option<libc::tm> {
	if ms == 0 {
		return None;
	}
	let seconds = (ms / 1000) as libc::time_t;
	let mut tm = std::mem::MaybeUninit::<libc::tm>::uninit();
	// SAFETY: `localtime_r` fills the caller-owned struct and never retains the
	// seconds pointer.
	let filled = unsafe { libc::localtime_r(&seconds, tm.as_mut_ptr()) };
	if filled.is_null() {
		None
	} else {
		Some(unsafe { tm.assume_init() })
	}
}

/// Days since 1970-01-01 for a civil date (Howard Hinnant's algorithm).
fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
	let y = year - i64::from(month <= 2);
	let era = if y >= 0 { y } else { y - 399 } / 400;
	let yoe = y - era * 400;
	let mp = (month + 9) % 12;
	let doy = (153 * mp + 2) / 5 + day - 1;
	let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
	era * 146_097 + doe - 719_468
}

fn date_context() -> Option<DateContext> {
	let now_ms = SystemTime::now()
		.duration_since(UNIX_EPOCH)
		.ok()
		.map(|duration| duration.as_millis() as u64)?;
	let tm = local_tm(now_ms)?;
	let days = days_from_civil(
		i64::from(tm.tm_year) + 1900,
		i64::from(tm.tm_mon) + 1,
		i64::from(tm.tm_mday),
	);
	Some(DateContext { tm, days })
}

const WEEKDAYS: [&str; 7] = [
	"Sunday",
	"Monday",
	"Tuesday",
	"Wednesday",
	"Thursday",
	"Friday",
	"Saturday",
];

const MONTHS: [&str; 12] = [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
];

fn date_group_key(ms: u64, now: Option<&DateContext>) -> (i64, String) {
	let (Some(now), Some(tm)) = (now, local_tm(ms)) else {
		return (999_999, "Unknown".to_string());
	};
	let days = days_from_civil(
		i64::from(tm.tm_year) + 1900,
		i64::from(tm.tm_mon) + 1,
		i64::from(tm.tm_mday),
	);
	let ago = now.days - days;
	if ago <= 0 {
		return (0, "Today".to_string());
	}
	match ago {
		1 => (1, "Yesterday".to_string()),
		2..=6 => (ago, WEEKDAYS[(tm.tm_wday.clamp(0, 6)) as usize].to_string()),
		7..=13 => (7, "Last week".to_string()),
		_ if tm.tm_year == now.tm.tm_year && tm.tm_mon == now.tm.tm_mon => {
			(8, "This month".to_string())
		}
		_ if tm.tm_year == now.tm.tm_year => {
			let months_ago = now.tm.tm_mon - tm.tm_mon;
			(
				20 + i64::from(months_ago),
				MONTHS[(tm.tm_mon.clamp(0, 11)) as usize].to_string(),
			)
		}
		_ => {
			let years_ago = now.tm.tm_year - tm.tm_year;
			(
				100 + i64::from(years_ago),
				format!("{}", i64::from(tm.tm_year) + 1900),
			)
		}
	}
}

fn letter_group_key(item: &FileItem) -> (i64, String) {
	let name = if item.title.is_empty() {
		&item.name
	} else {
		&item.title
	};
	let letter = name
		.chars()
		.find(|character| character.is_alphanumeric())
		.unwrap_or('#');
	(0, letter.to_uppercase().collect())
}

fn type_group_key(item: &FileItem) -> (i64, String) {
	if item.is_dir {
		return (0, "Folders".to_string());
	}
	if item.control_kind != 0
		|| Path::new(&item.path)
			.extension()
			.and_then(|extension| extension.to_str())
			.is_some_and(|extension| {
				extension.eq_ignore_ascii_case("desktop")
					|| extension.eq_ignore_ascii_case("appimage")
			}) {
		return (6, "Apps".to_string());
	}
	let mime = from_path(&item.path).first_or_octet_stream();
	let essence = mime.essence_str();
	let (rank, label) = if essence.starts_with("image/") {
		(1, "Images")
	} else if essence.starts_with("video/") {
		(2, "Videos")
	} else if essence.starts_with("audio/") {
		(3, "Audio")
	} else if essence.starts_with("text/")
		|| essence == "application/pdf"
		|| essence == "application/json"
		|| essence == "application/xml"
	{
		(4, "Documents")
	} else if essence.contains("zip")
		|| essence.contains("tar")
		|| essence.contains("gzip")
		|| essence.contains("compressed")
		|| essence.contains("archive")
	{
		(5, "Archives")
	} else {
		(7, "Other")
	};
	(rank, label.to_string())
}

struct CustomGroup {
	name: String,
	files: Vec<String>,
}

fn parse_custom_groups(json: &str) -> Vec<CustomGroup> {
	let Ok(value) = serde_json::from_str::<serde_json::Value>(json) else {
		return Vec::new();
	};
	let Some(entries) = value.as_array() else {
		return Vec::new();
	};
	let mut groups = Vec::new();
	for entry in entries {
		let name = entry
			.get("name")
			.or_else(|| entry.get("Name"))
			.and_then(|value| value.as_str())
			.unwrap_or_default()
			.trim()
			.to_string();
		if name.is_empty() {
			continue;
		}
		let files = entry
			.get("files")
			.or_else(|| entry.get("Files"))
			.and_then(|value| value.as_array())
			.map(|files| {
				files
					.iter()
					.filter_map(|file| file.as_str())
					.map(str::to_string)
					.collect()
			})
			.unwrap_or_default();
		groups.push(CustomGroup { name, files });
	}
	groups
}

/// Parse a `{ "name": [col, row], ... }` map as used by
/// `FreePlacementPositions`.
fn parse_free_position_entries(json: &str) -> Vec<(String, i32, i32)> {
	let mut entries = Vec::new();
	if let Ok(value) = serde_json::from_str::<serde_json::Value>(json)
		&& let Some(obj) = value.as_object()
	{
		for (name, pos) in obj {
			if let Some(arr) = pos.as_array() {
				let col = arr.first().and_then(|v| v.as_i64()).unwrap_or(0) as i32;
				let row = arr.get(1).and_then(|v| v.as_i64()).unwrap_or(0) as i32;
				entries.push((name.clone(), col, row));
			}
		}
	}
	entries
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
		self.exposed as i32
	}

	fn data(&self, index: QModelIndex, role: i32) -> QVariant {
		if index.row() < 0 || index.row() as usize >= self.exposed {
			return QVariant::default();
		}
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
			// Sizes and times are exposed for the list view's optional columns.
			// Times are Unix milliseconds, like the values the sort modes use.
			0x0106 => QVariant::from(item.size as f64),
			0x0107 => QVariant::from(item.modified as f64),
			0x0108 => QVariant::from(item.created as f64),
			0x0109 => QVariant::from(item.accessed as f64),
			0x010a => i32::from(item.control_kind).into(),
			0x010b => item.toggle_on.into(),
			0x010c => QString::from(item.number_value.as_str()).into(),
			0x010d => i32::from(item.group).into(),
			0x010e => QString::from(item.group_label.as_str()).into(),
			0x010f => item.is_stashed.into(),
			0x0110 => QString::from(item.comment.as_str()).into(),
			_ => QVariant::default(),
		}
	}

	fn role_names(&self) -> HashMap<i32, QByteArray> {
		let mut map = HashMap::new();
		map.insert(0x0100, "name".into());
		map.insert(0x0101, "path".into());
		map.insert(0x0102, "is_directory".into());
		map.insert(0x0103, "icon".into());
		map.insert(0x0104, "title".into());
		map.insert(0x0105, "is_symlink".into());
		map.insert(0x0106, "size_bytes".into());
		map.insert(0x0107, "modified_time".into());
		map.insert(0x0108, "created_time".into());
		map.insert(0x0109, "accessed_time".into());
		map.insert(0x010a, "control_kind".into());
		map.insert(0x010b, "toggle_on".into());
		map.insert(0x010c, "number_value".into());
		map.insert(0x010d, "group_index".into());
		map.insert(0x010e, "group_label".into());
		map.insert(0x010f, "is_stashed".into());
		map.insert(0x0110, "comment".into());
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

/// Whether a directory's own `.directory` should be probed while listing its
/// parent. On vfat a lookup for a missing name scans the whole directory, and
/// ROM folders hold thousands of entries, so listing `ROMS` spent ~800 ms
/// checking for `.directory` in each console folder. Removable media is
/// described by directory descriptors instead; a folder's own `.directory` is
/// still loaded when the folder is entered.
fn directory_entry_allowed(path: &Path) -> bool {
	let text = path.to_string_lossy();
	!text.starts_with("/mnt/")
		&& text != "/mnt"
		&& !text.starts_with("/media/")
		&& !text.starts_with("/run/media/")
}

pub fn get_item_title(path: &Path) -> String {
	// A directory always has an entry *path* (its `.directory`), but most
	// directories do not have the file. Reading the missing file was cached,
	// yet still involved a stat and a parse for every folder in a scan.
	if directory_entry_allowed(path)
		&& crate::config::entry_path(path).is_some_and(|entry| entry.is_file())
	{
		let entry = crate::desktop_entry::read(path);
		if let Some(name) = entry.name.filter(|name| !name.is_empty()) {
			return name;
		}
	}

	title_from_descriptor(path)
}

fn title_from_descriptor(path: &Path) -> String {
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

/// The secondary `Comment=` line for an item, resolved the same way the file
/// view resolves it: the item's own entry first, then its descriptor, then an
/// AppImage's embedded entry. Empty means no comment.
pub fn get_item_comment(path: &Path) -> String {
	if directory_entry_allowed(path)
		&& crate::config::entry_path(path).is_some_and(|entry| entry.is_file())
	{
		let entry = crate::desktop_entry::read(path);
		if let Some(comment) = entry.comment.filter(|comment| !comment.trim().is_empty()) {
			return comment;
		}
	}

	if let Some(descriptor) = crate::directory_descriptor::lookup(path) {
		if let Some(comment) = descriptor
			.comment
			.filter(|comment| !comment.trim().is_empty())
		{
			return comment;
		}
	}

	if let Some(entry) = crate::appimage::desktop_entry(path) {
		if let Some(comment) = entry.comment.filter(|comment| !comment.trim().is_empty()) {
			return comment;
		}
	}

	String::new()
}

pub fn get_icon(path: &str) -> String {
	// An empty path would make `gio info` inspect the current working directory,
	// so bail out before any filesystem or gio lookup can happen.
	if path.trim().is_empty() {
		return "text-x-generic".to_string();
	}

	let path_buf = Path::new(path);
	let is_dir = path_buf.is_dir();

	if is_dir && !directory_entry_allowed(path_buf) {
		return get_folder_icon(path);
	}

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

	// A file descriptor supplies the name and icon from outside the file, the
	// same way a directory descriptor describes a mounted card. A generated
	// ROM entry lives in the descriptor cache and arrives here through this
	// lookup, so no special case is needed once it has been written.
	if let Some(descriptor) = crate::directory_descriptor::lookup(path_buf) {
		if let Some(icon) = descriptor.icon {
			return icon_source(icon, crate::config::base_dir(path_buf));
		}
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

	// A content type owned by a descriptor generator keeps that generator's
	// placeholder even when no descriptor could be produced. Otherwise the
	// `gio` icon (the bare type name, which the theme may not ship) would win
	// and the file would look generic.
	if let Some(icon) = crate::descriptor_generator::placeholder_icon(path_buf) {
		ICON_CACHE.lock().unwrap().insert(key, icon.clone());
		return icon;
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
		// A descriptor may be written just before its image. Keep the
		// source an absolute URL even when the image is not there yet:
		// returning a bare `/path` makes QML resolve it against `qrc:`,
		// so the icon can never appear once the image is written.
		Err(_) if path.is_absolute() => {
			format!("file://{}", path.to_string_lossy())
		}
		Err(_) => icon,
	}
}

/// Well-known folders and the icons that distinguish them. Resolved once:
/// this used to canonicalise the home directory and all eight XDG directories
/// inside every folder-icon lookup, which cost more than the rest of a scan on
/// a slow SD card.
struct FolderPlaces {
	home: Option<PathBuf>,
	dirs: Vec<(PathBuf, &'static str)>,
}

static FOLDER_PLACES: Lazy<FolderPlaces> = Lazy::new(|| {
	let home = dirs::home_dir().and_then(|path| std::fs::canonicalize(path).ok());
	let candidates: &[(fn() -> Option<PathBuf>, &str, &str)] = &[
		(dirs::desktop_dir, "Desktop", "folder-desktop"),
		(dirs::download_dir, "Downloads", "folder-download"),
		(dirs::picture_dir, "Pictures", "folder-pictures"),
		(dirs::audio_dir, "Music", "folder-music"),
		(dirs::video_dir, "Videos", "folder-videos"),
		(dirs::document_dir, "Documents", "folder-documents"),
		(dirs::template_dir, "Templates", "folder-templates"),
		(dirs::public_dir, "Public", "folder-public"),
	];
	let dirs = candidates
		.iter()
		.filter_map(|(get_dir, fallback_name, icon)| {
			let target =
				get_dir().or_else(|| home.as_ref().map(|home| home.join(fallback_name)))?;
			let target = std::fs::canonicalize(&target).unwrap_or(target);
			Some((target, *icon))
		})
		.collect();
	FolderPlaces { home, dirs }
});

pub fn get_folder_icon(path: &str) -> String {
	let path_buf = Path::new(path);
	// The scan paths are already absolute. Canonicalising each directory (and
	// each well-known place) made a folder of console folders on the SD card
	// take most of a second. Removable paths are described by descriptors and
	// are never symlinks we need to resolve here.
	let removable = !directory_entry_allowed(path_buf);
	let abs_path = if path_buf.is_absolute() && (removable || !path_buf.is_symlink()) {
		path_buf.to_path_buf()
	} else {
		std::fs::canonicalize(path_buf).unwrap_or_else(|_| path_buf.to_path_buf())
	};

	if directory_entry_allowed(&abs_path)
		&& let Some(icon) = config::get_image(&abs_path, "Desktop Entry", "Icon")
		&& !icon.is_empty()
	{
		return icon_source(icon, &abs_path);
	}

	// A directory descriptor supplies the name and icon from outside the
	// directory, so a mounted card that cannot carry its own `.directory`
	// still shows a device icon (see `directory_descriptor`).
	if let Some(descriptor) = crate::directory_descriptor::lookup(&abs_path) {
		if let Some(icon) = descriptor.icon {
			return icon_source(icon, &abs_path);
		}
	}

	let places = &*FOLDER_PLACES;
	if places.home.as_ref().is_some_and(|home| abs_path == *home) {
		return "user-home".to_string();
	}
	for (target, icon) in &places.dirs {
		if abs_path == *target {
			return (*icon).to_string();
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
	let _ = crate::launch::spawn(
		"xdg-open",
		std::slice::from_ref(&path),
		&path,
		"xdg-open",
		"",
		None,
	);
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

#[cfg(test)]
mod tests {
	use super::*;
	use std::os::unix::fs::PermissionsExt;
	use std::time::{Duration, Instant};

	#[test]
	fn custom_groups_keep_their_declared_order_and_files() {
		let groups = parse_custom_groups(
			r#"[{"name":"Clock","files":["datetime.desktop","timezone"]},
			    {"name":"Display","files":["brightness.desktop"]}]"#,
		);
		assert_eq!(groups.len(), 2);
		assert_eq!(groups[0].name, "Clock");
		assert_eq!(groups[0].files, ["datetime.desktop", "timezone"]);
		assert_eq!(groups[1].name, "Display");
	}

	#[test]
	fn date_keys_are_based_on_the_civil_day() {
		assert_eq!(days_from_civil(1970, 1, 1), 0);
		assert_eq!(days_from_civil(1970, 1, 2), 1);
		assert_eq!(days_from_civil(2000, 3, 1), 11017);
	}

	#[test]
	fn grouped_layout_reserves_a_row_for_each_header() {
		let mut directory = Directory::default();
		directory.group_labels = vec!["First".to_string(), String::new(), "Stash".to_string()];
		let mut items = Vec::new();
		for (group, label) in [(0, "First"), (1, ""), (2, "Stash")] {
			let mut item = FileItem::default();
			item.name = label.to_string();
			item.group = group;
			item.group_label = label.to_string();
			items.push(item);
		}
		directory.items = items;
		directory.visible = (0..directory.items.len()).collect();

		let json =
			directory.compute_group_layout(false, 300.0, 300.0, 50.0, 50.0, 10.0, 20.0, 0, false);
		let value: serde_json::Value = serde_json::from_str(&json).unwrap();
		assert_eq!(value["groups"].as_array().unwrap().len(), 2);
		assert_eq!(value["slots"].as_array().unwrap().len(), 3);
		// The untitled group draws no header, so it starts on the next item row.
		assert_eq!(value["slots"][1]["r"], 2);
		// Stash has a header of its own and is last.
		assert_eq!(value["groups"][1]["label"], "Stash");
		assert_eq!(value["slots"][2]["r"], 4);
	}

	#[test]
	fn radio_exec_exports_the_selected_item() {
		let root = std::env::temp_dir().join(format!("hishell-radio-exec-{}", std::process::id()));
		std::fs::create_dir_all(&root).unwrap();
		let script = root.join("capture.sh");
		let output = root.join("item");
		std::fs::write(
			&script,
			format!(
				"#!/bin/sh\nprintf '%s' \"$HISHELL_APP_ITEM\" > '{}'\n",
				output.display()
			),
		)
		.unwrap();
		std::fs::set_permissions(&script, std::fs::Permissions::from_mode(0o755)).unwrap();

		let selected = root.join("Bluetooth/AA:BB:CC:DD:EE:FF.desktop");
		std::fs::create_dir_all(selected.parent().unwrap()).unwrap();
		run_radio_exec(
			script.to_str().unwrap(),
			"AA:BB:CC:DD:EE:FF",
			"Controller",
			selected.to_str().unwrap(),
		);

		let deadline = Instant::now() + Duration::from_secs(5);
		let item = loop {
			if let Ok(text) = std::fs::read_to_string(&output) {
				break text;
			}
			assert!(Instant::now() < deadline, "radio command did not run");
			std::thread::sleep(Duration::from_millis(20));
		};
		assert_eq!(item, selected.to_str().unwrap());
		std::fs::remove_dir_all(&root).ok();
	}
}
/// The cheap first pass: names and file kinds, no metadata, titles or icons.
/// The worker fills those in; keeping this pass on the GUI thread is what makes
/// the empty cells appear immediately on a cold card.
fn placeholder_items(path: &str, include_hidden: bool) -> Vec<FileItem> {
	let mut items = Vec::new();
	let Ok(entries) = fs::read_dir(path) else {
		return items;
	};
	for entry in entries.flatten() {
		let name = entry.file_name().to_string_lossy().to_string();
		if name.starts_with('.') && !include_hidden {
			continue;
		}
		let entry_path = entry.path();
		let file_type = entry.file_type().ok();
		let is_symlink = file_type.map(|t| t.is_symlink()).unwrap_or(false);
		// `DirEntry::file_type` does not follow links, so a symlink to a
		// directory would otherwise be a file to the view: no folder icon, no
		// drop target and no spring-load. Follow only the links, keeping the
		// ordinary entries on the cheap `file_type` path.
		let is_dir =
			file_type.map(|t| t.is_dir()).unwrap_or(false) || (is_symlink && entry_path.is_dir());
		let is_stashed = name.starts_with('.');
		items.push(FileItem {
			title: name.clone(),
			comment: String::new(),
			path: entry_path.to_string_lossy().to_string(),
			is_dotfile: is_stashed,
			name,
			is_dir,
			is_symlink,
			icon: if is_dir {
				"folder".to_string()
			} else {
				"text-x-generic".to_string()
			},
			is_entry: false,
			control_kind: 0,
			toggle_on: false,
			number_value: String::new(),
			size: 0,
			modified: 0,
			created: 0,
			accessed: 0,
			group: 0,
			group_label: String::new(),
			is_stashed,
			custom_group: String::new(),
		});
	}
	items
}

/// The filesystem half of a folder scan. Runs on a worker thread, so it must
/// not touch the QObject or any Qt state.
fn scan_items(path: &str, include_hidden: bool) -> Vec<FileItem> {
	let scan_start = Instant::now();
	let mut items = Vec::new();
	let listing = fs::read_dir(path);

	if let Ok(entries) = listing {
		for entry in entries.flatten() {
			let name = entry.file_name().to_string_lossy().to_string();

			if name.starts_with('.') && !include_hidden {
				continue;
			}

			let entry_path = entry.path();
			let is_dotfile = name.starts_with('.');
			let file_type = entry.file_type().ok();
			let is_symlink = file_type.map(|t| t.is_symlink()).unwrap_or(false);
			// A link to a folder is a folder for icons, drops and
			// spring-load, just like the target it opens. `file_type` sees
			// only the link, so resolve exactly those entries.
			let is_dir = file_type.map(|t| t.is_dir()).unwrap_or(false)
				|| (is_symlink && entry_path.is_dir());

			// Resolve the entry file once. For a directory that is its
			// `.directory` and only when it exists: every directory used to
			// look like an entry, so a scan of the SD card read and parsed
			// the same missing file several times per folder.
			let entry_file = if is_dir {
				if directory_entry_allowed(&entry_path) {
					let candidate = entry_path.join(".directory");
					candidate.is_file().then_some(candidate)
				} else {
					None
				}
			} else {
				crate::config::entry_path(&entry_path)
			};
			let entry_data = entry_file
				.as_ref()
				.map(|entry_file| crate::desktop_entry::read(entry_file));
			// A desktop entry that asks not to be displayed is stashed like
			// a dotfile: hidden while the stash is on, shown when it is off.
			if !include_hidden && entry_data.as_ref().is_some_and(|entry| entry.no_display) {
				continue;
			}
			let is_entry = entry_data.is_some();
			let p = entry_path.to_string_lossy().to_string();
			// A descriptor can supply both the title and the secondary
			// comment for a file the directory cannot describe itself (a
			// ROM on a read-only card). It is a cached index lookup, and a
			// desktop entry never needs it.
			let descriptor = if entry_data.is_none() {
				crate::directory_descriptor::lookup(&entry_path)
			} else {
				None
			};
			let title = if let Some(name) = entry_data
				.as_ref()
				.and_then(|entry| entry.name.clone())
				.filter(|name| !name.is_empty())
			{
				name
			} else if is_dir {
				let app_name = crate::appimage::desktop_entry(&entry_path)
					.and_then(|entry| entry.name)
					.filter(|name| !name.is_empty());
				descriptor
					.as_ref()
					.and_then(|descriptor| descriptor.name.clone())
					.or(app_name)
					.unwrap_or_else(|| {
						entry_path
							.file_name()
							.map(|name| name.to_string_lossy().to_string())
							.unwrap_or_else(|| entry_path.to_string_lossy().to_string())
					})
			} else {
				descriptor
					.as_ref()
					.and_then(|descriptor| descriptor.name.clone())
					.unwrap_or_else(|| get_item_title(&entry_path))
			};
			let comment = entry_data
				.as_ref()
				.and_then(|entry| entry.comment.clone())
				.or_else(|| {
					descriptor
						.as_ref()
						.and_then(|descriptor| descriptor.comment.clone())
				})
				.unwrap_or_default();
			let icon = entry_data
				.as_ref()
				.and_then(|entry| entry.icon.clone())
				.filter(|icon| !icon.is_empty())
				.map(|icon| icon_source(icon, crate::config::base_dir(&entry_path)))
				.unwrap_or_else(|| {
					if is_dir {
						get_folder_icon(&p)
					} else {
						get_icon(&p)
					}
				});
			let control_kind = match entry_data
				.as_ref()
				.and_then(|entry| entry.entry_type.as_deref())
			{
				Some("Button") => 1,
				Some("Toggle") => 2,
				Some("Number") => 3,
				_ => 0,
			};
			let toggle_on = entry_data
				.as_ref()
				.and_then(|entry| entry.toggle)
				.unwrap_or(false);
			let number_value = entry_data
				.as_ref()
				.map(|entry| {
					entry
						.number
						.iter()
						.map(|field| field.value.to_string())
						.collect::<Vec<_>>()
						.join(" ")
				})
				.unwrap_or_default();

			let metadata = entry.metadata().ok();
			let (modified, created, accessed) = metadata
				.as_ref()
				.map(|meta| {
					(
						time_ms(meta.modified().ok()),
						time_ms(meta.created().ok()),
						time_ms(meta.accessed().ok()),
					)
				})
				.unwrap_or((0, 0, 0));
			let size = metadata.as_ref().map(|meta| meta.len()).unwrap_or(0);
			let is_stashed =
				is_dotfile || entry_data.as_ref().is_some_and(|entry| entry.no_display);
			let custom_group = entry_data
				.as_ref()
				.and_then(|entry| entry.group.clone())
				.unwrap_or_default();

			items.push(FileItem {
				name,
				title,
				comment,
				path: p,
				is_dir,
				is_symlink,
				is_dotfile,
				icon,
				is_entry,
				control_kind,
				toggle_on,
				number_value,
				size,
				modified,
				created,
				accessed,
				group: 0,
				group_label: String::new(),
				is_stashed,
				custom_group,
			});
		}
	}

	if crate::file_manager::perf_mode() > 0 {
		eprintln!(
			"hishell-perf: scan {} items from {} in {} ms",
			items.len(),
			path,
			scan_start.elapsed().as_millis()
		);
	}
	items
}
