import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "toolkit"

// The old ShellContextMenu, sourced from the same directory/action queries as
// the original: background menus carry the Here actions, New and View; item
// menus carry the item actions plus the target-specific groups.
WideMenu {
	id: contextMenu

	// Take the keyboard while open so the controller and the arrow keys drive
	// the menu instead of the view behind it.
	focus: true

	property var directory: null
	property var window: null
	property bool targetIsDir: false
	property bool targetIsImage: false
	property bool targetIsBackground: false

	property var actions: []
	property var mainActions: []
	property var extraActions: []
	property var newMenu: null
	property var viewMenu: null

	function playSound(name) {
		if (contextMenu.directory)
			contextMenu.directory.play_sound(name)
	}
	onOpened: playSound("menu-open")
	onClosed: playSound("menu-close")

	function reload() {
		if (!contextMenu.directory) {
			contextMenu.actions = []
			return
		}
		const target = contextMenu.targetIsBackground ? "location" : "focus"
		let list = []
		try {
			list = JSON.parse(contextMenu.directory.actions_json("context", target))
		} catch (error) {
			list = []
		}
		if (contextMenu.targetIsBackground) {
			// The old folder menu carried Edit Path, Refresh and Paste.
			list = list.filter(action => action.here
				&& (action.id === "refresh" || action.id === "paste"))
			list.unshift({
				"id": "__edit-path",
				"enabled": true,
				"visible": true,
				"checked": false,
				"icon": "edit-rename",
				"shortcut": "Ctrl+L"
			})
			const order = ["__edit-path", "refresh", "paste"]
			list.sort((first, second) =>
				order.indexOf(first.id) - order.indexOf(second.id))
		} else {
			list = list.filter(action => action.items)
			// Quit only applies to a running application item.
			list = list.filter(action => action.id !== "quit-active"
				|| (contextMenu.directory
					&& contextMenu.directory.is_item_active(
						contextMenu.directory.focused_path)))
			// A folder's Open and Navigate do the same thing; keep the
			// navigation action that the view actually uses.
			if (contextMenu.targetIsDir)
				list = list.filter(action => action.id !== "open"
					&& action.id !== "open-with")
			// The old Open group put Open in Window beside Open and Open With,
			// before the edit/danger groups.
			const openWindow = {
				"id": "__open-window",
				"enabled": contextMenu.directory.focused_path.length > 0,
				"visible": true,
				"checked": false,
				"icon": "window-new-symbolic",
				"shortcut": "Ctrl+N"
			}
			const openWith = list.findIndex(action => action.id === "open-with")
			list.splice(openWith >= 0 ? openWith + 1 : 0, 0, openWindow)
		}
		contextMenu.actions = list
		const extraIds = ["rotate-image", "toggle", "number", "radio"]
		contextMenu.extraActions = list.filter(action => extraIds.indexOf(action.id) !== -1)
		contextMenu.mainActions = list.filter(action => extraIds.indexOf(action.id) === -1)
	}

	onAboutToShow: {
		contextMenu.reload()

		if (contextMenu.targetIsBackground) {
			if (!contextMenu.newMenu) {
				contextMenu.newMenu = newMenuComponent.createObject(contextMenu)
				contextMenu.addMenu(contextMenu.newMenu)
			}
			if (!contextMenu.viewMenu) {
				contextMenu.viewMenu = viewMenuComponent.createObject(contextMenu, {
					"directory": contextMenu.directory,
					"window": contextMenu.window
				})
				contextMenu.addMenu(contextMenu.viewMenu)
			}
		} else {
			if (contextMenu.newMenu) {
				contextMenu.removeMenu(contextMenu.newMenu)
				contextMenu.newMenu.destroy()
				contextMenu.newMenu = null
			}
			if (contextMenu.viewMenu) {
				contextMenu.removeMenu(contextMenu.viewMenu)
				contextMenu.viewMenu.destroy()
				contextMenu.viewMenu = null
			}
		}
	}

	Repeater {
		model: contextMenu.mainActions

		SpacedMenuItem {
			id: mainEntry
			required property var modelData
			action: Action {
				text: mainEntry.modelData.id === "__open-window"
					? (contextMenu.window
						? contextMenu.window.actionLabel("open-window") : "Open in Window")
					: mainEntry.modelData.id === "__edit-path" ? "Edit Path"
					: (contextMenu.window
						? contextMenu.window.actionLabel(mainEntry.modelData.id)
						: mainEntry.modelData.id)
				icon.name: mainEntry.modelData.icon || ""
				shortcut: mainEntry.modelData.shortcut || ""
				enabled: mainEntry.modelData.enabled
				onTriggered: {
					contextMenu.playSound("menu-item")
					if (mainEntry.modelData.id === "__edit-path") {
						const bar = contextMenu.window
							? contextMenu.window.headerPathBar : null
						if (bar && bar.startEditing)
							bar.startEditing()
					} else if (mainEntry.modelData.id === "__open-window") {
						const path = contextMenu.directory.focused_path
						if (path.length > 0)
							contextMenu.directory.open_in_new_window(path)
					} else if (mainEntry.modelData.id === "navigate") {
						const pane = contextMenu.window
							? contextMenu.window.activePane : null
						const path = contextMenu.directory.focused_path
						if (pane && pane.navigateTo && path.length > 0)
							pane.navigateTo(path)
						else
							contextMenu.directory.invoke(mainEntry.modelData.id)
					} else {
						contextMenu.directory.invoke(mainEntry.modelData.id)
					}
				}
			}
		}
	}

	MenuSeparator { visible: contextMenu.extraActions.length > 0 }

	Repeater {
		model: contextMenu.extraActions

		SpacedMenuItem {
			id: extraEntry
			required property var modelData
			action: Action {
				text: contextMenu.window
					? contextMenu.window.actionLabel(extraEntry.modelData.id)
					: extraEntry.modelData.id
				icon.name: extraEntry.modelData.icon || ""
				shortcut: extraEntry.modelData.shortcut || ""
				enabled: extraEntry.modelData.enabled
				onTriggered: {
					contextMenu.playSound("menu-item")
					contextMenu.directory.invoke(extraEntry.modelData.id)
				}
			}
		}
	}

	MenuSeparator {}

	Component {
		id: newMenuComponent

		WideMenu {
			title: "New"
			icon.name: "document-new"

			SpacedMenuItem {
				text: "New Folder"
				icon.name: "folder-new"
				onTriggered: {
					contextMenu.playSound("menu-item")
					if (contextMenu.directory)
						contextMenu.directory.invoke("new-folder")
				}
			}
			SpacedMenuItem {
				text: "New Text File"
				icon.name: "document-new"
				onTriggered: {
					contextMenu.playSound("menu-item")
					if (contextMenu.directory)
						contextMenu.directory.invoke("new-text-file")
				}
			}
		}
	}

	Component {
		id: viewMenuComponent

		WideMenu {
			id: viewMenu

			property var directory: contextMenu.directory
			property var window: contextMenu.window
			property bool viewLocal: viewMenu.directory
				? viewMenu.directory.has_meta() : false
			property string scopePath: ""
			readonly property var config: viewMenu.directory
				? viewMenu.directory.config : null
			readonly property bool showShortcuts: viewMenu.config
				? viewMenu.config.show_shortcuts : true

			function playSound(name) {
				if (viewMenu.directory)
					viewMenu.directory.play_sound(name)
			}

			function setViewConfig(key, value) {
				if (viewMenu.directory)
					viewMenu.directory.set_config_scoped(key, value, viewMenu.viewLocal)
			}

			function zoomView(delta) {
				if (!viewMenu.directory)
					return
				if (String(viewMenu.directory.config.grid_mode) === "SIZE") {
					const size = Math.max(16, Math.min(256,
						viewMenu.directory.config.grid_size + delta * 8))
					viewMenu.setViewConfig("grid_size", String(size))
				} else {
					const lines = Math.max(1, Math.min(8,
						viewMenu.directory.config.grid_lines - delta))
					viewMenu.setViewConfig("grid_lines", String(lines))
				}
			}

			function openViewOptions() {
				const bar = viewMenu.window ? viewMenu.window.headerPathBar : null
				if (bar && bar.openConfigure)
					bar.openConfigure("view")
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

			readonly property bool isIconSize: config
				? config.grid_mode === "SIZE" : false
			readonly property bool listMode: config
				? config.view_mode === "LIST" : false
			readonly property bool scrollHorizontal: config
				? config.scrollHorizontal === "HORIZONTAL" : false
			readonly property bool freePlacement: config
				? config.sort === "FREE" && config.view_mode === "GRID" : false
			readonly property bool customGroups: config
				? config.group_mode === "CUSTOM" : false
			readonly property bool hasFreePlacementPositions: {
				if (!viewMenu.config)
					return false
				try {
					const parsed = JSON.parse(String(
						viewMenu.config.free_placement_positions))
					return parsed && typeof parsed === "object"
						&& Object.keys(parsed).length > 0
				} catch (error) {
					return false
				}
			}
			readonly property int lineCount: config
				? Math.max(1, Math.min(8, config.grid_lines > 0 ? config.grid_lines : 4)) : 4
			readonly property string lineCountLabel: viewMenu.scrollHorizontal
				? "Rows" : "Columns"
			readonly property var availableListColumns: [
				{ "key": "TITLE", "label": "Title" },
				{ "key": "FILENAME", "label": "File Name" },
				{ "key": "COMMENT", "label": "Comment" },
				{ "key": "SIZE", "label": "Size" },
				{ "key": "MODIFIED", "label": "Date Modified" },
				{ "key": "CREATED", "label": "Date Created" },
				{ "key": "ACCESSED", "label": "Date Accessed" },
				{ "key": "TYPE", "label": "Type" }
			]

			function isNameColumn(key) {
				return key === "TITLE" || key === "FILENAME"
			}

			function normalizeListColumns(values) {
				const known = {}
				for (const column of viewMenu.availableListColumns)
					known[column.key] = true
				const seen = {}
				const result = []
				for (const value of values || []) {
					const key = String(value).toUpperCase()
					if (!known[key] || seen[key])
						continue
					seen[key] = true
					result.push(key)
				}
				if (!result.some(viewMenu.isNameColumn))
					result.unshift("TITLE")
				return result
			}

			readonly property var listColumns: {
				if (!viewMenu.config)
					return viewMenu.normalizeListColumns([])
				let parsed = []
				try {
					parsed = JSON.parse(String(viewMenu.config.list_columns))
				} catch (error) {
					parsed = []
				}
				return viewMenu.normalizeListColumns(
					Array.isArray(parsed) ? parsed : [])
			}

			readonly property var listColumnMenuOrder: {
				const shown = viewMenu.listColumns.slice()
				const seen = {}
				for (const key of shown)
					seen[key] = true
				const hidden = []
				for (const column of viewMenu.availableListColumns) {
					if (!seen[column.key])
						hidden.push(column.key)
				}
				return shown.concat(hidden)
			}

			function listColumnLabel(key) {
				for (const column of viewMenu.availableListColumns) {
					if (column.key === key)
						return column.label
				}
				return key
			}

			function hasListColumn(key) {
				return viewMenu.listColumns.indexOf(key) !== -1
			}

			function setListColumns(columns) {
				viewMenu.setViewConfig("list_columns",
					JSON.stringify(viewMenu.normalizeListColumns(columns)))
			}

			function setListColumnVisible(key, visible) {
				const columns = viewMenu.listColumns.slice()
				const index = columns.indexOf(key)
				if (visible && index === -1) {
					columns.push(key)
				} else if (!visible && index !== -1) {
					const nameColumns = columns.filter(viewMenu.isNameColumn)
					if (viewMenu.isNameColumn(key) && nameColumns.length === 1)
						columns[index] = key === "TITLE" ? "FILENAME" : "TITLE"
					else
						columns.splice(index, 1)
				} else {
					return
				}
				viewMenu.setListColumns(columns)
			}

			function moveListColumn(key, delta) {
				const columns = viewMenu.listColumns.slice()
				const index = columns.indexOf(key)
				const target = index + delta
				if (index < 0 || target < 0 || target >= columns.length)
					return
				columns.splice(index, 1)
				columns.splice(target, 0, key)
				viewMenu.setListColumns(columns)
			}

			function canMoveListColumn(key, delta) {
				const index = viewMenu.listColumns.indexOf(key)
				const target = index + delta
				return index !== -1 && target >= 0 && target < viewMenu.listColumns.length
			}

			ButtonGroup { id: scopeGroup; exclusive: true }
			ButtonGroup { id: viewModeGroup; exclusive: true }
			ButtonGroup { id: columnCountGroup; exclusive: true }
			ButtonGroup { id: sortGroup; exclusive: true }
			ButtonGroup { id: groupGroup; exclusive: true }
			ButtonGroup { id: hAlignGroup; exclusive: true }
			ButtonGroup { id: vAlignGroup; exclusive: true }
			title: "&View"
			onOpened: {
				const path = viewMenu.directory ? String(viewMenu.directory.path) : ""
				if (viewMenu.scopePath !== path) {
					viewMenu.scopePath = path
					viewMenu.viewLocal = viewMenu.directory
						? viewMenu.directory.has_meta() : false
				}
				viewMenu.playSound("menu-open")
			}
			onClosed: viewMenu.playSound("menu-close")

				SpacedMenuItem {
					text: "General"
					checkable: true
					checked: !viewMenu.viewLocal
					ButtonGroup.group: scopeGroup
					onTriggered: viewMenu.viewLocal = false
				}
				SpacedMenuItem {
					text: "Here"
					checkable: true
					checked: viewMenu.viewLocal
					ButtonGroup.group: scopeGroup
					onTriggered: viewMenu.viewLocal = true
				}
				SpacedMenuItem {
					text: "View Options…"
					icon.name: "view-choose"
					onTriggered: {
						playSound("menu-item")
						viewMenu.openViewOptions()
					}
				}
				SpacedMenuItem {
					text: viewMenu.isIconSize ? "Size by Lines" : "Size by Icon Size"
					icon.name: viewMenu.isIconSize ? "view-grid" : "zoom-fit-best"
					onTriggered: viewMenu.setViewConfig("grid_mode",
						viewMenu.isIconSize ? "LINES" : "SIZE")
				}
				WideMenu {
					title: viewMenu.isIconSize ? "Icon Size" : viewMenu.lineCountLabel
					icon.name: viewMenu.isIconSize ? "zoom-fit-best" : "view-grid"

					Repeater {
						model: viewMenu.isIconSize
							? [16, 24, 32, 48, 64, 72, 96, 128, 192, 256]
							: [1, 2, 3, 4, 5, 6, 7, 8]

						SpacedMenuItem {
							required property int modelData
							text: String(modelData)
							checkable: true
							ButtonGroup.group: columnCountGroup
							checked: viewMenu.isIconSize
								? config && config.grid_size === modelData
								: viewMenu.lineCount === modelData
							onTriggered: viewMenu.setViewConfig(
								viewMenu.isIconSize ? "grid_size" : "grid_lines",
								String(modelData))
						}
					}
				}
				MenuSeparator {}
				SpacedMenuItem {
					action: Action {
						text: "Zoom In"
						icon.name: "zoom-in"
						shortcut: viewMenu.showShortcuts ? "Ctrl+=" : ""
						onTriggered: viewMenu.zoomView(1)
					}
				}
				SpacedMenuItem {
					action: Action {
						text: "Zoom Out"
						icon.name: "zoom-out"
						shortcut: viewMenu.showShortcuts ? "Ctrl+-" : ""
						onTriggered: viewMenu.zoomView(-1)
					}
				}
				MenuSeparator {}
				SpacedMenuItem {
					text: "Grid View"
					icon.name: "view-grid"
					checkable: true
					ButtonGroup.group: viewModeGroup
					checked: config && config.view_mode === "GRID"
					onTriggered: if (directory)
						viewMenu.setViewConfig("view_mode", "GRID")
				}
				SpacedMenuItem {
					text: "List View"
					icon.name: "view-list-details"
					checkable: true
					ButtonGroup.group: viewModeGroup
					checked: config && config.view_mode === "LIST"
					onTriggered: if (directory)
						viewMenu.setViewConfig("view_mode", "LIST")
				}
				WideMenu {
					title: "List Columns"
					icon.name: "view-list-details"
					enabled: viewMenu.listMode

					SpacedMenuItem {
						text: "Show Header"
						icon.name: "view-list-header"
						checkable: true
						checked: config && config.list_header
						onTriggered: viewMenu.setViewConfig("list_header",
							config && config.list_header ? "false" : "true")
					}
					MenuSeparator {}
					Repeater {
						model: viewMenu.listColumnMenuOrder

						SpacedMenuItem {
							id: listColumnItem
							required property string modelData
							readonly property bool shown: viewMenu.hasListColumn(modelData)
							text: viewMenu.listColumnLabel(modelData)
							onTriggered: viewMenu.setListColumnVisible(modelData, !shown)

							contentItem: RowLayout {
								spacing: Kirigami.Units.smallSpacing

								Label {
									Layout.preferredWidth: Kirigami.Units.gridUnit
									horizontalAlignment: Text.AlignHCenter
									text: listColumnItem.shown ? "✓" : ""
									color: Kirigami.Theme.highlightColor
									font.bold: true
								}
								Label {
									Layout.fillWidth: true
									text: listColumnItem.text
								}
								ToolButton {
									icon.name: "go-up"
									display: AbstractButton.IconOnly
									enabled: viewMenu.canMoveListColumn(
										listColumnItem.modelData, -1)
									ToolTip.text: "Move left"
									ToolTip.visible: hovered
									onClicked: viewMenu.moveListColumn(
										listColumnItem.modelData, -1)
								}
								ToolButton {
									icon.name: "go-down"
									display: AbstractButton.IconOnly
									enabled: viewMenu.canMoveListColumn(
										listColumnItem.modelData, 1)
									ToolTip.text: "Move right"
									ToolTip.visible: hovered
									onClicked: viewMenu.moveListColumn(
										listColumnItem.modelData, 1)
								}
							}
						}
					}
				}
				MenuSeparator {}
				WideMenu {
					title: "Sort By…"
					icon.name: "view-sort-ascending"
					SpacedMenuItem {
						text: "Newest"
						checkable: true
						ButtonGroup.group: sortGroup
						checked: config && config.sort === "NEWEST"
						onTriggered: if (directory)
							viewMenu.setViewConfig("sort", "NEWEST")
					}
					SpacedMenuItem {
						text: "Oldest"
						checkable: true
						ButtonGroup.group: sortGroup
						checked: config && config.sort === "OLDEST"
						onTriggered: if (directory)
							viewMenu.setViewConfig("sort", "OLDEST")
					}
					WideMenu {
						title: "Which date…"
						icon.name: "appointment-new"
						SpacedMenuItem {
							text: "Modified"
							checkable: true
							checked: config && config.sort_date_mode === "MODIFIED"
							onTriggered: if (directory)
								viewMenu.setViewConfig("sort_date_mode", "MODIFIED")
						}
						SpacedMenuItem {
							text: "Created"
							checkable: true
							checked: config && config.sort_date_mode === "CREATED"
							onTriggered: if (directory)
								viewMenu.setViewConfig("sort_date_mode", "CREATED")
						}
						SpacedMenuItem {
							text: "Accessed"
							checkable: true
							checked: config && config.sort_date_mode === "ACCESSED"
							onTriggered: if (directory)
								viewMenu.setViewConfig("sort_date_mode", "ACCESSED")
						}
					}
					MenuSeparator {}
					SpacedMenuItem {
						text: "Alphabetical"
						checkable: true
						ButtonGroup.group: sortGroup
						checked: config && config.sort === "ALPHABETICAL"
						onTriggered: if (directory)
							viewMenu.setViewConfig("sort", "ALPHABETICAL")
					}
					WideMenu {
						title: "Which name…"
						icon.name: "insert-text"
						SpacedMenuItem {
							text: "Title"
							checkable: true
							checked: config && config.sort_alpha_mode === "TITLES"
							onTriggered: if (directory)
								viewMenu.setViewConfig("sort_alpha_mode", "TITLES")
						}
						SpacedMenuItem {
							text: "File Name"
							checkable: true
							checked: config && config.sort_alpha_mode === "FILENAMES"
							onTriggered: if (directory)
								viewMenu.setViewConfig("sort_alpha_mode", "FILENAMES")
						}
					}
					MenuSeparator {}
					SpacedMenuItem {
						text: "Free Placement"
						checkable: true
						ButtonGroup.group: sortGroup
						visible: !viewMenu.listMode
						enabled: viewMenu.viewLocal && !viewMenu.customGroups
						checked: config && config.sort === "FREE"
						onTriggered: if (directory)
							viewMenu.setViewConfig("sort", "FREE")
					}
					SpacedMenuItem {
						text: "Reset Manual Placement"
						icon.name: "edit-reset"
						visible: !viewMenu.listMode
						enabled: viewMenu.hasFreePlacementPositions
						onTriggered: {
							if (directory)
								directory.reset_free_positions()
							viewMenu.playSound("dialog-ok")
						}
					}
				}
				WideMenu {
					title: "Group By…"
					icon.name: "view-group"
					enabled: !viewMenu.freePlacement && !viewMenu.customGroups
					SpacedMenuItem {
						text: "None"
						checkable: true
						ButtonGroup.group: groupGroup
						checked: config && config.group_mode === "NONE"
						onTriggered: if (directory)
							viewMenu.setViewConfig("group_mode", "NONE")
					}
					SpacedMenuItem {
						text: "Date"
						checkable: true
						ButtonGroup.group: groupGroup
						checked: config && config.group_mode === "DATE"
						onTriggered: if (directory)
							viewMenu.setViewConfig("group_mode", "DATE")
					}
					SpacedMenuItem {
						text: "Letters"
						checkable: true
						ButtonGroup.group: groupGroup
						checked: config && config.group_mode === "LETTERS"
						onTriggered: if (directory)
							viewMenu.setViewConfig("group_mode", "LETTERS")
					}
					SpacedMenuItem {
						text: "Type"
						checkable: true
						ButtonGroup.group: groupGroup
						checked: config && config.group_mode === "TYPE"
						onTriggered: if (directory)
							viewMenu.setViewConfig("group_mode", "TYPE")
					}
				}
				WideMenu {
					title: "Labels"
					icon.name: "label"
					SpacedMenuItem {
						text: "Show Labels"
						checkable: true
						checked: config && config.show_labels
						onTriggered: if (directory)
							viewMenu.setViewConfig("show_labels",
								config.show_labels ? "false" : "true")
					}
					SpacedMenuItem {
						text: "Labels Beside Icons"
						checkable: true
						enabled: config && config.show_labels
						checked: config && config.gridLabelsBesidesIcons
						onTriggered: if (directory)
							viewMenu.setViewConfig("grid_labels_beside_icons",
								config.gridLabelsBesidesIcons ? "false" : "true")
					}
					SpacedMenuItem {
						text: "Show Titles"
						checkable: true
						enabled: config && config.show_labels
						checked: config && config.label_text === "TITLE"
						onTriggered: if (directory)
							viewMenu.setViewConfig("label_text", "TITLE")
					}
					SpacedMenuItem {
						text: "Show File Names"
						checkable: true
						enabled: config && config.show_labels
						checked: config && config.label_text === "FILENAME"
						onTriggered: if (directory)
							viewMenu.setViewConfig("label_text",
								config.label_text === "FILENAME" ? "TITLE" : "FILENAME")
					}
				}
				WideMenu {
					title: "Arrange"
					icon.name: "transform-move"
					WideMenu {
						title: "Scroll Direction"
						icon.name: "go-next"
						SpacedMenuItem {
							text: "Vertical"
							checkable: true
							checked: config && !viewMenu.scrollHorizontal
							onTriggered: if (directory)
								viewMenu.setViewConfig("scroll_direction", "VERTICAL")
						}
						SpacedMenuItem {
							text: "Horizontal"
							checkable: true
							checked: config && viewMenu.scrollHorizontal
							onTriggered: if (directory)
								viewMenu.setViewConfig("scroll_direction", "HORIZONTAL")
						}
					}
					WideMenu {
						title: "Horizontal Align"
						SpacedMenuItem { text: "Fill"; checkable: true
						ButtonGroup.group: hAlignGroup
							checked: config && config.gridHorizontalAlign === "FILL"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_horizontal_align", "FILL") }
						SpacedMenuItem { text: "Left"; checkable: true
						ButtonGroup.group: hAlignGroup
							checked: config && config.gridHorizontalAlign === "LEFT"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_horizontal_align", "LEFT") }
						SpacedMenuItem { text: "Center"; checkable: true
						ButtonGroup.group: hAlignGroup
							checked: config && config.gridHorizontalAlign === "CENTER"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_horizontal_align", "CENTER") }
						SpacedMenuItem { text: "Right"; checkable: true
						ButtonGroup.group: hAlignGroup
							checked: config && config.gridHorizontalAlign === "RIGHT"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_horizontal_align", "RIGHT") }
					}
					WideMenu {
						title: "Vertical Align"
						SpacedMenuItem { text: "Fill"; checkable: true
						ButtonGroup.group: vAlignGroup
							checked: config && config.gridVerticalAlign === "FILL"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_vertical_align", "FILL") }
						SpacedMenuItem { text: "Top"; checkable: true
						ButtonGroup.group: vAlignGroup
							checked: config && config.gridVerticalAlign === "TOP"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_vertical_align", "TOP") }
						SpacedMenuItem { text: "Center"; checkable: true
						ButtonGroup.group: vAlignGroup
							checked: config && config.gridVerticalAlign === "CENTER"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_vertical_align", "CENTER") }
						SpacedMenuItem { text: "Bottom"; checkable: true
						ButtonGroup.group: vAlignGroup
							checked: config && config.gridVerticalAlign === "BOTTOM"
							onTriggered: if (directory) viewMenu.setViewConfig("grid_vertical_align", "BOTTOM") }
					}
				}
				WideMenu {
					title: "Navigation"
					icon.name: "transform-move"
					SpacedMenuItem {
						text: "Smooth Scrolling"
						checkable: true
						checked: config && config.smoothScrolling
						onTriggered: if (directory)
							viewMenu.setViewConfig("smooth_scrolling",
								config.smoothScrolling ? "false" : "true")
					}
					SpacedMenuItem {
						text: "Open on Click"
						checkable: true
						checked: config && config.open_on_click
						onTriggered: if (directory)
							viewMenu.setViewConfig("open_on_click",
								config.open_on_click ? "false" : "true")
					}
					SpacedMenuItem {
						text: "Focus Empty Slots"
						checkable: true
						enabled: viewMenu.freePlacement
						checked: config && config.focusEmptySlots
						onTriggered: if (directory)
							viewMenu.setViewConfig("focus_empty_slots",
								config.focusEmptySlots ? "false" : "true")
					}
				}
				WideMenu {
					title: "Wallpaper"
					icon.name: "preferences-desktop-wallpaper"
					SpacedMenuItem {
						text: "Set Wallpaper…"
						icon.name: "document-open"
						onTriggered: wallpaperDialog.open()
					}
					SpacedMenuItem {
						text: "Clear Wallpaper"
						icon.name: "edit-clear"
						enabled: config && String(config.wallpaper).length > 0
						onTriggered: viewMenu.setViewConfig("wallpaper", "")
					}
				}
				WideMenu {
					title: "Stash"
					icon.name: "user-trash"
					SpacedMenuItem {
						text: "Show Stash"
						checkable: true
						checked: config && config.show_stash
						onTriggered: if (directory)
							viewMenu.setViewConfig("show_stash",
								config.show_stash ? "false" : "true")
					}
					SpacedMenuItem {
						text: "Stash Dotfiles"
						checkable: true
						checked: config && config.stash_dotfiles
						onTriggered: if (directory)
							viewMenu.setViewConfig("stash_dotfiles",
								config.stash_dotfiles ? "false" : "true")
					}
				}

			FileDialog {
				id: wallpaperDialog
				title: "Choose Wallpaper"
				nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.gif *.svg)",
					"All files (*)"]
				onAccepted: viewMenu.setViewConfig("wallpaper",
					viewMenu.pathFromUrl(wallpaperDialog.selectedFile))
			}
		}
	}



	WideMenu {
		title: "Configure"
		icon.name: "preferences-system"
		visible: contextMenu.targetIsBackground

		SpacedMenuItem {
			text: "Layout…"
			icon.name: "view-list-details"
			onTriggered: if (contextMenu.window && contextMenu.window.headerPathBar)
				contextMenu.window.headerPathBar.openConfigure("layout")
		}
		SpacedMenuItem {
			text: "Window…"
			icon.name: "preferences-system-windows"
			onTriggered: if (contextMenu.window && contextMenu.window.headerPathBar)
				contextMenu.window.headerPathBar.openConfigure("window")
		}
		SpacedMenuItem {
			text: "Folder…"
			icon.name: "folder"
			onTriggered: if (contextMenu.window && contextMenu.window.headerPathBar)
				contextMenu.window.headerPathBar.openConfigure("folder")
		}
		SpacedMenuItem {
			text: "Radio…"
			icon.name: "radio-checked"
			onTriggered: if (contextMenu.window && contextMenu.window.headerPathBar)
				contextMenu.window.headerPathBar.openConfigure("radio")
		}
		SpacedMenuItem {
			text: "Launch…"
			icon.name: "system-run"
			onTriggered: if (contextMenu.window && contextMenu.window.headerPathBar)
				contextMenu.window.headerPathBar.openConfigure("launch")
		}
	}

}
