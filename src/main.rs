//! A qtbridge frontend that mirrors the folder config and the directory model.

#[cfg(feature = "gamepad")]
mod gamepad;

use std::cell::RefCell;
use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::sync::Mutex;

use hishell::platform::{AppCatalog, FreeDesktopApps};
use hishell::{
	ActionId, ActionRequest, AppId, ChangeSet, Command, Config, ConfigKey, ConfigValue,
	CopyOptions, Direction, Effect, Engine, FocusCommand, FolderDelta, FolderMode, LaunchRequest,
	Location, MenuKind, Metrics, NavigationPlan, NavigationRequest, Op, Overwrite, PaneId, Prompt, Target,
	ViewRequest, ViewSpec, Viewport,
};
use qtbridge::{
	QApp, QListModel, QListModelBase, QModelItem, QmlObject, include_bytes_qml, qobject,
};

unsafe extern "C" {
	fn hishell_register_drag_helper();
}

static CLIPBOARD: once_cell::sync::Lazy<Mutex<Option<hishell::ops::ClipboardSnapshot>>> =
	once_cell::sync::Lazy::new(|| Mutex::new(None));

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
	native_drag: bool,
	native_titlebar: bool,
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
	qproperty!("native_drag", Member = native_drag, Notify = changed);
	qproperty!(
		"native_titlebar",
		Member = native_titlebar,
		Notify = changed
	);
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
	fn notify(&mut self) {
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
			(ConfigKey::NativeDrag, ConfigValue::Bool(value)) => self.native_drag = *value,
			(ConfigKey::NativeTitleBar, ConfigValue::Bool(value)) => self.native_titlebar = *value,
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
			ConfigKey::NativeDrag => self.native_drag,
			ConfigKey::NativeTitleBar => self.native_titlebar,
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

fn qml_config_value(key: ConfigKey, value: &str) -> Option<ConfigValue> {
	match key.default() {
		ConfigValue::Bool(_) => match value {
			"true" | "1" => Some(ConfigValue::Bool(true)),
			"false" | "0" => Some(ConfigValue::Bool(false)),
			_ => None,
		},
		ConfigValue::Int(_) => value.parse().ok().map(ConfigValue::Int),
		ConfigValue::Str(_) => Some(ConfigValue::Str(value.to_string())),
		ConfigValue::Json(_) => Some(ConfigValue::Json(value.to_string())),
	}
}

/// Actions the thin frontend has a UI for. Core may recommend more; the
/// frontend decides what to render, so prompts and clipboard actions wait for
/// their dialogs.
fn supported_action(id: &str) -> bool {
	matches!(
		id,
		"open"
			| "open-with"
			| "navigate"
			| "go-up" | "refresh"
			| "select-all"
			| "new-folder"
			| "new-text-file"
			| "copy" | "cut" | "paste"
			| "properties"
			| "duplicate"
			| "create-link"
			| "rename"
			| "trash" | "destroy"
			| "toggle"
			| "rotate-image"
	)
}

fn transition_json(plan: &NavigationPlan) -> String {
	serde_json::json!({
		"from": plan.from.to_string_lossy(),
		"to": plan.to.to_string_lossy(),
		"relation": serde_json::to_value(&plan.relation).unwrap_or(serde_json::Value::Null),
		"animated": plan.animated,
		"close": plan.close.len(),
		"open": plan.open.len(),
	})
	.to_string()
}

fn parse_uris(text: &str) -> Vec<PathBuf> {
	text.lines()
		.map(str::trim)
		.filter(|line| !line.is_empty() && !line.starts_with('#'))
		.map(|line| {
			if let Some(rest) = line.strip_prefix("file://") {
				PathBuf::from(percent_decode(rest))
			} else {
				PathBuf::from(line)
			}
		})
		.collect()
}

fn direction_from(name: &str) -> Option<Direction> {
	match name {
		"left" => Some(Direction::Left),
		"right" => Some(Direction::Right),
		"up" => Some(Direction::Up),
		"down" => Some(Direction::Down),
		_ => None,
	}
}

fn menu_kind(name: &str) -> Option<MenuKind> {
	match name {
		"main" => Some(MenuKind::Main),
		"context" => Some(MenuKind::Context),
		"edit" => Some(MenuKind::Edit),
		"new" => Some(MenuKind::New),
		"folder" => Some(MenuKind::FolderMenu),
		"view" => Some(MenuKind::View),
		"selection" => Some(MenuKind::SelectionBar),
		_ => None,
	}
}

fn target_kind(name: &str) -> Option<Target> {
	match name {
		"location" => Some(Target::Location),
		"focus" => Some(Target::Focus),
		"selection" => Some(Target::Selection),
		"auto" => Some(Target::Auto),
		_ => None,
	}
}

fn key_from_qml(name: &str) -> Option<ConfigKey> {
	// Menus use the config file's own key names (GridMode, ShowLabels, …).
	if let Some(key) = ConfigKey::ALL.iter().find(|key| key.name() == name) {
		return Some(*key);
	}
	match name {
		"title" => Some(ConfigKey::Title),
		"icon" => Some(ConfigKey::Icon),
		"wallpaper" => Some(ConfigKey::Wallpaper),
		"maximized" => Some(ConfigKey::Maximized),
		"top_layout" | "top" => Some(ConfigKey::Top),
		"middle_layout" | "middle" => Some(ConfigKey::Middle),
		"bottom_layout" | "bottom" => Some(ConfigKey::Bottom),
		"header_layout" | "header" => Some(ConfigKey::Header),
		"native_menubar" => Some(ConfigKey::NativeMenuBar),
		"native_menus" => Some(ConfigKey::NativeMenus),
		"native_drag" | "nativeDrag" => Some(ConfigKey::NativeDrag),
		"native_titlebar" => Some(ConfigKey::NativeTitleBar),
		"show_shortcuts" => Some(ConfigKey::ShowShortcuts),
		"execution_wrapper" | "executionWrapper" => Some(ConfigKey::ExecutionWrapper),
		"screen_name" | "screen" => Some(ConfigKey::Screen),
		"grid_mode" => Some(ConfigKey::GridMode),
		"grid_size" => Some(ConfigKey::GridSize),
		"grid_lines" | "gridLines" => Some(ConfigKey::Lines),
		"grid_horizontal_align" | "gridHorizontalAlign" => Some(ConfigKey::GridHorizontalAlign),
		"grid_vertical_align" | "gridVerticalAlign" => Some(ConfigKey::GridVerticalAlign),
		"scroll_direction" | "scrollHorizontal" => Some(ConfigKey::ScrollDirection),
		"view_mode" => Some(ConfigKey::ViewMode),
		"list_columns" | "listColumns" => Some(ConfigKey::ListColumns),
		"list_header" => Some(ConfigKey::ListHeader),
		"show_labels" => Some(ConfigKey::ShowLabels),
		"grid_labels_beside_icons" | "gridLabelsBesidesIcons" => {
			Some(ConfigKey::GridLabelsBesidesIcons)
		}
		"label_text" => Some(ConfigKey::LabelText),
		"sort" => Some(ConfigKey::Sort),
		"sort_date_mode" | "sortDateMode" => Some(ConfigKey::SortDateMode),
		"sort_alpha_mode" | "sortAlphaMode" => Some(ConfigKey::SortAlphaMode),
		"group_mode" | "group" => Some(ConfigKey::Group),
		"groups" => Some(ConfigKey::Groups),
		"show_stash" => Some(ConfigKey::ShowStash),
		"stash_shown" => Some(ConfigKey::StashShown),
		"stash_dotfiles" | "stashDotFiles" => Some(ConfigKey::StashDotFiles),
		"free_placement_positions" | "freePlacementPositions" => {
			Some(ConfigKey::FreePlacementPositions)
		}
		"center_focus" => Some(ConfigKey::CenterFocus),
		"smooth_scrolling" | "smoothScrolling" => Some(ConfigKey::SmoothScrolling),
		"open_on_click" => Some(ConfigKey::OpenOnClick),
		"focus_empty_slots" | "focusEmptySlots" => Some(ConfigKey::FocusEmptySlots),
		"radio_enabled" => Some(ConfigKey::RadioEnabled),
		"radio_only" => Some(ConfigKey::RadioOnly),
		"radio_selected" => Some(ConfigKey::RadioSelected),
		"radio_exec" => Some(ConfigKey::RadioExec),
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
	fn folder_icon(&self, path: String) -> String {
		let path = Path::new(&path);
		let icon = if path.is_dir() {
			hishell::IconRef::Theme(String::from("folder"))
		} else {
			hishell::icon::for_path(path)
		};
		match icon {
			hishell::IconRef::Theme(name) => name,
			hishell::IconRef::Path(path) => format!("file://{}", path.to_string_lossy()),
		}
	}

	#[qslot]
	fn folder_title(&self, path: String) -> String {
		let title = Config::load_for(&Location::folder(&path)).config.title;
		if title.is_empty() {
			hishell::path::folder_name(&path)
		} else {
			title
		}
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
	size_bytes: i64,
	modified_time: i64,
	created_time: i64,
	accessed_time: i64,
	mime: String,
	group_label: String,
	is_image: bool,
	is_symlink: bool,
	/// 1 button, 2 toggle off, 3 toggle on, 4 number.
	control_kind: i32,
	number_value: String,
}

pub struct Directory {
	rows: Vec<DirectoryRow>,
	path: String,
	config: Rc<RefCell<ConfigBridge>>,
	engine: Option<Engine>,
	revision: i32,
	selection_active: bool,
	selected_count: i32,
	selection_revision: i32,
	active_items: Vec<String>,
	active_revision: i32,
	filter: String,
	match_count: i32,
	visible_count: i32,
	unfiltered_rows: Vec<DirectoryRow>,
	focused_path: String,
	focus_is_image: bool,
	focus_is_directory: bool,
	last_descriptor_epoch: u64,
	has_meta: bool,
}

impl Directory {
	pub fn new(path: &Path) -> Self {
		let mut directory = Self {
			rows: Vec::new(),
			path: path.to_string_lossy().into_owned(),
			config: Rc::new(RefCell::new(ConfigBridge::default())),
			engine: Engine::open(path).ok(),
			revision: 0,
			selection_active: false,
			selected_count: 0,
			selection_revision: 0,
			active_items: Vec::new(),
			active_revision: 0,
			filter: String::new(),
			match_count: 0,
			visible_count: 0,
			unfiltered_rows: Vec::new(),
			focused_path: String::new(),
			focus_is_image: false,
			focus_is_directory: false,
			last_descriptor_epoch: 0,
			has_meta: path.join(".directory").is_file() || path.join(".cfg").is_file(),
		};
		directory.reload();
		save_session(&directory.path);
		directory
	}

	fn reload(&mut self) {
		let Some(engine) = self.engine.as_mut() else {
			return;
		};
		let outcome = engine.dispatch(Command::Reload).ok();
		self.config.borrow_mut().apply(engine.config());
		let rows = rows_after(engine, outcome.as_ref().map(|outcome| &outcome.changes));
		self.set_rows(rows);
	}

	fn refresh_now(&mut self) {
		if let Some(engine) = self.engine.as_mut() {
			let _ = engine.tick();
		}
		self.reload();
		self.reset();
		self.read_selection();
		self.read_focus();
		self.revision += 1;
		self.revision_changed();
		self.selection_changed();
	}

	fn read_focus(&mut self) {
		let (path, is_image, is_directory) = self
			.engine
			.as_ref()
			.and_then(|engine| {
				engine.focus().and_then(|id| engine.item(id)).map(|item| {
					(
						item.path.to_string_lossy().into_owned(),
						item.mime.as_deref().is_some_and(|mime| mime.starts_with("image/")),
						item.fs_kind == hishell::FsKind::Directory,
					)
				})
			})
			.unwrap_or_default();
		if self.focused_path != path {
			self.focused_path = path;
			self.focus_is_image = is_image;
			self.focus_is_directory = is_directory;
			self.focus_changed();
		}
	}

	fn navigate_command(&mut self, command: Command) -> bool {
		let plan_json = match self.engine.as_mut() {
			Some(engine) => match engine.dispatch(command) {
				Ok(outcome) => outcome.effects.iter().find_map(|effect| match effect {
					Effect::Navigate(plan) => Some(transition_json(plan)),
					_ => None,
				}),
				Err(_) => return false,
			},
			None => return false,
		};
		self.after_engine_change();
		if let Some(plan_json) = plan_json {
			self.transition_requested(plan_json);
		}
		true
	}

	fn after_engine_change(&mut self) {
		let Some(engine) = self.engine.as_ref() else {
			return;
		};
		self.path = engine.location().path().to_string_lossy().into_owned();
		self.has_meta = Path::new(&self.path).join(".directory").is_file()
			|| Path::new(&self.path).join(".cfg").is_file();
		save_session(&self.path);
		self.config.borrow_mut().apply(engine.config());
		self.filter.clear();
		self.set_rows(rows_after(engine, None));
		self.filter_changed();
		self.read_selection();
		self.read_focus();
		self.reset();
		self.revision += 1;
		self.path_changed();
		self.revision_changed();
		self.selection_changed();
	}

	fn set_rows(&mut self, rows: Vec<DirectoryRow>) {
		self.unfiltered_rows = rows;
		self.apply_filter();
	}

	fn apply_filter(&mut self) {
		let needle = self.filter.to_lowercase();
		self.rows = if needle.is_empty() {
			self.unfiltered_rows.clone()
		} else {
			self.unfiltered_rows
				.iter()
				.filter(|row| {
					row.name.to_lowercase().contains(&needle)
						|| row.title.to_lowercase().contains(&needle)
				})
				.cloned()
				.collect()
		};
		self.match_count = self.rows.len() as i32;
		self.visible_count = self.rows.len() as i32;
	}

	fn focus_first_match(&mut self) {
		if self.rows.iter().any(|row| row.path == self.focused_path) {
			return;
		}
		if let Some(path) = self.rows.first().map(|row| row.path.clone()) {
			self.focus_path(path);
		}
	}

	fn read_selection(&mut self) {
		if let Some(engine) = &self.engine {
			let selection = engine.selection();
			self.selection_active = selection
				.map(|selection| selection.active())
				.unwrap_or(false);
			self.selected_count = selection
				.map(|selection| selection.count() as i32)
				.unwrap_or(0);
		}
	}

	fn target_paths(&self) -> Vec<PathBuf> {
		let Some(engine) = &self.engine else {
			return Vec::new();
		};
		if let Some(selection) = engine.selection()
			&& selection.active()
			&& !selection.is_empty()
		{
			return selection
				.items()
				.iter()
				.filter_map(|id| engine.item(*id))
				.map(|item| item.path.clone())
				.collect();
		}
		engine
			.focus()
			.and_then(|id| engine.item(id))
			.map(|item| item.path.clone())
			.into_iter()
			.collect()
	}

	fn schedule_refresh(&self, millis: u64) {
		let handle = self.get_thread_handle();
		std::thread::spawn(move || {
			std::thread::sleep(std::time::Duration::from_millis(millis));
			handle.invoke_mut(|directory: &mut Directory| directory.refresh_now());
		});
	}

	fn run_op(&mut self, op: Op) -> bool {
		let job = match self.engine.as_mut() {
			Some(engine) => match engine.dispatch(Command::Run(op)) {
				Ok(outcome) => outcome.job.is_some(),
				Err(_) => return false,
			},
			None => return false,
		};
		self.after_engine_change();
		if job {
			self.schedule_refresh(400);
		}
		true
	}

	fn selection_id(&self, path: &str) -> Option<hishell::ItemId> {
		let engine = self.engine.as_ref()?;
		engine.item_at(Path::new(path)).map(|item| item.id)
	}

	fn apply_selection(&mut self, command: Command) {
		if let Some(engine) = self.engine.as_mut() {
			let _ = engine.dispatch(command);
		}
		self.read_selection();
		self.selection_revision += 1;
		self.selection_changed();
	}
}

impl Default for Directory {
	fn default() -> Self {
		Self::new(Path::new("."))
	}
}

#[qobject(Base = QListModel)]
impl Directory {
	qproperty!("config", Member = config);
	qproperty!("path", Member = path, Notify = path_changed);
	qproperty!("revision", Member = revision, Notify = revision_changed);
	qproperty!(
		"selectionActive",
		Member = selection_active,
		Notify = selection_changed
	);
	qproperty!(
		"selectedCount",
		Member = selected_count,
		Notify = selection_changed
	);
	qproperty!(
		"selectionRevision",
		Member = selection_revision,
		Notify = selection_changed
	);
	qproperty!(
		"activeRevision",
		Member = active_revision,
		Notify = active_changed
	);
	qproperty!("filter", Member = filter, Notify = filter_changed);
	qproperty!(
		"matchCount",
		Member = match_count,
		Notify = filter_changed
	);
	qproperty!("itemCount", Member = visible_count, Notify = filter_changed);
	qproperty!(
		"focusIsImage",
		Member = focus_is_image,
		Notify = focus_changed
	);
	qproperty!(
		"focusIsDirectory",
		Member = focus_is_directory,
		Notify = focus_changed
	);
	qproperty!(
		"focused_path",
		Member = focused_path,
		Notify = focus_changed
	);

	#[qsignal]
	fn path_changed(&mut self);

	#[qsignal]
	fn focus_changed(&mut self);

	#[qsignal]
	fn filter_changed(&mut self);

	#[qsignal]
	fn properties_requested(&mut self, path: String);

	#[qsignal]
	fn rename_requested(&mut self, path: String, suggested: String);

	#[qsignal]
	fn trash_requested(&mut self, paths_json: String, permanent: bool);

	#[qsignal]
	fn open_with_requested(&mut self, path: String);

	#[qsignal]
	fn transition_requested(&mut self, plan_json: String);

	#[qsignal]
	fn revision_changed(&mut self);

	#[qsignal]
	fn selection_changed(&mut self);
	#[qsignal]
	fn active_changed(&mut self);

	#[qslot]
	fn is_selected(&self, path: String) -> bool {
		let Some(engine) = &self.engine else {
			return false;
		};
		let Some(item) = engine.item_at(Path::new(&path)) else {
			return false;
		};
		engine
			.selection()
			.map(|selection| selection.contains(item.id))
			.unwrap_or(false)
	}

	#[qslot]
	fn selected_paths_json(&self) -> String {
		let Some(engine) = &self.engine else {
			return String::from("[]");
		};
		let paths: Vec<String> = engine
			.selection()
			.filter(|selection| selection.active())
			.map(|selection| {
				selection
					.items()
					.iter()
					.filter_map(|id| engine.item(*id))
					.map(|item| item.path.to_string_lossy().into_owned())
					.collect()
			})
			.unwrap_or_default();
		serde_json::to_string(&paths).unwrap_or_else(|_| String::from("[]"))
	}

	#[qslot]
	fn radio_value(&self, path: String) -> String {
		hishell::folder::radio_value(Path::new(&path))
	}

	#[qslot]
	fn home_directory(&self) -> String {
		std::env::var("HOME").unwrap_or_default()
	}

	#[qslot]
	fn select(&mut self, path: String) {
		if let Some(id) = self.selection_id(&path) {
			self.apply_selection(Command::SelectOnly(id));
		}
	}

	#[qslot]
	fn select_range(&mut self, path: String) {
		if let Some(id) = self.selection_id(&path) {
			self.apply_selection(Command::SelectRange(id));
		}
	}

	#[qslot]
	fn toggle_select(&mut self, path: String) {
		if let Some(id) = self.selection_id(&path) {
			self.apply_selection(Command::ToggleSelection(id));
		}
	}

	#[qslot]
	fn has_meta(&self) -> bool {
		self.has_meta
	}

	#[qslot]
	fn set_config(&mut self, key: String, value: String) -> bool {
		let local = self.has_meta;
		self.set_config_scoped(key, value, local)
	}

	#[qslot]
	fn set_config_scoped(&mut self, key: String, value: String, local: bool) -> bool {
		let Some(key) = key_from_qml(&key) else {
			return false;
		};
		let Some(value) = qml_config_value(key, &value) else {
			return false;
		};
		let raw = match &value {
			ConfigValue::Bool(value) => value.to_string(),
			ConfigValue::Int(value) => value.to_string(),
			ConfigValue::Str(value) => value.clone(),
			ConfigValue::Json(value) => value.clone(),
		};
		let Some(engine) = self.engine.as_mut() else {
			return false;
		};
		let outcome = match engine.dispatch(Command::SetConfigRaw {
			section: key.section().to_string(),
			key: key.name().to_string(),
			value: raw,
			local,
		}) {
			Ok(outcome) => outcome,
			Err(_) => return false,
		};
		self.config.borrow_mut().apply(engine.config());
		let rows = rows_after(engine, Some(&outcome.changes));
		self.set_rows(rows);
		self.read_selection();
		self.reset();
		self.revision += 1;
		self.revision_changed();
		true
	}

	#[qslot]
	fn append_filter(&mut self, text: String) {
		if text.is_empty() {
			return;
		}
		self.filter.push_str(&text);
		self.apply_filter();
		self.reset();
		self.focus_first_match();
		self.filter_changed();
	}

	#[qslot]
	fn backspace_filter(&mut self) {
		if self.filter.pop().is_some() {
			self.apply_filter();
			self.reset();
			self.focus_first_match();
			self.filter_changed();
		}
	}

	#[qslot]
	fn clear_filter(&mut self) {
		if self.filter.is_empty() {
			return;
		}
		self.filter.clear();
		self.apply_filter();
		self.reset();
		self.filter_changed();
	}

	#[qslot]
	fn copy_selection(&mut self) -> bool {
		let paths = self.target_paths();
		if paths.is_empty() {
			return false;
		}
		*CLIPBOARD.lock().unwrap() = Some(hishell::ops::ClipboardSnapshot {
			paths,
			cut: false,
		});
		true
	}

	#[qslot]
	fn cut_selection(&mut self) -> bool {
		let paths = self.target_paths();
		if paths.is_empty() {
			return false;
		}
		*CLIPBOARD.lock().unwrap() = Some(hishell::ops::ClipboardSnapshot {
			paths,
			cut: true,
		});
		true
	}

	#[qslot]
	fn paste(&mut self) -> bool {
		let Some(snapshot) = CLIPBOARD.lock().unwrap().clone() else {
			return false;
		};
		let Some(engine) = self.engine.as_mut() else {
			return false;
		};
		let op = Op::Paste {
			snapshot: snapshot.clone(),
			dest: PathBuf::from(&self.path),
			options: hishell::ops::PasteOptions {
				cut: snapshot.cut,
				overwrite: Overwrite::Never,
			},
		};
		let Ok(outcome) = engine.dispatch(Command::Run(op)) else {
			return false;
		};
		if snapshot.cut {
			*CLIPBOARD.lock().unwrap() = None;
		}
		let job = outcome.job.is_some();
		let rows = rows_after(engine, Some(&outcome.changes));
		self.set_rows(rows);
		self.read_selection();
		self.read_focus();
		self.reset();
		self.revision += 1;
		self.revision_changed();
		if job {
			self.schedule_refresh(250);
		}
		true
	}

	#[qslot]
	fn properties_json(&self, path: String) -> String {
		let path = PathBuf::from(path);
		let metadata = std::fs::metadata(&path).ok();
		let kind = if path.is_dir() { "Folder" } else { "File" };
		serde_json::json!({
			"name": path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default(),
			"path": path.to_string_lossy(),
			"type": kind,
			"size": metadata.as_ref().map(|meta| meta.len() as i64).unwrap_or(0),
			"modified": metadata.as_ref().and_then(|meta| meta.modified().ok())
				.and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
				.map(|duration| duration.as_millis() as i64).unwrap_or(0),
			"mime": hishell::icon::mime_for_path(&path).unwrap_or_default(),
		})
		.to_string()
	}

	#[qslot]
	fn open_in_new_window(&self, path: String) -> bool {
		let path = PathBuf::from(path);
		let target = if path.is_dir() { path } else {
			path.parent().map(Path::to_path_buf).unwrap_or(path)
		};
		let Ok(executable) = std::env::current_exe() else {
			return false;
		};
		std::process::Command::new(executable).arg(target).spawn().is_ok()
	}

	#[qslot]
	fn set_free_position(&mut self, name: String, column: i32, row: i32) -> bool {
		let Some(engine) = self.engine.as_mut() else {
			return false;
		};
		let Ok(outcome) = engine.dispatch(Command::SetFreePosition { name, column, row })
		else {
			return false;
		};
		self.config.borrow_mut().apply(engine.config());
		let rows = rows_after(engine, Some(&outcome.changes));
		self.set_rows(rows);
		self.read_selection();
		self.read_focus();
		self.reset();
		self.revision += 1;
		self.revision_changed();
		true
	}

	#[qslot]
	fn set_free_positions(&mut self, json: String) -> bool {
		let Ok(map) =
			serde_json::from_str::<serde_json::Map<String, serde_json::Value>>(&json)
		else {
			return false;
		};
		let positions: Vec<(String, i32, i32)> = map
			.into_iter()
			.filter_map(|(name, value)| {
				let values = value.as_array()?;
				let column = values.first()?.as_i64()? as i32;
				let row = values.get(1)?.as_i64()? as i32;
				Some((name, column, row))
			})
			.collect();
		if positions.is_empty() {
			return false;
		}
		let Some(engine) = self.engine.as_mut() else {
			return false;
		};
		let Ok(outcome) = engine.dispatch(Command::SetFreePositions { positions })
		else {
			return false;
		};
		self.config.borrow_mut().apply(engine.config());
		let rows = rows_after(engine, Some(&outcome.changes));
		self.set_rows(rows);
		self.read_selection();
		self.read_focus();
		self.reset();
		self.revision += 1;
		self.revision_changed();
		true
	}

	#[qslot]
	fn reset_free_positions(&mut self) -> bool {
		let Some(engine) = self.engine.as_mut() else {
			return false;
		};
		let Ok(outcome) = engine.dispatch(Command::ResetFreePositions) else {
			return false;
		};
		self.config.borrow_mut().apply(engine.config());
		let rows = rows_after(engine, Some(&outcome.changes));
		self.set_rows(rows);
		self.reset();
		self.revision += 1;
		self.revision_changed();
		true
	}

	#[qslot]
	fn folders_json(&self, path: String) -> String {
		let mut folders: Vec<(String, String)> = std::fs::read_dir(&path)
			.ok()
			.into_iter()
			.flatten()
			.filter_map(|entry| entry.ok())
			.filter(|entry| entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false))
			.filter_map(|entry| {
				let name = entry.file_name().to_string_lossy().into_owned();
				if name.starts_with('.') {
					return None;
				}
				let path = entry.path().to_string_lossy().into_owned();
				Some((name, path))
			})
			.collect();
		folders.sort_by(|left, right| left.0.to_lowercase().cmp(&right.0.to_lowercase()));
		serde_json::to_string(
			&folders
				.into_iter()
				.map(|(name, path)| serde_json::json!({ "name": name, "path": path }))
				.collect::<Vec<_>>(),
		)
		.unwrap_or_else(|_| String::from("[]"))
	}

	#[qslot]
	fn row_visible(&self, path: String) -> bool {
		self.rows.iter().any(|row| row.path == path)
	}

	#[qslot]
	fn row_index(&self, path: String) -> i32 {
		self.rows
			.iter()
			.position(|row| row.path == path)
			.map(|index| index as i32)
			.unwrap_or(-1)
	}

	#[qslot]
	fn focus_path(&mut self, path: String) {
		let Some(engine) = self.engine.as_mut() else {
			return;
		};
		let _ = engine.dispatch(Command::Focus(FocusCommand::Set {
			pane: PaneId(0),
			path: std::path::PathBuf::from(path),
		}));
		self.read_focus();
	}

	#[qslot]
	fn focus_first(&mut self) {
		if let Some(engine) = self.engine.as_mut() {
			let _ = engine.dispatch(Command::Focus(FocusCommand::First));
		}
		self.read_focus();
	}

	#[qslot]
	fn focus_last(&mut self) {
		if let Some(engine) = self.engine.as_mut() {
			let _ = engine.dispatch(Command::Focus(FocusCommand::Last));
		}
		self.read_focus();
	}

	#[qslot]
	fn move_focus(&mut self, direction: String) -> bool {
		let Some(direction) = direction_from(&direction) else {
			return false;
		};
		let Some(engine) = self.engine.as_mut() else {
			return false;
		};
		let before = engine.focus();
		let Ok(outcome) = engine.dispatch(Command::Focus(FocusCommand::Move(direction))) else {
			return false;
		};
		let after = engine.focus();
		self.read_focus();
		before != after && outcome.changes.focus.is_some()
	}

	#[qslot]
	fn set_path(&mut self, path: String) {
		let path = PathBuf::from(path);
		if !path.is_dir() {
			return;
		}
		if let Ok(engine) = Engine::open(&path) {
			self.engine = Some(engine);
			self.after_engine_change();
		}
	}

	#[qslot]
	fn navigate(&mut self, path: String) -> bool {
		let target = PathBuf::from(&path);
		if !target.is_dir() {
			return false;
		}
		self.navigate_command(Command::Navigate(NavigationRequest {
			pane: PaneId(0),
			target,
			record_history: true,
		}))
	}

	#[qslot]
	fn open(&mut self, path: String) {
		if Path::new(&path).is_dir() {
			let _ = self.navigate(path);
			return;
		}
		self.focus_path(path);
		let _ = self.invoke(String::from("open"));
	}

	#[qslot]
	fn go_up(&mut self) {
		self.navigate_command(Command::GoUp);
	}

	#[qslot]
	fn actions_json(&self, menu: String, target: String) -> String {
		let Some(engine) = &self.engine else {
			return String::from("[]");
		};
		let Some(menu) = menu_kind(&menu) else {
			return String::from("[]");
		};
		let Some(target) = target_kind(&target) else {
			return String::from("[]");
		};
		let mut actions = engine.actions(&ActionRequest { menu, target });
		actions.retain(|spec| supported_action(spec.id.as_str()));
		// Trash is the normal action; permanent deletion only appears when
		// there is no working trash action for the target.
		let trash_available = actions
			.iter()
			.any(|spec| spec.id == ActionId::TRASH && spec.enabled);
		actions.retain(|spec| {
			spec.id != ActionId::DELETE && (spec.id != ActionId::DESTROY || !trash_available)
		});
		let actions: Vec<serde_json::Value> = actions
			.into_iter()
			.map(|spec| {
				let descriptor = hishell::action::descriptor(spec.id);
				serde_json::json!({
					"id": spec.id,
					"enabled": spec.enabled,
					"visible": spec.visible,
					"checked": spec.checked,
					"icon": descriptor.map(|descriptor| descriptor.icon_name).unwrap_or(""),
					"shortcut": descriptor
						.and_then(|descriptor| descriptor.default_shortcut)
						.unwrap_or(""),
					"here": descriptor
						.map(|descriptor| descriptor.subjects.contains(hishell::action::ActionSubjects::HERE))
						.unwrap_or(false),
					"items": descriptor
						.map(|descriptor| descriptor.subjects.intersects(hishell::action::ActionSubjects::ITEMS))
						.unwrap_or(false),
				})
			})
			.collect();
		serde_json::to_string(&actions).unwrap_or_else(|_| String::from("[]"))
	}

	#[qslot]
	fn invoke(&mut self, id: String) -> String {
		let Some(action) = ActionId::from_str(&id) else {
			return String::from("{}");
		};
		if action == ActionId::COPY {
			self.copy_selection();
			return String::from("{}");
		}
		if action == ActionId::CUT {
			self.cut_selection();
			return String::from("{}");
		}
		if action == ActionId::PASTE {
			self.paste();
			return String::from("{}");
		}
		if action == ActionId::PROPERTIES {
			if let Some(path) = self.target_paths().first() {
				self.properties_requested(path.to_string_lossy().into_owned());
			}
			return String::from("{}");
		}
		if action == ActionId::RENAME
			|| action == ActionId::TRASH
			|| action == ActionId::DELETE
			|| action == ActionId::DESTROY
			|| action == ActionId::OPEN_WITH
		{
			let paths = self.target_paths();
			if action == ActionId::RENAME {
				if let Some(path) = paths.first() {
					let suggested = path
						.file_name()
						.map(|name| name.to_string_lossy().into_owned())
						.unwrap_or_default();
					self.rename_requested(path.to_string_lossy().into_owned(), suggested);
				}
			} else if action == ActionId::OPEN_WITH {
				if let Some(path) = paths.first() {
					self.open_with_requested(path.to_string_lossy().into_owned());
				}
			} else {
				let paths: Vec<String> = paths
					.iter()
					.map(|path| path.to_string_lossy().into_owned())
					.collect();
				self.trash_requested(
					serde_json::to_string(&paths).unwrap_or_else(|_| String::from("[]")),
					action != ActionId::TRASH,
				);
			}
			return String::from("{}");
		}
		let Some(engine) = self.engine.as_mut() else {
			return String::from("{}");
		};
		let Ok(outcome) = engine.dispatch(Command::Invoke(action)) else {
			return String::from("{}");
		};
		let job = outcome.job.is_some();
		self.path = engine.location().path().to_string_lossy().into_owned();
		self.config.borrow_mut().apply(engine.config());
		let rows = rows_after(engine, Some(&outcome.changes));
		self.set_rows(rows);
		self.read_selection();
		self.read_focus();
		self.reset();
		self.revision += 1;
		self.path_changed();
		self.revision_changed();
		self.selection_changed();
		let effect_count = outcome.effects.len();
		for effect in outcome.effects {
			match effect {
				Effect::Prompt(Prompt::Rename { path, suggested }) => {
					self.rename_requested(path.to_string_lossy().into_owned(), suggested);
				}
				Effect::Prompt(Prompt::OpenWith { path }) => {
					self.open_with_requested(path.to_string_lossy().into_owned());
				}
				Effect::Prompt(Prompt::Destroy { paths }) => {
					let paths: Vec<String> = paths
						.iter()
						.map(|path| path.to_string_lossy().into_owned())
						.collect();
					self.trash_requested(
						serde_json::to_string(&paths).unwrap_or_else(|_| String::from("[]")),
						true,
					);
				}
				_ => {}
			}
		}
		if job {
			self.schedule_refresh(250);
		}
		serde_json::json!({
			"effects": effect_count,
			"job": job,
		})
		.to_string()
	}

	#[qslot]
	fn rename(&mut self, path: String, new_name: String) -> bool {
		self.run_op(Op::Rename {
			path: PathBuf::from(path),
			new_name,
		})
	}

	#[qslot]
	fn trash(&mut self, paths_json: String, permanent: bool) -> bool {
		let paths: Vec<PathBuf> = serde_json::from_str::<Vec<String>>(&paths_json)
			.unwrap_or_default()
			.into_iter()
			.map(PathBuf::from)
			.collect();
		if paths.is_empty() {
			return false;
		}
		let op = if permanent {
			Op::Delete { paths }
		} else {
			Op::Trash { paths }
		};
		self.run_op(op)
	}

	#[qslot]
	fn drop(&mut self, uris: String, dest: String, action: String) -> bool {
		let dest = PathBuf::from(dest);
		if !dest.is_dir() {
			return false;
		}
		let sources: Vec<PathBuf> = parse_uris(&uris)
			.into_iter()
			.filter(|source| {
				// Dropping an item back where it already is, or dropping a
				// folder into itself, must never touch the source.
				source.parent() != Some(dest.as_path())
					&& *source != dest
					&& !(source.is_dir() && dest.starts_with(source))
			})
			.collect();
		if sources.is_empty() {
			return false;
		}
		// Never replace an existing destination: an overwrite is what turns a
		// same-folder drop into data loss.
		let options = CopyOptions::default();
		let op = match action.as_str() {
			"move" => Op::Move {
				sources,
				dest,
				options,
			},
			"link" => Op::Link { sources, dest },
			_ => Op::Copy {
				sources,
				dest,
				options,
			},
		};
		self.run_op(op)
	}

	#[qslot]
	fn thumbnail(&self, path: String, size: i32) -> String {
		use hishell::platform::{ThumbnailRequest, Thumbnailer};
		hishell::FreeDesktopThumbnailer
			.thumbnail(&ThumbnailRequest {
				path: PathBuf::from(path),
				size: size.max(1) as u32,
			})
			.ok()
			.flatten()
			.map(|thumbnail| format!("file://{}", thumbnail.path.to_string_lossy()))
			.unwrap_or_default()
	}

	#[qslot]
	fn poll_gamepad(&self) -> String {
		#[cfg(feature = "gamepad")]
		{
			return gamepad::poll()
				.map(|input| input.as_str().to_string())
				.unwrap_or_default();
		}
		#[cfg(not(feature = "gamepad"))]
		{
			String::new()
		}
	}

	#[qslot]
	fn apps_json(&self, path: String) -> String {
		let apps = FreeDesktopApps;
		let entries: Vec<serde_json::Value> = apps
			.apps_for(Path::new(&path))
			.into_iter()
			.map(|app| {
				serde_json::json!({
					"id": app.id.0,
					"name": app.name,
					"icon": match app.icon {
						Some(hishell::IconRef::Theme(name)) => name,
						Some(hishell::IconRef::Path(path)) => format!("file://{}", path.to_string_lossy()),
						None => String::new(),
					},
				})
			})
			.collect();
		serde_json::to_string(&entries).unwrap_or_else(|_| String::from("[]"))
	}

	#[qslot]
	fn open_with(&mut self, path: String, app: String) -> bool {
		let Some(engine) = self.engine.as_mut() else {
			return false;
		};
		engine
			.dispatch(Command::Launch(LaunchRequest::App {
				path: PathBuf::from(path),
				app: AppId(app),
			}))
			.is_ok()
	}

	#[qslot]
	fn select_all(&mut self) {
		self.apply_selection(Command::SelectAll);
	}

	#[qslot]
	fn clear_selection(&mut self) {
		self.apply_selection(Command::ClearSelection);
	}

	#[qslot]
	fn refresh(&mut self) {
		self.refresh_now();
	}

	#[qslot]
	fn item_count(&self) -> i32 {
		self.rows.len() as i32
	}

	#[qslot]
	fn poll_descriptors(&mut self) -> bool {
		let epoch = hishell::descriptor_generator::results_epoch();
		if epoch == self.last_descriptor_epoch {
			return false;
		}
		if hishell::descriptor_generator::folder_busy(Path::new(&self.path)) {
			return false;
		}
		self.last_descriptor_epoch = epoch;
		if !hishell::descriptor_generator::has_results() {
			return false;
		}
		self.refresh_now();
		true
	}

	#[qslot]
	fn debug_rows(&self) -> String {
		self.rows
			.iter()
			.map(|row| row.name.clone())
			.collect::<Vec<_>>()
			.join(",")
	}

	#[qslot]
	fn view_json(
		&self,
		width: f64,
		height: f64,
		grid_unit: f64,
		small_spacing: f64,
		label_height: f64,
	) -> String {
		let Some(engine) = &self.engine else {
			return String::from("{}");
		};
		let request = ViewRequest {
			viewport: Viewport {
				width,
				height,
				horizontal_scrollbar: 8.0,
				vertical_scrollbar: 8.0,
			},
			metrics: Metrics {
				grid_unit,
				small_spacing,
				medium_spacing: small_spacing * 1.5,
				large_spacing: small_spacing * 2.0,
				label_height,
			},
		};
		match engine.view(request) {
			ViewSpec::Folder(view) => match view.mode {
				FolderMode::Grid(grid) => serde_json::json!({
					"mode": "grid",
					"lines": grid.lines,
					"count": view.slots.len(),
					"icon_size": grid.icon_size,
					"cell_width": grid.cell.width,
					"cell_height": grid.cell.height,
					"gap": grid.gap,
					"horizontal": grid.horizontal,
					"grouped": !view.headers.is_empty(),
					"headers": view.headers.iter().map(|header| serde_json::json!({
						"title": header.title,
						"x": header.rect.x,
						"y": header.rect.y,
						"width": header.rect.width,
						"height": header.rect.height,
					})).collect::<Vec<_>>(),
					"revision": view.revision,
					"free": view.sort.key == hishell::view::SortKey::Free,
					"slots": view.slots.iter().filter_map(|slot| {
						engine.item(slot.item).map(|item| serde_json::json!({
							"path": item.path.to_string_lossy(),
							"name": item.name,
							"title": item.title,
							"icon": match &item.icon {
								hishell::IconRef::Theme(name) => name.clone(),
								hishell::IconRef::Path(path) => format!("file://{}", path.to_string_lossy()),
							},
							"is_image": item.mime.as_deref().is_some_and(|mime| mime.starts_with("image/")),
							"is_directory": item.fs_kind == hishell::FsKind::Directory,
							"is_symlink": item.is_symlink,
							"control_kind": match item.kind {
								hishell::ItemKind::Button => 1,
								hishell::ItemKind::Toggle if item.toggle_on => 3,
								hishell::ItemKind::Toggle => 2,
								hishell::ItemKind::Number => 4,
								_ => 0,
							},
							"number_value": item.number_value,
							"x": slot.rect.x,
							"y": slot.rect.y,
							"width": slot.rect.width,
							"height": slot.rect.height,
						}))
					}).collect::<Vec<_>>(),
				})
				.to_string(),
				FolderMode::List(list) => serde_json::json!({
					"mode": "list",
					"columns": list.columns.iter().map(|column| column.as_key()).collect::<Vec<_>>(),
					"header": list.header,
					"grouped": !view.headers.is_empty(),
					"revision": view.revision,
				})
				.to_string(),
			},
			ViewSpec::File(_) => String::from("{}"),
		}
	}

	#[qslot]
	fn is_item_active(&self, path: String) -> bool {
		self.active_items.iter().any(|item| item == &path)
	}

	#[qslot]
	fn refresh_active_items(&mut self) {
		let Some(engine) = &self.engine else {
			return;
		};
		let mut paths: Vec<String> = engine
			.execution()
			.active_items()
			.iter()
			.map(|path| path.to_string_lossy().into_owned())
			.collect();
		paths.sort();
		if paths == self.active_items {
			return;
		}
		self.active_items = paths;
		self.active_revision += 1;
		self.active_changed();
	}

	#[qslot]
	fn refresh_async(&self) {
		let handle = self.get_thread_handle();
		std::thread::spawn(move || {
			std::thread::sleep(std::time::Duration::from_millis(50));
			handle.invoke_mut(|directory: &mut Directory| directory.refresh_now());
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

/// Apply the folder delta to the existing rows. A reset, or an order that no
/// longer matches the item set, rebuilds the rows; an order-only delta reuses
/// the payloads the model already has.
fn rows_after(engine: &Engine, changes: Option<&ChangeSet>) -> Vec<DirectoryRow> {
	match changes.map(|changes| &changes.folder) {
		Some(FolderDelta::Items { order, .. }) => {
			let rows: Option<Vec<DirectoryRow>> = order
				.iter()
				.map(|id| engine.item(*id).map(row_from_item))
				.collect();
			match rows {
				Some(rows) if rows.len() == engine.items().len() => rows,
				_ => engine.items().iter().map(row_from_item).collect(),
			}
		}
		_ => engine.items().iter().map(row_from_item).collect(),
	}
}

fn row_from_item(item: &hishell::Item) -> DirectoryRow {
	DirectoryRow {
		name: item.name.clone(),
		path: item.path.to_string_lossy().into_owned(),
		is_directory: item.fs_kind == hishell::FsKind::Directory,
		icon: match &item.icon {
			hishell::IconRef::Theme(name) => name.clone(),
			hishell::IconRef::Path(path) => format!("file://{}", path.to_string_lossy()),
		},
		title: item.title.clone(),
		size_bytes: item.size as i64,
		modified_time: item.modified as i64,
		created_time: item.created as i64,
		accessed_time: item.accessed as i64,
		mime: item.mime.clone().unwrap_or_default(),
		group_label: item.group_label.clone(),
		is_image: item
			.mime
			.as_deref()
			.is_some_and(|mime| mime.starts_with("image/")),
		is_symlink: item.is_symlink,
		control_kind: match item.kind {
			hishell::ItemKind::Button => 1,
			hishell::ItemKind::Toggle if item.toggle_on => 3,
			hishell::ItemKind::Toggle => 2,
			hishell::ItemKind::Number => 4,
			_ => 0,
		},
		number_value: item.number_value.clone(),
	}
}

fn save_session(path: &str) {
	let store = hishell::SessionStore::default();
	let mut data = store.load();
	if data.path != Path::new(path) {
		data.path = PathBuf::from(path);
		let _ = store.save(&data);
	}
}

fn percent_decode(input: &str) -> String {
	let mut out = String::with_capacity(input.len());
	let bytes = input.as_bytes();
	let mut index = 0;
	while index < bytes.len() {
		if bytes[index] == b'%' && index + 2 < bytes.len() {
			let high = (bytes[index + 1] as char).to_digit(16);
			let low = (bytes[index + 2] as char).to_digit(16);
			if let (Some(high), Some(low)) = (high, low) {
				out.push((high * 16 + low) as u8 as char);
				index += 3;
				continue;
			}
		}
		out.push(bytes[index] as char);
		index += 1;
	}
	out
}

fn initial_path(argument: Option<String>) -> PathBuf {
	let mut argument = argument.unwrap_or_else(|| String::from("."));
	if let Some(rest) = argument.strip_prefix("file://") {
		argument = percent_decode(rest);
	}
	if argument == "~" || argument.starts_with("~/") {
		if let Ok(home) = std::env::var("HOME") {
			argument = if argument == "~" {
				home
			} else {
				format!("{}{}", home, &argument[1..])
			};
		}
	}
	let path = PathBuf::from(&argument);
	let absolute = if path.is_absolute() {
		path
	} else {
		std::env::current_dir()
			.map(|cwd| cwd.join(path))
			.unwrap_or_else(|_| PathBuf::from(argument))
	};
	let saved = hishell::SessionStore::default().startup_location(&absolute);
	let path = saved.path().to_path_buf();
	if path.is_file() {
		path.parent().map(Path::to_path_buf).unwrap_or(path)
	} else {
		path
	}
}

#[derive(Default)]
pub struct TestBridge {
	root: String,
	passes: usize,
	failures: Vec<String>,
}

#[qobject]
impl TestBridge {
	qproperty!("root", Member = root);

	#[qslot]
	fn exists(&self, path: String) -> bool {
		Path::new(&path).exists()
	}

	#[qslot]
	fn pass(&mut self, name: String) {
		self.passes += 1;
		println!("SELFTEST PASS {name}");
	}

	#[qslot]
	fn fail(&mut self, name: String, message: String) {
		self.failures.push(format!("{name}: {message}"));
		println!("SELFTEST FAIL {name}: {message}");
	}
}

fn self_test() {
	let root = std::env::temp_dir().join(format!("hishell-selftest-{}", std::process::id()));
	let _ = std::fs::remove_dir_all(&root);
	let dir = root.join("dir");
	let child = dir.join("child");
	std::fs::create_dir_all(&child).unwrap();
	std::fs::write(dir.join("a.txt"), b"a").unwrap();
	std::fs::write(dir.join("b.txt"), b"b").unwrap();
	std::fs::write(dir.join("c.txt"), b"c").unwrap();
	std::fs::write(dir.join("keep.txt"), b"keep").unwrap();

	let mut app = QApp::new();
	unsafe { hishell_register_drag_helper() };
	let bridge = Rc::new(RefCell::new(TestBridge {
		root: root.to_string_lossy().into_owned(),
		..TestBridge::default()
	}));
	app.application_name("hishell-qt-selftest")
		.register::<TestBridge>()
		.register::<Directory>()
		.register::<PathBridge>()
		.set_initial_object("leftDirectory", Rc::new(RefCell::new(Directory::new(&dir))))
		.set_initial_object(
			"rightDirectory",
			Rc::new(RefCell::new(Directory::new(&dir))),
		)
		.set_initial_object("testBridge", bridge.clone());

	include_bytes_qml!("qml", "hishell_qt");
	app.load_qml_from_file("qrc:/hishell_qt/qml/SelfTest.qml")
		.run();

	let bridge = bridge.borrow();
	println!(
		"SELFTEST RESULT passes={} failures={}",
		bridge.passes,
		bridge.failures.len()
	);
	for failure in &bridge.failures {
		println!("SELFTEST FAILURE {failure}");
	}
	let failed = !bridge.failures.is_empty();
	drop(bridge);
	if failed {
		std::process::exit(1);
	}
	let _ = std::fs::remove_dir_all(root);
}

fn main() {
	if std::env::var_os("HISHELL_SELF_TEST").is_some() {
		self_test();
		return;
	}
	let path = initial_path(std::env::args().nth(1));
	#[cfg(feature = "gamepad")]
	gamepad::init();
	let mut app = QApp::new();
	unsafe { hishell_register_drag_helper() };
	app.application_name("hishell-qt")
		.register::<ConfigBridge>()
		.register::<Directory>()
		.register::<PathBridge>()
		.set_initial_object(
			"leftDirectory",
			Rc::new(RefCell::new(Directory::new(&path))),
		)
		.set_initial_object(
			"rightDirectory",
			Rc::new(RefCell::new(Directory::new(&path))),
		);

	include_bytes_qml!("qml", "hishell_qt");
	app.load_qml_from_file("qrc:/hishell_qt/qml/Main.qml").run();
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn uri_lists_decode_file_urls() {
		assert_eq!(
			parse_uris("file:///tmp/a%20b\n# comment\n/tmp/c\n"),
			vec![PathBuf::from("/tmp/a b"), PathBuf::from("/tmp/c")]
		);
		assert!(parse_uris("").is_empty());
	}

	#[test]
	fn transition_json_carries_the_core_relation() {
		let plan = NavigationPlan {
			pane: PaneId(0),
			requested: PathBuf::from("/a/b"),
			from: PathBuf::from("/a"),
			to: PathBuf::from("/a/b"),
			focus: None,
			relation: hishell::navigation::PathRelation::Child { distance: 1 },
			common_ancestor: PathBuf::from("/a"),
			close: Vec::new(),
			open: Vec::new(),
			animated: true,
		};
		let json = transition_json(&plan);
		assert!(json.contains("\"to\":\"/a/b\""), "{json}");
		assert!(json.contains("Child"), "{json}");
		assert!(json.contains("\"animated\":true"), "{json}");
	}

	#[test]
	fn only_implemented_actions_reach_the_menu() {
		assert!(supported_action("rename"));
		assert!(supported_action("trash"));
		assert!(supported_action("open-with"));
		assert!(!supported_action("copy"));
	}
}
