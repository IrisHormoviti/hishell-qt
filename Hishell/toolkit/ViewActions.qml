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
