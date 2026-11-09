import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt
import org.kde.kirigami as Kirigami
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
	property string dragPath: ""
	property bool dragActive: false

	Timer {
		id: springTimer
		interval: 700
		repeat: false
		onTriggered: {
			const target = pane.springPath
			pane.springPath = ""
			if (target.length > 0 && target !== pane.dragPath)
				pane.directory.navigate(target)
		}
	}

	function springEnter(path) {
		// Hovering the folder being dragged must not spring-load into itself.
		if (path === pane.dragPath)
			return
		if (pane.springPath === path)
			return
		pane.springPath = path
		springTimer.restart()
	}

	function beginDrag(path, uris, image) {
		pane.dragPath = path
		pane.dragActive = true
		dragSource.Drag.mimeData = ({ "text/uri-list": uris })
		dragSource.Drag.imageSource = image
		dragSource.Drag.active = true
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


	function springLeaveAll() {
		springTimer.stop()
		pane.springPath = ""
	}

	function springLeave(path) {
		if (pane.springPath === path) {
			springTimer.stop()
			pane.springPath = ""
		}
	}
	property string transitionDirection: ""

	readonly property alias renameDialogOpen: renameDialog.visible
	readonly property alias trashDialogOpen: trashDialog.visible
	readonly property alias openWithDialogOpen: openWithDialog.visible

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
			content.opacity = 0.25
			content.scale = pane.transitionDirection === "out" ? 0.96 : 1.04
			transitionAnimation.restart()
		}
	}

	ParallelAnimation {
		id: transitionAnimation
		NumberAnimation {
			target: content
			property: "opacity"
			from: 0.25
			to: 1
			duration: 170
		}
		NumberAnimation {
			target: content
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

	Frame {
		id: content
		anchors.fill: parent
		padding: 0
		background: Item {
			Rectangle {
				anchors.fill: parent
				color: "transparent"
			}
			Image {
				anchors.fill: parent
				source: pane.wallpaperUrl
				fillMode: Image.PreserveAspectCrop
				asynchronous: true
				visible: source.toString().length > 0
			}
		}
		transformOrigin: Item.Center

			MouseArea {
				anchors.fill: parent
				acceptedButtons: Qt.RightButton
				onClicked: {
					pane.activated()
					pane.contextTarget = "location"
					contextMenu.popup()
				}
			}

			DropArea {
				anchors.fill: parent
				onPositionChanged: pane.springLeaveAll()
				onDropped: function (drop) {
					if (pane.repositionFromDrop(drop))
						return
					const uris = drop.urls && drop.urls.length > 0
						? drop.urls.join("\n") : drop.text
					pane.directory.drop(uris, pane.directory.path, pane.dropAction(drop))
					drop.acceptProposedAction()
				}
			}

			GridView {
				id: grid
				anchors.fill: parent
				anchors.leftMargin: pane.gridOffsetX
				anchors.topMargin: pane.gridOffsetY
					+ (pane.filterActive ? filterBar.height + 8 : 0)
				anchors.rightMargin: pane.spec.horizontal ? 0
					: Math.max(0, content.width - pane.gridOffsetX - pane.naturalWidth)
				anchors.bottomMargin: pane.spec.horizontal
					? Math.max(0, content.height - pane.gridOffsetY - pane.naturalHeight) : 0
				clip: true
				focus: pane.active && pane.spec.mode === "grid" && pane.spec.free !== true
				visible: pane.spec.mode === "grid" && pane.spec.free !== true
					&& pane.spec.grouped !== true
				model: pane.directory
				cellWidth: pane.spec.cell_width || 96
				cellHeight: pane.spec.cell_height || 96

				Keys.onPressed: function (event) {
					pane.handleKey(event)
				}

				delegate: Item {
					id: cell
					required property string name
					required property string title
					required property string path
					required property string icon
					required property bool is_directory
					required property bool is_image

					property string thumb: ""
					property string dragImage: ""
					Component.onCompleted: {
						if (is_image)
							thumb = pane.directory.thumbnail(path, 96)
						cell.grabToImage(function (result) {
							cell.dragImage = result.url
						}, Qt.size(64, 64))
					}

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: grid.cellWidth
					height: grid.cellHeight
					opacity: pane.dragActive && pane.dragPath === path ? 0.4 : 1.0

					Rectangle {
						anchors.fill: parent
						anchors.margins: 2
						radius: 6
						color: Kirigami.Theme.highlightColor
						opacity: cell.selected ? 0.28 : 0
					}

					Rectangle {
						anchors.fill: parent
						anchors.margins: 1
						color: "transparent"
						border.width: 2
						border.color: Kirigami.Theme.highlightColor
						visible: pane.active && pane.directory.focused_path === path
					}

					GridLayout {
						anchors.centerIn: parent
						columns: pane.labelsBeside && pane.showLabels ? 2 : 1
						columnSpacing: 4
						rowSpacing: 4

						Item {
							Layout.preferredWidth: pane.spec.icon_size || 48
							Layout.preferredHeight: Layout.preferredWidth
							Layout.alignment: Qt.AlignHCenter

							Image {
								anchors.fill: parent
								source: cell.thumb
								fillMode: Image.PreserveAspectCrop
								visible: cell.thumb.length > 0
							}

							Image {
								anchors.fill: parent
								source: pane.isFileIcon(cell.icon) ? cell.icon : ""
								fillMode: Image.PreserveAspectFit
								visible: cell.thumb.length === 0 && pane.isFileIcon(cell.icon)
							}

							Kirigami.Icon {
								anchors.fill: parent
								source: cell.icon
								visible: cell.thumb.length === 0 && !pane.isFileIcon(cell.icon)
							}
						}

						Label {
							Layout.fillWidth: pane.labelsBeside && pane.showLabels
							Layout.preferredWidth: pane.labelsBeside && pane.showLabels
								? Math.max(0, grid.cellWidth - (pane.spec.icon_size || 48) - 12)
								: grid.cellWidth - 8
							Layout.alignment: Qt.AlignVCenter
							visible: pane.showLabels
							text: pane.displayName(name, title)
							elide: Text.ElideMiddle
							horizontalAlignment: pane.labelsBeside && pane.showLabels
								? Text.AlignLeft : Text.AlignHCenter
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: cell.is_directory
						onEntered: if (cell.is_directory) pane.springEnter(cell.path)
						onPositionChanged: function (drag) {
							if (!cell.is_directory)
								return
							if (drag.x >= 0 && drag.x <= cell.width
									&& drag.y >= 0 && drag.y <= cell.height)
								pane.springEnter(cell.path)
							else
								pane.springLeave(cell.path)
						}
						onDropped: function (drop) {
							pane.springLeave(cell.path)
							if (!cell.is_directory)
								return
							const uris = drop.urls && drop.urls.length > 0
								? drop.urls.join("\n") : drop.text
							pane.directory.drop(uris, cell.path, pane.dropAction(drop))
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: dragArea
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: dragSource

						property bool dragging: false
						property point pressPoint

						onPressed: function (mouse) {
							dragging = false
							pressPoint = Qt.point(mouse.x, mouse.y)
						}
						onPositionChanged: function (mouse) {
							if (dragging || !pressed)
								return
							const dx = mouse.x - pressPoint.x
							const dy = mouse.y - pressPoint.y
							if (dx * dx + dy * dy < 36)
								return
							dragging = true
							pane.beginDrag(path, pane.dragUrl(path), cell.dragImage)
						}
						onReleased: dragging = false
						onClicked: function (mouse) {
							if (dragging) {
								dragging = false
								return
							}
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(cell.path)
								pane.contextTarget = "focus"
								contextMenu.popup()
							} else {
								pane.clickTarget(cell.path, mouse.modifiers)
							}
						}
						onPressAndHold: if (!dragArea.dragging) pane.holdTarget(cell.path)
						onDoubleClicked: pane.doubleTarget(cell.path)
					}
				}
			}

			ListView {
				id: list
				anchors.fill: parent
				anchors.topMargin: pane.filterActive ? filterBar.height + 8 : 0
				clip: true
				focus: pane.active && pane.spec.mode !== "grid" && pane.spec.free !== true
				visible: pane.spec.mode !== "grid" && pane.spec.free !== true
				model: pane.directory

				Keys.onPressed: function (event) {
					pane.handleKey(event)
				}

				header: Item {
					width: list.width
					height: pane.spec.header === true ? 28 : 0
					visible: pane.spec.header === true

					RowLayout {
						anchors.fill: parent
						anchors.leftMargin: 6
						anchors.rightMargin: 6
						spacing: 8

						Item {
							Layout.preferredWidth: 24
						}
						Repeater {
							model: pane.listColumns
							Label {
								required property string modelData
								Layout.fillWidth: pane.isFillColumn(modelData)
								Layout.preferredWidth: pane.isFillColumn(modelData)
									? -1 : pane.columnWidth(modelData)
								text: pane.columnLabel(modelData)
								elide: Text.ElideRight
								font.bold: true
							}
						}
					}
				}

				section.property: pane.spec.grouped === true ? "group_label" : ""
				section.criteria: ViewSection.FullString
				section.delegate: Item {
					width: ListView.view ? ListView.view.width : list.width
					height: 30

					Label {
						anchors.left: parent.left
						anchors.leftMargin: 6
						anchors.verticalCenter: parent.verticalCenter
						text: section
						font.bold: true
						color: Kirigami.Theme.textColor
					}
				}

				delegate: Rectangle {
					id: row
					required property string name
					required property string title
					required property string path
					required property string icon
					required property string mime
					required property string group_label
					required property bool is_directory
					required property bool is_image
					required property var size_bytes
					required property var modified_time
					required property var created_time
					required property var accessed_time

					property string thumb: ""
					property string dragImage: ""
					Component.onCompleted: {
						if (is_image)
							thumb = pane.directory.thumbnail(path, 32)
						row.grabToImage(function (result) {
							row.dragImage = result.url
						}, Qt.size(64, 64))
					}

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: ListView.view.width
					height: 30
					opacity: pane.dragActive && pane.dragPath === path ? 0.4 : 1.0
					color: row.selected ? Qt.rgba(
						Kirigami.Theme.highlightColor.r,
						Kirigami.Theme.highlightColor.g,
						Kirigami.Theme.highlightColor.b,
						0.28) : "transparent"

					Rectangle {
						anchors.fill: parent
						anchors.margins: 1
						color: "transparent"
						border.width: 2
						border.color: Kirigami.Theme.highlightColor
						visible: pane.active && pane.directory.focused_path === path
					}

					RowLayout {
						anchors.fill: parent
						anchors.leftMargin: 6
						anchors.rightMargin: 6
						spacing: 8

						Image {
							source: row.thumb
							width: 24
							height: 24
							fillMode: Image.PreserveAspectCrop
							visible: row.thumb.length > 0
						}

						Image {
							source: pane.isFileIcon(row.icon) ? row.icon : ""
							width: 18
							height: 18
							fillMode: Image.PreserveAspectFit
							visible: row.thumb.length === 0 && pane.isFileIcon(row.icon)
						}

						Kirigami.Icon {
							source: row.icon
							width: 18
							height: 18
							visible: row.thumb.length === 0 && !pane.isFileIcon(row.icon)
						}

						Repeater {
							model: pane.listColumns
							Label {
								required property string modelData
								Layout.fillWidth: pane.isFillColumn(modelData)
								Layout.preferredWidth: pane.isFillColumn(modelData)
									? -1 : pane.columnWidth(modelData)
								visible: pane.showLabels
								text: pane.columnText(modelData, row)
								elide: Text.ElideRight
							}
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: row.is_directory
						onEntered: if (row.is_directory) pane.springEnter(row.path)
						onPositionChanged: function (drag) {
							if (!row.is_directory)
								return
							if (drag.x >= 0 && drag.x <= row.width
									&& drag.y >= 0 && drag.y <= row.height)
								pane.springEnter(row.path)
							else
								pane.springLeave(row.path)
						}
						onDropped: function (drop) {
							pane.springLeave(row.path)
							if (!row.is_directory)
								return
							const uris = drop.urls && drop.urls.length > 0
								? drop.urls.join("\n") : drop.text
							pane.directory.drop(uris, row.path, pane.dropAction(drop))
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: rowDrag
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: dragSource

						property bool dragging: false
						property point pressPoint

						onPressed: function (mouse) {
							dragging = false
							pressPoint = Qt.point(mouse.x, mouse.y)
						}
						onPositionChanged: function (mouse) {
							if (dragging || !pressed)
								return
							const dx = mouse.x - pressPoint.x
							const dy = mouse.y - pressPoint.y
							if (dx * dx + dy * dy < 36)
								return
							dragging = true
							pane.beginDrag(path, pane.dragUrl(path), row.dragImage)
						}
						onReleased: dragging = false
						onClicked: function (mouse) {
							if (dragging) {
								dragging = false
								return
							}
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(row.path)
								pane.contextTarget = "focus"
								contextMenu.popup()
							} else {
								pane.clickTarget(row.path, mouse.modifiers)
							}
						}
						onPressAndHold: if (!rowDrag.dragging) pane.holdTarget(row.path)
						onDoubleClicked: pane.doubleTarget(row.path)
					}
				}
			}

			Flickable {
				id: absoluteView
				anchors.fill: parent
				anchors.topMargin: pane.filterActive ? filterBar.height + 8 : 0
				visible: pane.spec.free === true || pane.spec.grouped === true
				clip: true
				focus: pane.active && visible
				contentWidth: Math.max(width, pane.freeNaturalWidth + pane.freeOffsetX)
				contentHeight: Math.max(height, pane.freeNaturalHeight + pane.freeOffsetY)
				boundsBehavior: Flickable.StopAtBounds

				Keys.onPressed: function (event) {
					pane.handleKey(event)
				}

				DropArea {
					anchors.fill: parent
					onPositionChanged: pane.springLeaveAll()
					onDropped: function (drop) {
						if (pane.repositionFromDrop(drop))
							return
						const uris = drop.urls && drop.urls.length > 0
							? drop.urls.join("\n") : drop.text
						pane.directory.drop(uris, pane.directory.path, pane.dropAction(drop))
						drop.acceptProposedAction()
					}
				}

			Repeater {
				model: (pane.spec.free === true || pane.spec.grouped === true)
					? pane.spec.slots : []

				delegate: Item {
					id: freeSlot
					required property var modelData

					x: pane.freeOffsetX + modelData.x
					y: pane.freeOffsetY + modelData.y
					width: modelData.width
					height: modelData.height
					opacity: pane.dragActive
						&& pane.dragPath === modelData.path ? 0.4 : 1.0

					property string thumb: ""
					property string dragImage: ""
					Component.onCompleted: {
						if (modelData.is_image)
							thumb = pane.directory.thumbnail(modelData.path, 64)
						freeSlot.grabToImage(function (result) {
							freeSlot.dragImage = result.url
						}, Qt.size(64, 64))
					}

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(modelData.path)
					}

					Rectangle {
						anchors.fill: parent
						anchors.margins: 2
						radius: 6
						color: Kirigami.Theme.highlightColor
						opacity: freeSlot.selected ? 0.28 : 0
					}

					Rectangle {
						anchors.fill: parent
						anchors.margins: 1
						color: "transparent"
						border.width: 2
						border.color: Kirigami.Theme.highlightColor
						visible: pane.active && pane.directory.focused_path === modelData.path
					}

					GridLayout {
						anchors.centerIn: parent
						columns: pane.labelsBeside && pane.showLabels ? 2 : 1
						columnSpacing: 4
						rowSpacing: 4

						Item {
							Layout.preferredWidth: 48
							Layout.preferredHeight: 48
							Layout.alignment: Qt.AlignHCenter

							Image {
								anchors.fill: parent
								source: freeSlot.thumb
								fillMode: Image.PreserveAspectCrop
								visible: freeSlot.thumb.length > 0
							}

							Image {
								anchors.fill: parent
								source: pane.isFileIcon(modelData.icon) ? modelData.icon : ""
								fillMode: Image.PreserveAspectFit
								visible: freeSlot.thumb.length === 0 && pane.isFileIcon(modelData.icon)
							}

							Kirigami.Icon {
								anchors.fill: parent
								source: modelData.icon
								visible: freeSlot.thumb.length === 0 && !pane.isFileIcon(modelData.icon)
							}
						}

						Label {
							Layout.fillWidth: pane.labelsBeside && pane.showLabels
							Layout.preferredWidth: pane.labelsBeside && pane.showLabels
								? Math.max(0, freeSlot.width - 60) : freeSlot.width - 8
							Layout.alignment: Qt.AlignVCenter
							visible: pane.showLabels
							text: pane.displayName(modelData.name, modelData.title || "")
							elide: Text.ElideMiddle
							horizontalAlignment: pane.labelsBeside && pane.showLabels
								? Text.AlignLeft : Text.AlignHCenter
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: modelData.is_directory === true
						onEntered: if (modelData.is_directory === true)
							pane.springEnter(modelData.path)
						onPositionChanged: function (drag) {
							if (modelData.is_directory !== true)
								return
							if (drag.x >= 0 && drag.x <= freeSlot.width
									&& drag.y >= 0 && drag.y <= freeSlot.height)
								pane.springEnter(modelData.path)
							else
								pane.springLeave(modelData.path)
						}
						onDropped: function (drop) {
							pane.springLeave(modelData.path)
							if (modelData.is_directory !== true)
								return
							const uris = drop.urls && drop.urls.length > 0
								? drop.urls.join("\n") : drop.text
							pane.directory.drop(uris, modelData.path, pane.dropAction(drop))
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: freeDrag
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: dragSource

						property bool dragging: false
						property point pressPoint

						onPressed: function (mouse) {
							dragging = false
							pressPoint = Qt.point(mouse.x, mouse.y)
						}
						onPositionChanged: function (mouse) {
							if (dragging || !pressed)
								return
							const dx = mouse.x - pressPoint.x
							const dy = mouse.y - pressPoint.y
							if (dx * dx + dy * dy < 36)
								return
							dragging = true
							pane.beginDrag(modelData.path,
								pane.dragUrl(modelData.path), freeSlot.dragImage)
						}
						onReleased: dragging = false
						onClicked: function (mouse) {
							if (dragging) {
								dragging = false
								return
							}
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(modelData.path)
								pane.contextTarget = "focus"
								contextMenu.popup()
							} else {
								pane.clickTarget(modelData.path, mouse.modifiers)
							}
						}
						onPressAndHold: if (!freeDrag.dragging) pane.holdTarget(modelData.path)
						onDoubleClicked: pane.doubleTarget(modelData.path)
					}
				}
			}

			Repeater {
				model: pane.spec.headers || []

				Label {
					required property var modelData
					x: pane.freeOffsetX + modelData.x
					y: pane.freeOffsetY + modelData.y
					width: modelData.width
					height: modelData.height
					z: 2
					text: modelData.title
					font.bold: true
					color: Kirigami.Theme.textColor
					elide: Text.ElideRight
				}
			}
			}
	}



	Item {
		id: dragSource
		width: 1
		height: 1
		opacity: 0.01

		Drag.dragType: Drag.Automatic
		Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
		Drag.hotSpot.x: 24
		Drag.hotSpot.y: 24
		Drag.onDragStarted: pane.dragSourceUris = String(
			Drag.mimeData ? Drag.mimeData["text/uri-list"] : "")
		Drag.onDragFinished: {
			pane.dragActive = false
			pane.dragPath = ""
			pane.dragSourceUris = ""
		}
	}

	FolderFilterBar {
		id: filterBar
		directory: pane.directory
		matchCount: pane.directory ? pane.directory.matchCount : 0
		filterActive: pane.filterActive
		window: pane.window
		onFocusRequested: pane.focusView()
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
