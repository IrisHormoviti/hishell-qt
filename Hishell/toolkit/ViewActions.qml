pragma ComponentBehavior: Bound

import QtQuick

// Single source of truth for the folder-view settings. The menu-based ViewMenu
// (menu bar and context menu) and the touch-friendly ViewButton dialog both
// instantiate this object over the same Directory, so the two surfaces share
// one set of values, writes and behaviour instead of drifting apart.
QtObject {
	id: viewActions

	required property var directory
	property var config: viewActions.directory ? viewActions.directory.config : null
	// Which config the writes target: the global folder.cfg, or this folder's
	// own .directory.
	property bool isLocal: viewActions.directory ? viewActions.directory.has_meta : false

	// The window, so view settings can play an event sound. The two surfaces
	// that instantiate this object (ViewMenu, ViewDialog) both sit under the
	// window's layout, so it is set explicitly rather than walked up.
	property var window

	// Event sounds (ClamOS XDG sound theme). Played through the window's sound
	// object; a null window (or a missing theme) simply stays silent.
	function playSound(name) {
		if (viewActions.window && viewActions.window.sound)
			viewActions.window.sound.play(name);
	}

	readonly property string viewConfigGroupName: "Folder View"

	// ── Current values ───────────────────────────────────────────────────
	readonly property int gridSize: viewActions.config ? viewActions.config.grid_size : 64
	readonly property int gridSizeMin: 16
	readonly property int gridSizeMax: 256
	readonly property int gridSizeStep: 12

	readonly property int viewMode: viewActions.config ? viewActions.config.view_mode : 0
	readonly property bool isListView: viewActions.viewMode === 1
	readonly property string viewModeIcon: viewActions.isListView ? "view-list-details" : "view-grid"
	readonly property string viewModeLabel: viewActions.isListView ? qsTr("List") : qsTr("Grid")

	// Optional columns the list view can show, in the order the menu offers
	// them. "Name" is not here: it is always the leading column. The configured
	// order lives in `ListColumns` and controls left-to-right display order.
	readonly property var availableListColumns: [
		{ key: "SIZE", label: qsTr("Size") },
		{ key: "MODIFIED", label: qsTr("Date Modified") },
		{ key: "CREATED", label: qsTr("Date Created") },
		{ key: "ACCESSED", label: qsTr("Date Accessed") },
		{ key: "TYPE", label: qsTr("Type") }
	]

	readonly property var listColumns: {
		const cfg = viewActions.config;
		if (!cfg)
			return [];
		let parsed = [];
		try {
			parsed = JSON.parse(String(cfg.list_columns));
		} catch (e) {
			return [];
		}
		if (!Array.isArray(parsed))
			return [];
		const known = {};
		for (const column of viewActions.availableListColumns)
			known[column.key] = true;
		const seen = {};
		const result = [];
		for (const value of parsed) {
			const key = String(value).toUpperCase();
			if (!known[key] || seen[key])
				continue;
			seen[key] = true;
			result.push(key);
		}
		return result;
	}

	function listColumnLabel(key) {
		for (const column of viewActions.availableListColumns) {
			if (column.key === key)
				return column.label;
		}
		return key;
	}

	function hasListColumn(key) {
		return viewActions.listColumns.indexOf(key) !== -1;
	}

	// Write the entire ordered column list. The menu adds/removes one key at a
	// time but the config stores one array, so every edit goes through here.
	function setListColumns(columns) {
		const known = {};
		for (const column of viewActions.availableListColumns)
			known[column.key] = true;
		const seen = {};
		const result = [];
		for (const value of columns) {
			const key = String(value).toUpperCase();
			if (!known[key] || seen[key])
				continue;
			seen[key] = true;
			result.push(key);
		}
		viewActions.setConfig("ListColumns", JSON.stringify(result));
	}

	function setListColumnVisible(key, visible) {
		const columns = viewActions.listColumns.slice();
		const index = columns.indexOf(key);
		if (visible && index === -1)
			columns.push(key);
		else if (!visible && index !== -1)
			columns.splice(index, 1);
		else
			return;
		viewActions.setListColumns(columns);
	}

	// Move a shown column one place left (-1) or right (+1).
	function moveListColumn(key, delta) {
		const columns = viewActions.listColumns.slice();
		const index = columns.indexOf(key);
		const target = index + delta;
		if (index === -1 || target < 0 || target >= columns.length)
			return;
		const [column] = columns.splice(index, 1);
		columns.splice(target, 0, column);
		viewActions.setListColumns(columns);
	}

	function canMoveListColumn(key, delta) {
		const columns = viewActions.listColumns;
		const index = columns.indexOf(key);
		const target = index + delta;
		return index !== -1 && target >= 0 && target < columns.length;
	}

	readonly property bool showLabels: viewActions.config ? viewActions.config.show_labels : true
	readonly property bool labelsBesideIcons: viewActions.config ? viewActions.config.grid_labels_beside_icons : false
	readonly property int labelText: viewActions.config ? viewActions.config.label_text : 0

	readonly property int sort: viewActions.config ? viewActions.config.sort : 0
	readonly property int sortDateMode: viewActions.config ? viewActions.config.sort_date_mode : 0
	readonly property int sortAlphaMode: viewActions.config ? viewActions.config.sort_alpha_mode : 0

	readonly property int gridLines: viewActions.config ? viewActions.config.grid_lines : 0
	readonly property bool scrollHorizontal: viewActions.config ? viewActions.config.scroll_horizontal : false
	readonly property int horizontalAlign: viewActions.config ? viewActions.config.grid_horizontal_align : 0
	readonly property int verticalAlign: viewActions.config ? viewActions.config.grid_vertical_align : 0

	readonly property bool centerFocus: viewActions.config ? viewActions.config.center_focus : false
	readonly property bool smoothScrolling: viewActions.config ? viewActions.config.smooth_scrolling : true
	readonly property bool openOnClick: viewActions.config ? viewActions.config.open_on_click : true
	readonly property bool focusEmptySlots: viewActions.config ? viewActions.config.focus_empty_slots : false
	// Empty grid cells only exist in free placement, which is where FocusEmptySlots
	// can have any effect.
	readonly property bool freePlacement: viewActions.config ? (viewActions.config.sort === 3 && viewActions.config.view_mode === 0) : false

	readonly property string wallpaper: viewActions.config ? String(viewActions.config.wallpaper) : ""
	readonly property bool stashShown: viewActions.config ? viewActions.config.stash_shown : false
	readonly property bool stashDotfiles: viewActions.config ? viewActions.config.stash_dotfiles : false

	readonly property bool hasFreePlacementPositions: {
		const cfg = viewActions.config;
		if (!cfg)
			return false;
		try {
			const positions = JSON.parse(cfg.free_placement_positions);
			return !!positions && Object.keys(positions).length > 0;
		} catch (e) {
			return false;
		}
	}

	// ── Writes ───────────────────────────────────────────────────────────
	function setSectionConfig(section, key, value) {
		if (viewActions.directory)
			viewActions.directory.set_config(section, key, value, viewActions.isLocal);
	}

	function setConfig(key, value) {
		viewActions.setSectionConfig(viewActions.viewConfigGroupName, key, value);
	}

	function setNavigationConfig(key, value) {
		viewActions.setSectionConfig("Folder Navigation", key, value);
	}

	function setViewMode(value) {
		viewActions.setConfig("ViewMode", value);
		viewActions.playSound("menu-item");
	}

	function setSort(value) {
		viewActions.setConfig("Sort", value);
		viewActions.playSound("menu-item");
	}

	// Same writes without the sound, for callers that play their own (the View
	// menu gates the sound on the menu being on screen).
	function setViewModeSilent(value) {
		viewActions.setConfig("ViewMode", value);
	}

	function setSortSilent(value) {
		viewActions.setConfig("Sort", value);
	}

	function resetFreePlacement() {
		if (viewActions.directory)
			viewActions.directory.reset_free_positions();
		viewActions.playSound("dialog-ok");
	}

	function setGridSize(value) {
		const clamped = Math.max(viewActions.gridSizeMin, Math.min(viewActions.gridSizeMax, Math.round(value)));
		viewActions.setConfig("GridSize", String(clamped));
	}

	function nudgeGridSize(delta) {
		viewActions.setGridSize(viewActions.gridSize + delta);
	}

	function toggleViewMode() {
		viewActions.setViewMode(viewActions.isListView ? "GRID" : "LIST");
	}

	function pathFromUrl(url) {
		let path = String(url);
		if (path.startsWith("file://"))
			path = path.substring(7);
		return decodeURIComponent(path);
	}
}
