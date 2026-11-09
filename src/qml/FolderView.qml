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

	property string contextTarget: "location"

	function springEnter(path) {
		DragHelper.setSpringTarget(path)
	}

	function springLeave() {
		DragHelper.clearSpringTarget()
	}

	Connections {
		target: DragHelper
		function onSpringRequested(path) {
			pane.directory.navigate(path)
		}
	}
	property string transitionDirection: ""

	readonly property alias renameDialogOpen: renameDialog.visible
	readonly property alias trashDialogOpen: trashDialog.visible
	readonly property alias openWithDialogOpen: openWithDialog.visible

	function openContextMenu() {
		contextMenu.popup()
	}

	// Context menu for the focused item, shared by the Menu key, Shift+F10,
	// and the gamepad menu button. An empty slot is background, so it opens
	// the folder menu.
	function openFocusedMenu() {
		if (!pane.active || !pane.directory)
			return
		if (pane.directory.focusOnEmpty) {
			pane.contextTarget = "location"
			contextMenu.popup()
			return
		}
		if (pane.directory.focused_path.length > 0) {
			pane.contextTarget = "focus"
			contextMenu.popup()
		}
	}

	function closeDialogs() {
		renameDialog.close()
		trashDialog.close()
		openWithDialog.close()
	}

	onActiveChanged: if (active)
		folderGrid.focusView()

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
			pane.openFocusedMenu()
		} else if (action === "select") {
			if (pane.directory.focused_path.length > 0)
				pane.directory.toggle_select(pane.directory.focused_path)
		} else if (action === "directory") {
			pane.directory.select_all()
		}
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
		} else if (event.key === Qt.Key_Menu
				|| (event.key === Qt.Key_F10
					&& (event.modifiers & Qt.ShiftModifier))) {
			pane.openFocusedMenu()
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

	ShellContextMenu {
		id: contextMenu
		directory: pane.directory
		window: pane.window
		targetIsBackground: pane.contextTarget === "location"
		targetIsDir: pane.directory ? pane.directory.focusIsDirectory : false
		targetIsImage: pane.directory ? pane.directory.focusIsImage : false
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
			folderGrid.focusView()
		}
	}

	FolderSelectionBar {
		directory: pane.directory
		window: pane.window
	}
}
