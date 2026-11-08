import QtQuick
import org.kde.kirigami as Kirigami

// Single source of truth for the folder-view settings. The View menu and the
// Configure menu both read and write the same Directory config through here.
QtObject {
	id: viewActions

	required property var directory
	property var config: viewActions.directory ? viewActions.directory.config : null
	// Which config the writes target: the global folder.cfg, or this folder's
	// own .directory.
	property bool isLocal: viewActions.directory ? viewActions.directory.has_meta() : false
	property var window

	readonly property string viewConfigGroupName: "Folder View"

	// ── Current values ───────────────────────────────────────────────────
	readonly property int lineCountMin: 1
	readonly property int lineCountMax: 8
	readonly property int lineCount: {
		const lines = viewActions.config ? viewActions.config.grid_lines : 0
		return lines > 0
			? Math.max(viewActions.lineCountMin, Math.min(viewActions.lineCountMax, lines))
			: 4
	}
	readonly property string lineCountLabel: viewActions.scrollHorizontal ? "Rows" : "Columns"

	readonly property string gridMode: viewActions.config ? viewActions.config.grid_mode : "LINES"
	readonly property bool isIconSize: viewActions.gridMode === "SIZE"
	readonly property int iconSize: viewActions.config
		? Math.max(16, Math.min(256, viewActions.config.grid_size)) : 72

	readonly property bool isListView: viewActions.config
		? viewActions.config.view_mode === "LIST" : false
	readonly property string viewModeIcon: viewActions.isListView ? "view-list-details" : "view-grid"
	readonly property string viewModeLabel: viewActions.isListView ? "List" : "Grid"

	readonly property var availableListColumns: [
		{ key: "TITLE", label: "Title" },
		{ key: "FILENAME", label: "File Name" },
		{ key: "SIZE", label: "Size" },
		{ key: "MODIFIED", label: "Date Modified" },
		{ key: "CREATED", label: "Date Created" },
		{ key: "ACCESSED", label: "Date Accessed" },
		{ key: "TYPE", label: "Type" }
	]

	readonly property bool showListHeader: viewActions.config ? viewActions.config.list_header : true

	function isNameColumn(key) {
		return key === "TITLE" || key === "FILENAME"
	}

	function normalizeListColumns(values) {
		const known = {}
		for (const column of viewActions.availableListColumns)
			known[column.key] = true
		const seen = {}
		const result = []
		if (values) {
			for (const value of values) {
				const key = String(value).toUpperCase()
				if (!known[key] || seen[key])
					continue
				seen[key] = true
				result.push(key)
			}
		}
		if (!result.some(viewActions.isNameColumn))
			result.unshift("TITLE")
		return result
	}

	readonly property var listColumns: {
		const cfg = viewActions.config
		if (!cfg)
			return viewActions.normalizeListColumns([])
		let parsed = []
		try {
			parsed = JSON.parse(String(cfg.list_columns))
		} catch (error) {
			parsed = []
		}
		return viewActions.normalizeListColumns(Array.isArray(parsed) ? parsed : [])
	}

	// Shown columns first, then the hidden ones, so toggling or moving a column
	// moves its menu row as well.
	readonly property var listColumnMenuOrder: {
		const shown = viewActions.listColumns.slice()
		const hidden = []
		for (const column of viewActions.availableListColumns) {
			if (shown.indexOf(column.key) === -1)
				hidden.push(column.key)
		}
		return shown.concat(hidden)
	}

	function listColumnLabel(key) {
		for (const column of viewActions.availableListColumns) {
			if (column.key === key)
				return column.label
		}
		return key
	}

	function hasListColumn(key) {
		return viewActions.listColumns.indexOf(key) !== -1
	}

	function setListColumns(columns) {
		viewActions.setConfig("ListColumns",
			JSON.stringify(viewActions.normalizeListColumns(columns)))
	}

	function setListColumnVisible(key, visible) {
		const columns = viewActions.listColumns.slice()
		const index = columns.indexOf(key)
		if (visible && index === -1) {
			columns.push(key)
		} else if (!visible && index !== -1) {
			const nameColumns = columns.filter(viewActions.isNameColumn)
			if (viewActions.isNameColumn(key) && nameColumns.length === 1)
				columns[index] = key === "TITLE" ? "FILENAME" : "TITLE"
			else
				columns.splice(index, 1)
		} else {
			return
		}
		viewActions.setListColumns(columns)
	}

	function moveListColumn(key, delta) {
		const columns = viewActions.listColumns.slice()
		const index = columns.indexOf(key)
		const target = index + delta
		if (index === -1 || target < 0 || target >= columns.length)
			return
		const column = columns.splice(index, 1)[0]
		columns.splice(target, 0, column)
		viewActions.setListColumns(columns)
	}

	function canMoveListColumn(key, delta) {
		const columns = viewActions.listColumns
		const index = columns.indexOf(key)
		const target = index + delta
		return index !== -1 && target >= 0 && target < columns.length
	}

	function setListHeaderVisible(visible) {
		viewActions.setConfig("ListHeader", String(visible))
	}

	readonly property bool showLabels: viewActions.config ? viewActions.config.show_labels : true
	readonly property bool labelsBesideIcons: viewActions.config
		? viewActions.config.gridLabelsBesidesIcons : false
	readonly property string labelText: viewActions.config ? viewActions.config.label_text : "TITLE"

	readonly property string sort: viewActions.config ? viewActions.config.sort : "NEWEST"
	readonly property string sortDateMode: viewActions.config
		? viewActions.config.sort_date_mode : "MODIFIED"
	readonly property string sortAlphaMode: viewActions.config
		? viewActions.config.sort_alpha_mode : "FILENAMES"
	readonly property string groupMode: viewActions.config ? viewActions.config.group_mode : "NONE"
	readonly property bool customGroups: viewActions.groupMode === "CUSTOM"

	readonly property bool scrollHorizontal: viewActions.config
		? viewActions.config.scrollHorizontal === "HORIZONTAL" : false
	readonly property string horizontalAlign: viewActions.config
		? viewActions.config.gridHorizontalAlign : "FILL"
	readonly property string verticalAlign: viewActions.config
		? viewActions.config.gridVerticalAlign : "TOP"

	readonly property bool centerFocus: viewActions.config ? viewActions.config.center_focus : true
	readonly property bool smoothScrolling: viewActions.config
		? viewActions.config.smoothScrolling : true
	readonly property bool openOnClick: viewActions.config ? viewActions.config.open_on_click : true
	readonly property bool focusEmptySlots: viewActions.config
		? viewActions.config.focusEmptySlots : false
	readonly property bool freePlacement: viewActions.config
		? viewActions.config.sort === "FREE" && viewActions.config.view_mode === "GRID" : false

	readonly property string wallpaper: viewActions.config ? String(viewActions.config.wallpaper) : ""
	readonly property bool stashShown: viewActions.config ? viewActions.config.show_stash : false
	readonly property bool stashDotfiles: viewActions.config
		? viewActions.config.stash_dotfiles : true

	readonly property bool hasFreePlacementPositions: {
		const cfg = viewActions.config
		if (!cfg)
			return false
		try {
			const positions = JSON.parse(cfg.freePlacementPositions)
			return !!positions && Object.keys(positions).length > 0
		} catch (error) {
			return false
		}
	}

	// ── Writes ───────────────────────────────────────────────────────────
	function setSectionConfig(section, key, value) {
		if (!viewActions.directory)
			return
		viewActions.directory.set_config_scoped(key, value, viewActions.isLocal)
		// The slot has returned, so it is safe to let config bindings re-read
		// the directory now.
		if (viewActions.config)
			viewActions.config.notify()
	}

	function setConfig(key, value) {
		viewActions.setSectionConfig(viewActions.viewConfigGroupName, key, value)
	}

	function setNavigationConfig(key, value) {
		viewActions.setSectionConfig("Folder Navigation", key, value)
	}

	function setViewMode(value) {
		viewActions.setConfig("ViewMode", value)
	}

	function setSort(value) {
		viewActions.setConfig("Sort", value)
	}

	function setGroup(value) {
		viewActions.setConfig("Group", value)
	}

	function resetFreePlacement() {
		if (viewActions.directory)
			viewActions.directory.reset_free_positions()
	}

	function setLineCount(value) {
		const clamped = Math.max(viewActions.lineCountMin,
			Math.min(viewActions.lineCountMax, Math.round(value)))
		viewActions.setConfig("Lines", String(clamped))
	}

	function nudgeLineCount(delta) {
		viewActions.setLineCount(viewActions.lineCount + delta)
	}

	function setGridMode(value) {
		viewActions.setConfig("GridMode", value)
	}

	function setIconSize(value) {
		const clamped = Math.max(16, Math.min(256, Math.round(value)))
		viewActions.setConfig("GridSize", String(clamped))
	}

	// More lines means smaller icons; more icon pixels means a larger grid.
	function nudgeZoom(delta) {
		if (viewActions.isIconSize)
			viewActions.setIconSize(viewActions.iconSize + delta * 8)
		else
			viewActions.setLineCount(viewActions.lineCount + delta)
	}

	function toggleViewMode() {
		viewActions.setViewMode(viewActions.isListView ? "GRID" : "LIST")
	}

	function pathFromUrl(url) {
		let path = String(url)
		if (path.startsWith("file://"))
			path = path.substring(7)
		try {
			return decodeURIComponent(path)
		} catch (error) {
			return path
		}
	}
}
