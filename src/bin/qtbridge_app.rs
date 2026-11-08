//! A qtbridge frontend that mirrors the folder config and the directory model.

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::UNIX_EPOCH;

use hishell::{Config, ConfigKey, ConfigValue, Location};
use qtbridge::{
	QApp, QListModel, QListModelBase, QModelItem, QmlObject, include_bytes_qml, qobject,
};

#[derive(Default)]
pub struct ConfigBridge {
	title: String,
	icon: String,
	wallpaper: String,
	maximized: bool,
	top_layout: String,
	middle_layout: String,
	bottom_layout: String,
	header_layout: String,
	native_menubar: bool,
	native_menus: bool,
	native_titlebar: bool,
	native_drag: bool,
	show_shortcuts: bool,
	execution_wrapper: String,
	screen: String,
	grid_mode: String,
	grid_size: i32,
	lines: i32,
	grid_horizontal_align: String,
	grid_vertical_align: String,
	scroll_direction: String,
	view_mode: String,
	list_columns: String,
	list_header: bool,
	show_labels: bool,
	grid_labels_beside_icons: bool,
	label_text: String,
	sort: String,
	sort_date_mode: String,
	sort_alpha_mode: String,
	group: String,
	groups: String,
	show_stash: bool,
	stash_shown: bool,
	stash_dotfiles: bool,
	free_placement_positions: String,
	center_focus: bool,
	smooth_scrolling: bool,
	open_on_click: bool,
	focus_empty_slots: bool,
	radio_enabled: bool,
	radio_only: String,
	radio_selected: String,
	radio_exec: String,
	changed_revision: i32,
}

#[qobject]
impl ConfigBridge {
	qproperty!("title", Member = title, Notify = changed);
	qproperty!("icon", Member = icon, Notify = changed);
	qproperty!("wallpaper", Member = wallpaper, Notify = changed);
	qproperty!("maximized", Member = maximized, Notify = changed);
	qproperty!("top_layout", Member = top_layout, Notify = changed);
	qproperty!("middle_layout", Member = middle_layout, Notify = changed);
	qproperty!("bottom_layout", Member = bottom_layout, Notify = changed);
	qproperty!("header_layout", Member = header_layout, Notify = changed);
	qproperty!("native_menubar", Member = native_menubar, Notify = changed);
	qproperty!("native_menus", Member = native_menus, Notify = changed);
	qproperty!(
		"native_titlebar",
		Member = native_titlebar,
		Notify = changed
	);
	qproperty!("native_drag", Member = native_drag, Notify = changed);
	qproperty!("show_shortcuts", Member = show_shortcuts, Notify = changed);
	qproperty!(
		"executionWrapper",
		Member = execution_wrapper,
		Notify = changed
	);
	qproperty!("screen_name", Member = screen, Notify = changed);
	qproperty!("grid_mode", Member = grid_mode, Notify = changed);
	qproperty!("grid_size", Member = grid_size, Notify = changed);
	qproperty!("grid_lines", Member = lines, Notify = changed);
	qproperty!(
		"gridHorizontalAlign",
		Member = grid_horizontal_align,
		Notify = changed
	);
	qproperty!(
		"gridVerticalAlign",
		Member = grid_vertical_align,
		Notify = changed
	);
	qproperty!(
		"scrollHorizontal",
		Member = scroll_direction,
		Notify = changed
	);
	qproperty!("view_mode", Member = view_mode, Notify = changed);
	qproperty!("list_columns", Member = list_columns, Notify = changed);
	qproperty!("list_header", Member = list_header, Notify = changed);
	qproperty!("show_labels", Member = show_labels, Notify = changed);
	qproperty!(
		"gridLabelsBesidesIcons",
		Member = grid_labels_beside_icons,
		Notify = changed
	);
	qproperty!("label_text", Member = label_text, Notify = changed);
	qproperty!("sort", Member = sort, Notify = changed);
	qproperty!("sort_date_mode", Member = sort_date_mode, Notify = changed);
	qproperty!(
		"sort_alpha_mode",
		Member = sort_alpha_mode,
		Notify = changed
	);
	qproperty!("group_mode", Member = group, Notify = changed);
	qproperty!("groups", Member = groups, Notify = changed);
	qproperty!("show_stash", Member = show_stash, Notify = changed);
	qproperty!("stash_shown", Member = stash_shown, Notify = changed);
	qproperty!("stash_dotfiles", Member = stash_dotfiles, Notify = changed);
	qproperty!(
		"freePlacementPositions",
		Member = free_placement_positions,
		Notify = changed
	);
	qproperty!("center_focus", Member = center_focus, Notify = changed);
	qproperty!(
		"smoothScrolling",
		Member = smooth_scrolling,
		Notify = changed
	);
	qproperty!("open_on_click", Member = open_on_click, Notify = changed);
	qproperty!(
		"focusEmptySlots",
		Member = focus_empty_slots,
		Notify = changed
	);
	qproperty!("radio_enabled", Member = radio_enabled, Notify = changed);
	qproperty!("radio_only", Member = radio_only, Notify = changed);
	qproperty!("radio_selected", Member = radio_selected, Notify = changed);
	qproperty!("radio_exec", Member = radio_exec, Notify = changed);
	qproperty!(
		"changedRevision",
		Member = changed_revision,
		Notify = changed
	);

	#[qsignal]
	fn changed(&mut self);

	#[qslot]
	fn load(&mut self, folder: String) {
		let load = Config::load_for(&Location::folder(folder));
		self.apply(&load.config);
		self.changed_revision += 1;
		self.changed();
	}

	#[qslot]
	fn set_value(&mut self, key: String, value: String) -> bool {
		let Some(key) = key_from_qml(&key) else {
			return false;
		};
		match self.config_value(key, &value) {
			Ok(value) => match self.to_config().set(key, value) {
				Ok(delta) => {
					self.apply_value(key, &delta.new);
					self.changed_revision += 1;
					self.changed();
					true
				}
				Err(_) => false,
			},
			Err(_) => false,
		}
	}
}

impl ConfigBridge {
	fn apply(&mut self, config: &Config) {
		for key in ConfigKey::ALL {
			self.apply_value(*key, &config.get(*key));
		}
	}

	fn apply_value(&mut self, key: ConfigKey, value: &ConfigValue) {
		match (key, value) {
			(ConfigKey::Title, ConfigValue::Str(value)) => self.title = value.clone(),
			(ConfigKey::Icon, ConfigValue::Str(value)) => self.icon = value.clone(),
			(ConfigKey::Wallpaper, ConfigValue::Str(value)) => self.wallpaper = value.clone(),
			(ConfigKey::Maximized, ConfigValue::Bool(value)) => self.maximized = *value,
			(ConfigKey::Top, ConfigValue::Json(value)) => self.top_layout = value.clone(),
			(ConfigKey::Middle, ConfigValue::Json(value)) => self.middle_layout = value.clone(),
			(ConfigKey::Bottom, ConfigValue::Json(value)) => self.bottom_layout = value.clone(),
			(ConfigKey::Header, ConfigValue::Json(value)) => self.header_layout = value.clone(),
			(ConfigKey::NativeMenuBar, ConfigValue::Bool(value)) => self.native_menubar = *value,
			(ConfigKey::NativeMenus, ConfigValue::Bool(value)) => self.native_menus = *value,
			(ConfigKey::NativeTitleBar, ConfigValue::Bool(value)) => self.native_titlebar = *value,
			(ConfigKey::NativeDrag, ConfigValue::Bool(value)) => self.native_drag = *value,
			(ConfigKey::ShowShortcuts, ConfigValue::Bool(value)) => self.show_shortcuts = *value,
			(ConfigKey::ExecutionWrapper, ConfigValue::Str(value)) => {
				self.execution_wrapper = value.clone()
			}
			(ConfigKey::Screen, ConfigValue::Str(value)) => self.screen = value.clone(),
			(ConfigKey::GridMode, ConfigValue::Str(value)) => self.grid_mode = value.clone(),
			(ConfigKey::GridSize, ConfigValue::Int(value)) => self.grid_size = *value as i32,
			(ConfigKey::Lines, ConfigValue::Int(value)) => self.lines = *value as i32,
			(ConfigKey::GridHorizontalAlign, ConfigValue::Str(value)) => {
				self.grid_horizontal_align = value.clone()
			}
			(ConfigKey::GridVerticalAlign, ConfigValue::Str(value)) => {
				self.grid_vertical_align = value.clone()
			}
			(ConfigKey::ScrollDirection, ConfigValue::Str(value)) => {
				self.scroll_direction = value.clone()
			}
			(ConfigKey::ViewMode, ConfigValue::Str(value)) => self.view_mode = value.clone(),
			(ConfigKey::ListColumns, ConfigValue::Json(value)) => self.list_columns = value.clone(),
			(ConfigKey::ListHeader, ConfigValue::Bool(value)) => self.list_header = *value,
			(ConfigKey::ShowLabels, ConfigValue::Bool(value)) => self.show_labels = *value,
			(ConfigKey::GridLabelsBesidesIcons, ConfigValue::Bool(value)) => {
				self.grid_labels_beside_icons = *value
			}
			(ConfigKey::LabelText, ConfigValue::Str(value)) => self.label_text = value.clone(),
			(ConfigKey::Sort, ConfigValue::Str(value)) => self.sort = value.clone(),
			(ConfigKey::SortDateMode, ConfigValue::Str(value)) => {
				self.sort_date_mode = value.clone()
			}
			(ConfigKey::SortAlphaMode, ConfigValue::Str(value)) => {
				self.sort_alpha_mode = value.clone()
			}
			(ConfigKey::Group, ConfigValue::Str(value)) => self.group = value.clone(),
			(ConfigKey::Groups, ConfigValue::Json(value)) => self.groups = value.clone(),
			(ConfigKey::ShowStash, ConfigValue::Bool(value)) => self.show_stash = *value,
			(ConfigKey::StashShown, ConfigValue::Bool(value)) => self.stash_shown = *value,
			(ConfigKey::StashDotFiles, ConfigValue::Bool(value)) => self.stash_dotfiles = *value,
			(ConfigKey::FreePlacementPositions, ConfigValue::Json(value)) => {
				self.free_placement_positions = value.clone()
			}
			(ConfigKey::CenterFocus, ConfigValue::Bool(value)) => self.center_focus = *value,
			(ConfigKey::SmoothScrolling, ConfigValue::Bool(value)) => {
				self.smooth_scrolling = *value
			}
			(ConfigKey::OpenOnClick, ConfigValue::Bool(value)) => self.open_on_click = *value,
			(ConfigKey::FocusEmptySlots, ConfigValue::Bool(value)) => {
				self.focus_empty_slots = *value
			}
			(ConfigKey::RadioEnabled, ConfigValue::Bool(value)) => self.radio_enabled = *value,
			(ConfigKey::RadioOnly, ConfigValue::Str(value)) => self.radio_only = value.clone(),
			(ConfigKey::RadioSelected, ConfigValue::Str(value)) => {
				self.radio_selected = value.clone()
			}
			(ConfigKey::RadioExec, ConfigValue::Str(value)) => self.radio_exec = value.clone(),
			_ => {}
		}
	}

	fn to_config(&self) -> Config {
		let mut config = Config::default();
		for key in ConfigKey::ALL {
			let value = match key.default() {
				ConfigValue::Bool(_) => ConfigValue::Bool(self.bool_value(*key)),
				ConfigValue::Int(_) => ConfigValue::Int(self.int_value(*key) as i64),
				ConfigValue::Str(_) => ConfigValue::Str(self.string_value(*key)),
				ConfigValue::Json(_) => ConfigValue::Json(self.string_value(*key)),
			};
			let _ = config.set(*key, value);
		}
		config
	}

	fn config_value(&self, key: ConfigKey, value: &str) -> Result<ConfigValue, ()> {
		match key.default() {
			ConfigValue::Bool(_) => match value {
				"true" | "1" => Ok(ConfigValue::Bool(true)),
				"false" | "0" => Ok(ConfigValue::Bool(false)),
				_ => Err(()),
			},
			ConfigValue::Int(_) => value.parse().map(ConfigValue::Int).map_err(|_| ()),
			ConfigValue::Str(_) => Ok(ConfigValue::Str(value.to_string())),
			ConfigValue::Json(_) => Ok(ConfigValue::Json(value.to_string())),
		}
	}

	fn string_value(&self, key: ConfigKey) -> String {
		match key {
			ConfigKey::Title => self.title.clone(),
			ConfigKey::Icon => self.icon.clone(),
			ConfigKey::Wallpaper => self.wallpaper.clone(),
			ConfigKey::Top => self.top_layout.clone(),
			ConfigKey::Middle => self.middle_layout.clone(),
			ConfigKey::Bottom => self.bottom_layout.clone(),
			ConfigKey::Header => self.header_layout.clone(),
			ConfigKey::ExecutionWrapper => self.execution_wrapper.clone(),
			ConfigKey::Screen => self.screen.clone(),
			ConfigKey::GridMode => self.grid_mode.clone(),
			ConfigKey::GridHorizontalAlign => self.grid_horizontal_align.clone(),
			ConfigKey::GridVerticalAlign => self.grid_vertical_align.clone(),
			ConfigKey::ScrollDirection => self.scroll_direction.clone(),
			ConfigKey::ViewMode => self.view_mode.clone(),
			ConfigKey::ListColumns => self.list_columns.clone(),
			ConfigKey::LabelText => self.label_text.clone(),
			ConfigKey::Sort => self.sort.clone(),
			ConfigKey::SortDateMode => self.sort_date_mode.clone(),
			ConfigKey::SortAlphaMode => self.sort_alpha_mode.clone(),
			ConfigKey::Group => self.group.clone(),
			ConfigKey::Groups => self.groups.clone(),
			ConfigKey::FreePlacementPositions => self.free_placement_positions.clone(),
			ConfigKey::RadioOnly => self.radio_only.clone(),
			ConfigKey::RadioSelected => self.radio_selected.clone(),
			ConfigKey::RadioExec => self.radio_exec.clone(),
			_ => String::new(),
		}
	}

	fn int_value(&self, key: ConfigKey) -> i64 {
		match key {
			ConfigKey::GridSize => self.grid_size as i64,
			ConfigKey::Lines => self.lines as i64,
			_ => 0,
		}
	}

	fn bool_value(&self, key: ConfigKey) -> bool {
		match key {
			ConfigKey::Maximized => self.maximized,
			ConfigKey::NativeMenuBar => self.native_menubar,
			ConfigKey::NativeMenus => self.native_menus,
			ConfigKey::NativeTitleBar => self.native_titlebar,
			ConfigKey::NativeDrag => self.native_drag,
			ConfigKey::ShowShortcuts => self.show_shortcuts,
			ConfigKey::ListHeader => self.list_header,
			ConfigKey::ShowLabels => self.show_labels,
			ConfigKey::GridLabelsBesidesIcons => self.grid_labels_beside_icons,
			ConfigKey::ShowStash => self.show_stash,
			ConfigKey::StashShown => self.stash_shown,
			ConfigKey::StashDotFiles => self.stash_dotfiles,
			ConfigKey::CenterFocus => self.center_focus,
			ConfigKey::SmoothScrolling => self.smooth_scrolling,
			ConfigKey::OpenOnClick => self.open_on_click,
			ConfigKey::FocusEmptySlots => self.focus_empty_slots,
			ConfigKey::RadioEnabled => self.radio_enabled,
			_ => false,
		}
	}
}

fn key_from_qml(name: &str) -> Option<ConfigKey> {
	match name {
		"grid_mode" => Some(ConfigKey::GridMode),
		"grid_size" => Some(ConfigKey::GridSize),
		"grid_lines" => Some(ConfigKey::Lines),
		"view_mode" => Some(ConfigKey::ViewMode),
		"show_labels" => Some(ConfigKey::ShowLabels),
		"grid_labels_beside_icons" => Some(ConfigKey::GridLabelsBesidesIcons),
		"label_text" => Some(ConfigKey::LabelText),
		"sort" => Some(ConfigKey::Sort),
		"group_mode" => Some(ConfigKey::Group),
		"show_stash" => Some(ConfigKey::ShowStash),
		"center_focus" => Some(ConfigKey::CenterFocus),
		"smooth_scrolling" => Some(ConfigKey::SmoothScrolling),
		"open_on_click" => Some(ConfigKey::OpenOnClick),
		_ => None,
	}
}

#[derive(Default)]
pub struct PathBridge {}

#[qobject]
impl PathBridge {
	#[qslot]
	fn get_segments(&self, path: String) -> String {
		hishell::path::segments(&path)
	}

	#[qslot]
	fn path_for_index(&self, current_path: String, idx: i32) -> String {
		hishell::path::path_for_index(&current_path, idx)
	}

	#[qslot]
	fn folder_name(&self, path: String) -> String {
		hishell::path::folder_name(&path)
	}

	#[qslot]
	fn normalize_path(&self, path: String) -> String {
		hishell::path::normalize(&path)
	}

	#[qslot]
	fn navigation_plan(&self, from: String, to: String) -> String {
		hishell::path::navigation_plan(&from, &to)
	}

	#[qslot]
	fn parent_path(&self, path: String) -> String {
		hishell::path::parent(&path)
	}

	#[qslot]
	fn path_exists(&self, base: String, text: String) -> bool {
		hishell::path::exists(&base, &text)
	}

	#[qslot]
	fn resolve_path(&self, base: String, spec: String) -> String {
		hishell::path::resolve(&base, &spec)
	}

	#[qslot]
	fn complete_path(&self, base: String, text: String, limit: i32) -> String {
		hishell::path::complete(&base, &text, limit)
	}
}

#[derive(Default, Clone, QModelItem)]
#[allow(non_snake_case)]
pub struct DirectoryRow {
	name: String,
	path: String,
	is_directory: bool,
	icon: String,
	title: String,
	is_symlink: bool,
	size_bytes: i64,
	modified_time: i64,
	created_time: i64,
	accessed_time: i64,
	control_kind: i32,
	toggle_on: bool,
	number_value: String,
	comment: String,
	icon_ready: bool,
}

#[derive(Default)]
pub struct Directory {
	rows: Vec<DirectoryRow>,
	path: String,
	config: Rc<RefCell<ConfigBridge>>,
	revision: i32,
}

impl Directory {
	pub fn new(path: &Path) -> Self {
		let mut directory = Self {
			rows: Vec::new(),
			path: path.to_string_lossy().into_owned(),
			config: Rc::new(RefCell::new(ConfigBridge::default())),
			revision: 0,
		};
		directory.reload();
		directory
	}

	fn reload(&mut self) {
		self.rows = scan(Path::new(&self.path));
		self.config.borrow_mut().load(self.path.clone());
		self.revision += 1;
	}
}

#[qobject(Base = QListModel)]
impl Directory {
	qproperty!("config", Member = config);
	qproperty!("path", Member = path, Notify = path_changed);
	qproperty!("revision", Member = revision, Notify = revision_changed);

	#[qsignal]
	fn path_changed(&mut self);

	#[qsignal]
	fn revision_changed(&mut self);

	#[qslot]
	fn refresh(&mut self) {
		self.reload();
		self.reset();
		self.revision += 1;
		self.revision_changed();
	}

	#[qslot]
	fn refresh_async(&self) {
		let path = PathBuf::from(&self.path);
		let handle = self.get_thread_handle();
		std::thread::spawn(move || {
			let rows = scan(&path);
			handle.invoke_mut(move |directory: &mut Directory| {
				directory.rows = rows;
				directory.reset();
				directory.revision += 1;
				directory.revision_changed();
			});
		});
	}
}

impl QListModel for Directory {
	type Item = DirectoryRow;

	fn len(&self) -> usize {
		self.rows.len()
	}

	fn get(&self, index: usize) -> Option<&DirectoryRow> {
		self.rows.get(index)
	}

	fn push_unnotified(&mut self, value: DirectoryRow) {
		self.rows.push(value);
	}

	fn reset_unnotified(&mut self) {}
}

fn scan(path: &Path) -> Vec<DirectoryRow> {
	let Ok(entries) = std::fs::read_dir(path) else {
		return Vec::new();
	};
	let mut rows: Vec<DirectoryRow> = entries
		.flatten()
		.map(|entry| {
			let path = entry.path();
			let metadata = entry.metadata().ok();
			let is_directory = metadata
				.as_ref()
				.map(|metadata| metadata.is_dir())
				.unwrap_or(false);
			DirectoryRow {
				name: entry.file_name().to_string_lossy().into_owned(),
				path: path.to_string_lossy().into_owned(),
				is_directory,
				icon: if is_directory {
					String::from("folder")
				} else {
					String::from("text-x-generic")
				},
				title: entry.file_name().to_string_lossy().into_owned(),
				is_symlink: entry
					.file_type()
					.map(|kind| kind.is_symlink())
					.unwrap_or(false),
				size_bytes: metadata
					.as_ref()
					.map(|metadata| metadata.len() as i64)
					.unwrap_or(0),
				modified_time: metadata
					.as_ref()
					.and_then(|metadata| metadata.modified().ok())
					.and_then(|time| time.duration_since(UNIX_EPOCH).ok())
					.map(|duration| duration.as_millis() as i64)
					.unwrap_or(0),
				created_time: 0,
				accessed_time: 0,
				control_kind: 0,
				toggle_on: false,
				number_value: String::new(),
				comment: String::new(),
				icon_ready: true,
			}
		})
		.collect();
	rows.sort_by(|left, right| {
		right
			.is_directory
			.cmp(&left.is_directory)
			.then_with(|| left.name.to_lowercase().cmp(&right.name.to_lowercase()))
	});
	rows
}

fn main() {
	let path = std::env::args().nth(1).unwrap_or_else(|| String::from("."));
	let mut app = QApp::new();
	app.application_name("hishell-qt-bridge")
		.register::<ConfigBridge>()
		.register::<Directory>()
		.register::<PathBridge>()
		.set_initial_object(
			"directory",
			Rc::new(RefCell::new(Directory::new(Path::new(&path)))),
		);

	include_bytes_qml!("qml", "hishell_qt");
	app.load_qml_from_file("qrc:/hishell_qt/qml/Main.qml").run();
}
