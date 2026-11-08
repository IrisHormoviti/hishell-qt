import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt
import org.kde.kirigami as Kirigami

Item {
	id: pane

	property bool active: false

	signal activated()
	signal focusEdge(string direction)

	required property var directory

	PathBridge {
		id: pathUtils
	}

	property var contextActions: []
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
			"rename": "Rename…",
			"trash": "Move to Trash…",
			"delete": "Delete…",
			"destroy": "Delete Permanently…",
			"toggle": "Toggle",
			"rotate-image": "Rotate Clockwise"
		}
		return labels[id] || id
	}

	function isFileIcon(source) {
		return source.indexOf("file://") === 0 || source.indexOf("/") === 0
	}

	function handleKey(event) {
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
		} else if (event.key === Qt.Key_Backspace) {
			pane.directory.go_up()
			event.accepted = true
		}
	}

	Component.onCompleted: pane.directory.focus_first()


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

	Menu {
		id: contextMenu
		onAboutToShow: pane.contextActions = JSON.parse(
			pane.directory.actions_json("context", "focus"))

		Repeater {
			model: pane.contextActions

			MenuItem {
				required property var modelData
				text: pane.actionLabel(modelData.id)
				enabled: modelData.enabled
				onTriggered: pane.directory.invoke(modelData.id)
			}
		}
	}

	readonly property var spec: {
		pane.directory.revision
		return JSON.parse(pane.directory.view_json(grid.width, grid.height, 18, 4, 18))
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		RowLayout {
			Layout.fillWidth: true
			Layout.margins: 8

			Label {
				text: pathUtils.folder_name(pane.directory.path)
				font.bold: true
			}

			Label {
				text: pane.directory.path
				elide: Text.ElideMiddle
				Layout.fillWidth: true
			}

			Label {
				text: pane.spec.mode + " · " + (pane.spec.lines || 0) + " lines · "
					+ Math.round(pane.spec.icon_size || 0) + "px"
			}

			Label {
				text: pane.directory.selectedCount + " selected"
				visible: pane.directory.selectionActive
			}

			Button {
				text: "Up"
				onClicked: pane.directory.go_up()
			}

			Button {
				text: "Select all"
				onClicked: pane.directory.select_all()
			}

			Button {
				text: "Clear"
				visible: pane.directory.selectionActive
				onClicked: pane.directory.clear_selection()
			}

			Button {
				text: "Reload"
				onClicked: pane.directory.refresh_async()
			}
		}

		RowLayout {
			Layout.fillWidth: true
			Layout.leftMargin: 8
			Layout.rightMargin: 8
			Layout.bottomMargin: 8

			Label { text: "View" }

			ComboBox {
				model: ["Grid", "List"]
				Component.onCompleted: currentIndex = pane.directory.config.view_mode === "LIST" ? 1 : 0
				onActivated: pane.directory.set_config("view_mode", index === 1 ? "LIST" : "GRID")
			}

			Label { text: "Mode" }

			ComboBox {
				model: ["Lines", "Size"]
				Component.onCompleted: currentIndex = pane.directory.config.grid_mode === "SIZE" ? 1 : 0
				onActivated: pane.directory.set_config("grid_mode", index === 1 ? "SIZE" : "LINES")
			}

			Label { text: "Lines" }

			SpinBox {
				from: 1
				to: 8
				Component.onCompleted: value = pane.directory.config.grid_lines
				onValueModified: pane.directory.set_config("grid_lines", String(value))
			}

			Label { text: "Icon" }

			SpinBox {
				from: 16
				to: 256
				stepSize: 8
				Component.onCompleted: value = pane.directory.config.grid_size
				onValueModified: pane.directory.set_config("grid_size", String(value))
			}

			CheckBox {
				text: "Labels"
				Component.onCompleted: checked = pane.directory.config.show_labels
				onToggled: pane.directory.set_config("show_labels", checked ? "true" : "false")
			}

			Item { Layout.fillWidth: true }
		}

		Frame {
			id: content
			Layout.fillWidth: true
			Layout.fillHeight: true
			Layout.margins: 8
			transformOrigin: Item.Center

			DropArea {
				anchors.fill: parent
				onDropped: function (drop) {
					const action = drop.proposedAction === Qt.MoveAction ? "move"
						: drop.proposedAction === Qt.LinkAction ? "link" : "copy"
					const uris = drop.urls && drop.urls.length > 0
						? drop.urls.join("\n") : drop.text
					pane.directory.drop(uris, pane.directory.path, action)
					drop.acceptProposedAction()
				}
			}

			GridView {
				id: grid
				anchors.fill: parent
				clip: true
				focus: pane.active && pane.spec.free !== true
				visible: pane.spec.free !== true
				model: pane.directory
				cellWidth: pane.spec.cell_width || 96
				cellHeight: pane.spec.cell_height || 96

				Keys.onPressed: function (event) {
					pane.handleKey(event)
				}

				delegate: Item {
					id: cell
					required property string name
					required property string path
					required property string icon
					required property bool is_directory
					required property bool is_image

					property string thumb: ""
					Component.onCompleted: if (is_image)
						thumb = pane.directory.thumbnail(path, 96)

					Drag.active: dragArea.drag.active
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": "file://" + path })
					Drag.hotSpot.x: 8
					Drag.hotSpot.y: 8

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: grid.cellWidth
					height: grid.cellHeight

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
						visible: pane.directory.focused_path === path
					}

					Column {
						anchors.centerIn: parent
						spacing: 4

						Image {
							width: pane.spec.icon_size || 48
							height: width
							source: cell.thumb
							fillMode: Image.PreserveAspectCrop
							visible: cell.thumb.length > 0
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Image {
							width: pane.spec.icon_size || 48
							height: width
							source: cell.icon
							fillMode: Image.PreserveAspectFit
							visible: cell.thumb.length === 0 && pane.isFileIcon(cell.icon)
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Kirigami.Icon {
							width: pane.spec.icon_size || 48
							height: width
							source: cell.icon
							visible: cell.thumb.length === 0 && !pane.isFileIcon(cell.icon)
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Label {
							width: grid.cellWidth - 8
							text: name
							elide: Text.ElideMiddle
							horizontalAlignment: Text.AlignHCenter
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: cell.is_directory
						onDropped: function (drop) {
							if (!cell.is_directory)
								return
							const action = drop.proposedAction === Qt.MoveAction ? "move"
								: drop.proposedAction === Qt.LinkAction ? "link" : "copy"
							const uris = drop.urls && drop.urls.length > 0
								? drop.urls.join("\n") : drop.text
							pane.directory.drop(uris, cell.path, action)
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: dragArea
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: cell
						onClicked: function (mouse) {
							pane.activated()
							if (mouse.button === Qt.RightButton) {
								pane.directory.focus_path(cell.path)
								contextMenu.popup()
							} else {
								pane.directory.focus_path(cell.path)
								pane.directory.toggle_select(cell.path)
							}
						}
						onDoubleClicked: pane.directory.open(cell.path)
					}
				}
			}

			ListView {
				id: list
				anchors.fill: parent
				clip: true
				focus: pane.active && pane.spec.free !== true
				visible: pane.spec.mode !== "grid" && pane.spec.free !== true
				model: pane.directory

				Keys.onPressed: function (event) {
					pane.handleKey(event)
				}

				delegate: Rectangle {
					id: row
					required property string name
					required property string path
					required property string icon
					required property bool is_directory
					required property bool is_image

					property string thumb: ""
					Component.onCompleted: if (is_image)
						thumb = pane.directory.thumbnail(path, 32)

					Drag.active: rowDrag.drag.active
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": "file://" + path })
					Drag.hotSpot.x: 8
					Drag.hotSpot.y: 8

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: ListView.view.width
					height: 30
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
						visible: pane.directory.focused_path === path
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
							source: row.icon
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

						Label {
							text: row.name
							elide: Text.ElideRight
							Layout.fillWidth: true
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: row.is_directory
						onDropped: function (drop) {
							if (!row.is_directory)
								return
							const action = drop.proposedAction === Qt.MoveAction ? "move"
								: drop.proposedAction === Qt.LinkAction ? "link" : "copy"
							const uris = drop.urls && drop.urls.length > 0
								? drop.urls.join("\n") : drop.text
							pane.directory.drop(uris, row.path, action)
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: rowDrag
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: row
						onClicked: function (mouse) {
							pane.activated()
							if (mouse.button === Qt.RightButton) {
								pane.directory.focus_path(row.path)
								contextMenu.popup()
							} else {
								pane.directory.focus_path(row.path)
								pane.directory.toggle_select(row.path)
							}
						}
						onDoubleClicked: pane.directory.open(row.path)
					}
				}
			}

			Repeater {
				model: pane.spec.free === true ? pane.spec.slots : []

				delegate: Item {
					id: freeSlot
					required property var modelData

					x: modelData.x
					y: modelData.y
					width: modelData.width
					height: modelData.height

					property string thumb: ""
					Component.onCompleted: if (modelData.is_image)
						thumb = pane.directory.thumbnail(modelData.path, 64)

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(modelData.path)
					}

					Drag.active: freeDrag.drag.active
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": "file://" + modelData.path })
					Drag.hotSpot.x: 8
					Drag.hotSpot.y: 8

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
						visible: pane.directory.focused_path === modelData.path
					}

					Column {
						anchors.centerIn: parent
						spacing: 4

						Image {
							width: 48
							height: 48
							source: freeSlot.thumb
							fillMode: Image.PreserveAspectCrop
							visible: freeSlot.thumb.length > 0
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Image {
							width: 48
							height: 48
							source: modelData.icon
							fillMode: Image.PreserveAspectFit
							visible: freeSlot.thumb.length === 0 && pane.isFileIcon(modelData.icon)
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Kirigami.Icon {
							width: 48
							height: 48
							source: modelData.icon
							visible: freeSlot.thumb.length === 0 && !pane.isFileIcon(modelData.icon)
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Label {
							width: parent.width
							text: modelData.name
							elide: Text.ElideMiddle
							horizontalAlignment: Text.AlignHCenter
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: modelData.is_directory === true
						onDropped: function (drop) {
							if (modelData.is_directory !== true)
								return
							const action = drop.proposedAction === Qt.MoveAction ? "move"
								: drop.proposedAction === Qt.LinkAction ? "link" : "copy"
							const uris = drop.urls && drop.urls.length > 0
								? drop.urls.join("\n") : drop.text
							pane.directory.drop(uris, modelData.path, action)
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: freeDrag
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: freeSlot
						onClicked: function (mouse) {
							pane.activated()
							if (mouse.button === Qt.RightButton) {
								pane.directory.focus_path(modelData.path)
								contextMenu.popup()
							} else {
								pane.directory.focus_path(modelData.path)
								pane.directory.toggle_select(modelData.path)
							}
						}
						onDoubleClicked: pane.directory.open(modelData.path)
					}
				}
			}
		}
	}
}
