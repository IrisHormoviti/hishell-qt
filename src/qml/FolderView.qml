import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt
import org.kde.kirigami as Kirigami
import NativeDrag 1.0
import "toolkit"

Kirigami.Page {
	id: pane

	property bool active: false
	property var window: null
	Layout.fillWidth: true
	Layout.fillHeight: true
	padding: 0
	background: Rectangle { color: Kirigami.Theme.backgroundColor }

	signal activated()
	signal focusEdge(string direction)

	property var directory: null

	property var contextActions: []
	property string contextTarget: "location"
	property var contextNewMenu: null
	property var contextViewMenu: null
	property string springPath: ""
	property string dragSourceUris: ""
	property bool springPopupVisible: false
	property string springFolderPath: ""
	property var springFolders: []
	property real springAnchorX: 0
	property real springAnchorY: 0
	property string springNestedPath: ""

	Timer {
		id: springNestedTimer
		interval: 700
		onTriggered: {
			if (pane.springNestedPath.length > 0)
				pane.openSpringFolder(pane.springNestedPath)
		}
	}

	Timer {
		id: springTimer
		interval: 700
		repeat: false
		onTriggered: {
			const target = pane.springPath
			pane.springPath = ""
			if (target.length > 0 && !DragHelper.isSource(target))
				pane.directory.navigate(target)
		}
	}

	function springEnter(path) {
		DragHelper.setSpringTarget(path)
	}

	Connections {
		target: DragHelper
		function onSpringRequested(path) {
			if (pane.springPath !== path) {
				pane.springPath = path
				pane.directory.navigate(path)
			}
		}
	}

	function openSpringFolder(path) {
		let folders = []
		try {
			folders = JSON.parse(pane.directory.folders_json(path))
		} catch (error) {
			folders = []
		}
		if (folders.length === 0)
			return
		pane.springFolderPath = path
		pane.springFolders = folders
		pane.springPopupVisible = true
	}

	function pathFromUri(uri) {
		let path = String(uri)
		if (path.startsWith("file://"))
			path = path.substring(7)
		try {
			return decodeURIComponent(path)
		} catch (error) {
			return path
		}
	}

	function repositionFromDrop(drop) {
		if (pane.spec.free !== true || !pane.directory)
			return false
		if (!drop.urls || drop.urls.length === 0)
			return false
		const source = pane.pathFromUri(drop.urls[0])
		if (!pane.directory.row_visible(source))
			return false
		const name = source.split("/").pop()
		const cw = pane.spec.cell_width || 96
		const ch = pane.spec.cell_height || 96
		const gap = pane.spec.gap || 0
		const column = Math.max(0, Math.round(
			(drop.x - pane.freeOffsetX - cw / 2) / Math.max(1, cw + gap)))
		const row = Math.max(0, Math.round(
			(drop.y - pane.freeOffsetY - ch / 2) / Math.max(1, ch + gap)))
		pane.directory.set_free_position(name, column, row)
		drop.acceptProposedAction()
		return true
	}

	function applyDrop(drop, dest) {
		const uris = drop.urls && drop.urls.length > 0
			? drop.urls.join("\n") : drop.text
		pane.directory.drop(uris, dest, pane.dropAction(drop))
		drop.acceptProposedAction()
		pane.springPopupVisible = false
	}

	function springLeave(path) {
		DragHelper.clearSpringTarget()
		if (pane.springPath === path) {
			springTimer.stop()
			pane.springPath = ""
		}
	}
	property string transitionDirection: ""

	readonly property alias renameDialogOpen: renameDialog.visible
	readonly property alias trashDialogOpen: trashDialog.visible
	readonly property alias openWithDialogOpen: openWithDialog.visible

	function openContextMenu() {
		contextMenu.popup()
	}

	function closeDialogs() {
		renameDialog.close()
		trashDialog.close()
		openWithDialog.close()
	}

	onActiveChanged: if (active) {
		if (spec.free === true || spec.mode === "grid")
			grid.forceActiveFocus()
		else
			list.forceActiveFocus()
	}

	function focusFirst() {
		pane.directory.focus_first()
	}

	function focusLast() {
		pane.directory.focus_last()
	}

	function handleGamepad(action) {
		if (action === "up" || action === "down" || action === "left" || action === "right") {
			if (!pane.directory.move_focus(action) && (action === "left" || action === "right"))
				pane.focusEdge(action)
		} else if (action === "accept") {
			if (pane.directory.focused_path.length > 0)
				pane.directory.open(pane.directory.focused_path)
		} else if (action === "cancel") {
			pane.directory.go_up()
		} else if (action === "menu") {
			contextMenu.popup()
		} else if (action === "select") {
			if (pane.directory.focused_path.length > 0)
				pane.directory.toggle_select(pane.directory.focused_path)
		} else if (action === "directory") {
			pane.directory.select_all()
		}
	}

	function actionLabel(id) {
		const labels = {
			"open": "Open",
			"open-with": "Open With…",
			"navigate": "Navigate",
			"go-up": "Go Up",
			"refresh": "Refresh",
			"select-all": "Select All",
			"new-folder": "New Folder",
			"new-text-file": "New Text File",
			"copy": "Copy",
			"cut": "Cut",
			"paste": "Paste",
			"properties": "Properties",
			"duplicate": "Duplicate",
			"create-link": "Create Link",
			"rename": "Rename…",
			"trash": "Move to Trash…",
			"delete": "Delete…",
			"destroy": "Delete Permanently…",
			"toggle": "Toggle",
			"rotate-image": "Rotate Clockwise"
		}
		return labels[id] || id
	}

	// Drops copy by default; Shift moves and Ctrl+Shift links. Qt's proposed
	// action defaults to move, which used to destroy a file dropped back into
	// its own folder.
	function dropAction(drop) {
		if (drop.proposedAction === Qt.MoveAction)
			return "move"
		if (drop.proposedAction === Qt.LinkAction)
			return "link"
		return "copy"
	}

	function dragUrl(path) {
		return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
	}

	function clickTarget(path, modifiers) {
		const directory = pane.directory
		if (!directory)
			return
		pane.activated()
		directory.focus_path(path)
		if (modifiers & Qt.ControlModifier) {
			directory.toggle_select(path)
		} else if (modifiers & Qt.ShiftModifier) {
			directory.select_range(path)
		} else if (directory.selectionActive) {
			directory.select(path)
		} else if (directory.config.open_on_click) {
			directory.open(path)
		} else {
			directory.select(path)
		}
	}

	function holdTarget(path) {
		const directory = pane.directory
		if (!directory)
			return
		pane.activated()
		directory.focus_path(path)
		directory.select(path)
	}

	function doubleTarget(path) {
		const directory = pane.directory
		if (directory && !directory.config.open_on_click)
			directory.open(path)
	}

	function isFileIcon(source) {
		return source.indexOf("file://") === 0 || source.indexOf("/") === 0
	}

	function focusView() {
		if (pane.spec.free === true || pane.spec.grouped === true)
			absoluteView.forceActiveFocus()
		else if (pane.spec.mode === "grid")
			grid.forceActiveFocus()
		else
			list.forceActiveFocus()
	}

	function handleFilterKey(event) {
		const directory = pane.directory
		if (!directory)
			return false
		const active = String(directory.filter).length > 0
		const control = (event.modifiers
			& (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0

		if (event.key === Qt.Key_Escape) {
			if (!active)
				return false
			directory.clear_filter()
			return true
		}
		if (event.key === Qt.Key_Backspace) {
			if (!active)
				return false
			directory.backspace_filter()
			return true
		}
		if (event.key === Qt.Key_Space && !active)
			return false
		if (control || event.text.length === 0)
			return false
		for (let i = 0; i < event.text.length; i++) {
			const code = event.text.charCodeAt(i)
			if (code < 0x20 || code === 0x7f)
				return false
		}
		directory.append_filter(event.text)
		return true
	}

	function handleKey(event) {
		if (pane.handleFilterKey(event)) {
			event.accepted = true
			return
		}
		if (event.key === Qt.Key_Left) {
			if (!pane.directory.move_focus("left"))
				pane.focusEdge("left")
			event.accepted = true
		} else if (event.key === Qt.Key_Right) {
			if (!pane.directory.move_focus("right"))
				pane.focusEdge("right")
			event.accepted = true
		} else if (event.key === Qt.Key_Up) {
			if (event.modifiers & Qt.AltModifier) {
				pane.directory.go_up()
			} else {
				pane.directory.move_focus("up")
			}
			event.accepted = true
		} else if (event.key === Qt.Key_Down) {
			pane.directory.move_focus("down")
			event.accepted = true
		} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			if (pane.directory.focused_path.length > 0)
				pane.directory.open(pane.directory.focused_path)
			event.accepted = true
		} else if (event.key === Qt.Key_Escape) {
			pane.directory.clear_selection()
			event.accepted = true
		} else if (event.key === Qt.Key_Space) {
			if (pane.directory.focused_path.length > 0)
				pane.directory.toggle_select(pane.directory.focused_path)
			event.accepted = true
		} else if (event.key === Qt.Key_Backspace) {
			pane.directory.go_up()
			event.accepted = true
		}
	}

	Component.onCompleted: if (pane.directory)
		pane.directory.focus_first()


	Connections {
		target: pane.directory
		function onRename_requested(path, suggested) {
			renameDialog.targetPath = path
			renameDialog.originalName = suggested
			renameDialog.open()
		}
		function onTrash_requested(pathsJson, permanent) {
			trashDialog.pathsJson = pathsJson
			trashDialog.permanent = permanent
			trashDialog.open()
		}
		function onProperties_requested(path) {
			propertiesDialog.rows = JSON.parse(pane.directory.properties_json(path))
			propertiesDialog.open()
		}
		function onOpen_with_requested(path) {
			openWithDialog.targetPath = path
			openWithDialog.open()
		}
		function onTransition_requested(planJson) {
			let relation = ""
			try {
				relation = String(JSON.parse(planJson).relation || "")
			} catch (e) {
				relation = ""
			}
			pane.transitionDirection = relation.indexOf("Parent") >= 0 ? "out" : "in"
			folderGrid.opacity = 0.25
			folderGrid.scale = pane.transitionDirection === "out" ? 0.96 : 1.04
			transitionAnimation.restart()
		}
	}

	ParallelAnimation {
		id: transitionAnimation
		NumberAnimation {
			target: folderGrid
			property: "opacity"
			from: 0.25
			to: 1
			duration: 170
		}
		NumberAnimation {
			target: folderGrid
			property: "scale"
			from: pane.transitionDirection === "out" ? 0.96 : 1.04
			to: 1
			duration: 170
			easing.type: Easing.OutCubic
		}
	}

	Dialog {
		id: renameDialog
		property string targetPath: ""
		property string originalName: ""
		modal: true
		title: "Rename"
		standardButtons: Dialog.Ok | Dialog.Cancel
		onOpened: renameField.text = originalName
		onAccepted: {
			if (targetPath.length > 0 && renameField.text.length > 0
					&& renameField.text !== originalName)
				pane.directory.rename(targetPath, renameField.text)
		}

		ColumnLayout {
			anchors.fill: parent
			TextField {
				id: renameField
				Layout.fillWidth: true
			}
		}
	}

	Dialog {
		id: trashDialog
		property string pathsJson: "[]"
		property bool permanent: false
		modal: true
		title: permanent ? "Delete permanently?" : "Move to Trash?"
		standardButtons: Dialog.Ok | Dialog.Cancel
		onAccepted: pane.directory.trash(pathsJson, permanent)

		Label {
			text: permanent ? "This cannot be undone." : "The items can be restored from the trash."
		}
	}

	Dialog {
		id: openWithDialog
		property string targetPath: ""
		property var apps: []
		modal: true
		title: "Open With"
		standardButtons: Dialog.Cancel
		onOpened: apps = JSON.parse(pane.directory.apps_json(targetPath))

		ColumnLayout {
			Repeater {
				model: openWithDialog.apps
				Button {
					required property var modelData
					Layout.fillWidth: true
					text: modelData.name
					onClicked: {
						pane.directory.open_with(openWithDialog.targetPath, modelData.id)
						openWithDialog.close()
					}
				}
			}
		}
	}

	Dialog {
		id: propertiesDialog
		property var rows: []
		modal: true
		title: "Properties"
		standardButtons: Dialog.Close

		ColumnLayout {
			anchors.fill: parent
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Name"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.name || ""; Layout.fillWidth: true; elide: Text.ElideMiddle }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Path"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.path || ""; Layout.fillWidth: true; elide: Text.ElideMiddle }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Type"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.type || ""; Layout.fillWidth: true }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Size"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: pane.formatSize(propertiesDialog.rows.size || 0); Layout.fillWidth: true }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "Modified"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: pane.formatTime(propertiesDialog.rows.modified || 0); Layout.fillWidth: true }
			}
			RowLayout {
				Layout.fillWidth: true
				Label { text: "MIME"; Layout.preferredWidth: 90; font.bold: true }
				Label { text: propertiesDialog.rows.mime || ""; Layout.fillWidth: true }
			}
		}
	}

	Menu {
		id: contextMenu
		onAboutToShow: {
			const background = pane.contextTarget === "location"
			pane.contextActions = JSON.parse(
				pane.directory.actions_json("context", pane.contextTarget))
				.filter(action => background ? action.here : action.items)
			if (background)
				pane.contextActions = pane.contextActions.filter(action =>
					action.id !== "new-folder" && action.id !== "new-text-file")

			if (background) {
				if (!pane.contextNewMenu) {
					pane.contextNewMenu = newMenuComponent.createObject(contextMenu)
					contextMenu.addMenu(pane.contextNewMenu)
				}
				if (!pane.contextViewMenu) {
					pane.contextViewMenu = viewMenuComponent.createObject(contextMenu, {
						"directory": pane.directory,
						"window": pane.window
					})
					contextMenu.addMenu(pane.contextViewMenu)
				}
			} else {
				if (pane.contextNewMenu) {
					contextMenu.removeMenu(pane.contextNewMenu)
					pane.contextNewMenu.destroy()
					pane.contextNewMenu = null
				}
				if (pane.contextViewMenu) {
					contextMenu.removeMenu(pane.contextViewMenu)
					pane.contextViewMenu.destroy()
					pane.contextViewMenu = null
				}
			}
		}

		Component {
			id: newMenuComponent

			Menu {
				title: "New"
				icon.name: "document-new"

				ShellMenuItem {
					text: "New Folder"
					iconName: "folder-new"
					onTriggered: if (pane.directory) pane.directory.invoke("new-folder")
				}
				ShellMenuItem {
					text: "New Text File"
					iconName: "document-new"
					onTriggered: if (pane.directory) pane.directory.invoke("new-text-file")
				}
			}
		}

		Component {
			id: viewMenuComponent

			ViewMenu {}
		}

		Repeater {
			model: pane.contextActions

			ShellMenuItem {
				required property var modelData
				text: pane.actionLabel(modelData.id)
				iconName: modelData.icon || ""
				shortcutText: modelData.shortcut || ""
				enabled: modelData.enabled
				onTriggered: pane.directory.invoke(modelData.id)
			}
		}

		MenuSeparator {}

		ShellMenuItem {
			text: "Open in New Window"
			iconName: "window-new"
			onTriggered: {
				const path = pane.contextTarget === "location"
					? pane.directory.path : pane.directory.focused_path
				if (path.length > 0)
					pane.directory.open_in_new_window(path)
			}
		}
	}

	readonly property var spec: {
		if (!pane.directory)
			return ({})
		pane.directory.revision
		return JSON.parse(pane.directory.view_json(content.width, content.height, 18, 4, 18))
	}

	readonly property string horizontalAlign: pane.directory
		? String(pane.directory.config.gridHorizontalAlign) : "FILL"
	readonly property string verticalAlign: pane.directory
		? String(pane.directory.config.gridVerticalAlign) : "TOP"

	// Fill and Center both centre the block between the free space; Left and
	// Top pin it to the start, Right and Bottom to the end.
	function alignOffset(align, view, natural) {
		if (align === "LEFT" || align === "TOP")
			return 0
		if (align === "RIGHT" || align === "BOTTOM")
			return Math.max(0, view - natural)
		return Math.max(0, (view - natural) / 2)
	}

	readonly property int gridLineCount: pane.spec.lines || 4
	readonly property int gridCount: pane.spec.count || 0
	readonly property real gridGap: pane.spec.gap || 0
	readonly property real naturalWidth: {
		const pitch = (pane.spec.cell_width || 96) + pane.gridGap
		if (pane.spec.horizontal)
			return Math.ceil(pane.gridCount / Math.max(1, pane.gridLineCount)) * pitch
		return pane.gridLineCount * pitch
	}
	readonly property real naturalHeight: {
		const pitch = (pane.spec.cell_height || 96) + pane.gridGap
		if (pane.spec.horizontal)
			return pane.gridLineCount * pitch
		return Math.ceil(pane.gridCount / Math.max(1, pane.gridLineCount)) * pitch
	}
	readonly property real gridOffsetX: pane.alignOffset(pane.horizontalAlign,
		content.width, pane.naturalWidth)
	readonly property real gridOffsetY: pane.alignOffset(pane.verticalAlign,
		content.height, pane.naturalHeight)
	readonly property real freeNaturalWidth: {
		let width = 0
		for (const slot of pane.spec.slots || [])
			width = Math.max(width, slot.x + slot.width)
		return width
	}
	readonly property real freeNaturalHeight: {
		let height = 0
		for (const slot of pane.spec.slots || [])
			height = Math.max(height, slot.y + slot.height)
		return height
	}
	readonly property real freeOffsetX: pane.alignOffset(pane.horizontalAlign,
		content.width, pane.freeNaturalWidth)
	readonly property real freeOffsetY: pane.alignOffset(pane.verticalAlign,
		content.height, pane.freeNaturalHeight)
	readonly property bool filterActive: pane.directory
		? String(pane.directory.filter).length > 0 : false

	readonly property bool showLabels: pane.directory
		? pane.directory.config.show_labels : true
	readonly property bool labelsBeside: pane.directory
		? pane.directory.config.gridLabelsBesidesIcons : false
	readonly property string labelText: pane.directory
		? String(pane.directory.config.label_text) : "TITLE"

	function displayName(name, title) {
		return pane.labelText === "TITLE" && title.length > 0 ? title : name
	}

	readonly property var listColumns: {
		const columns = pane.spec.columns
		return columns && columns.length > 0 ? columns : ["TITLE"]
	}

	function isFillColumn(key) {
		return key === "TITLE" || key === "FILENAME"
	}

	function columnLabel(key) {
		const labels = {
			"TITLE": "Title",
			"FILENAME": "File Name",
			"SIZE": "Size",
			"MODIFIED": "Date Modified",
			"CREATED": "Date Created",
			"ACCESSED": "Date Accessed",
			"TYPE": "Type"
		}
		return labels[key] || key
	}

	function columnWidth(key) {
		if (key === "SIZE")
			return 80
		if (key === "MODIFIED" || key === "CREATED" || key === "ACCESSED")
			return 140
		if (key === "TYPE")
			return 110
		return -1
	}

	function formatSize(bytes) {
		if (!(bytes > 0))
			return ""
		const units = ["B", "kB", "MB", "GB", "TB"]
		let value = Number(bytes)
		let unit = 0
		while (value >= 1024 && unit < units.length - 1) {
			value /= 1024
			unit += 1
		}
		return unit === 0 ? value + " " + units[unit]
			: value.toFixed(value >= 10 ? 0 : 1) + " " + units[unit]
	}

	function formatTime(milliseconds) {
		if (!(milliseconds > 0))
			return ""
		return Qt.formatDateTime(new Date(Number(milliseconds)), "yyyy-MM-dd HH:mm")
	}

	function columnText(key, row) {
		if (key === "TITLE")
			return row.title.length > 0 ? row.title : row.name
		if (key === "FILENAME")
			return row.name
		if (key === "SIZE")
			return row.is_directory ? "" : pane.formatSize(row.size_bytes)
		if (key === "MODIFIED")
			return pane.formatTime(row.modified_time)
		if (key === "CREATED")
			return pane.formatTime(row.created_time)
		if (key === "ACCESSED")
			return pane.formatTime(row.accessed_time)
		if (key === "TYPE")
			return row.is_directory ? "Folder" : (row.mime.length > 0 ? row.mime : "File")
		return ""
	}

	readonly property string wallpaperUrl: {
		const path = pane.directory ? String(pane.directory.config.wallpaper) : ""
		if (path.length === 0)
			return ""
		return "file://" + path.split("/").map(encodeURIComponent).join("/")
	}

	FolderGrid {
		anchors.fill: parent
		pane: pane
		filterHeight: filterBar.height
	}

	FolderFilterBar {
		id: filterBar
		directory: pane.directory
		matchCount: pane.directory ? pane.directory.matchCount : 0
		filterActive: folderGrid.filterActive
		window: pane.window
		onFocusRequested: folderGrid.focusView()
		onClearRequested: {
			if (pane.directory)
				pane.directory.clear_filter()
			pane.focusView()
		}
	}

	FolderSelectionBar {
		directory: pane.directory
		window: pane.window
	}
}
