import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt
import org.kde.kirigami as Kirigami

ApplicationWindow {
	id: window
	width: 720
	height: 520
	visible: true
	title: "hishell qtbridge preview"

	required property var directory

	PathBridge {
		id: pathUtils
	}

	property var contextActions: []

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

	function handleGamepad(action) {
		if (action === "up" || action === "down" || action === "left" || action === "right") {
			window.directory.move_focus(action)
		} else if (action === "accept") {
			if (window.directory.focused_path.length > 0)
				window.directory.open(window.directory.focused_path)
		} else if (action === "cancel") {
			window.directory.go_up()
		} else if (action === "menu") {
			contextMenu.popup()
		} else if (action === "select") {
			if (window.directory.focused_path.length > 0)
				window.directory.toggle_select(window.directory.focused_path)
		} else if (action === "directory") {
			window.directory.select_all()
		}
	}

	function handleKey(event) {
		if (event.key === Qt.Key_Left) {
			window.directory.move_focus("left")
			event.accepted = true
		} else if (event.key === Qt.Key_Right) {
			window.directory.move_focus("right")
			event.accepted = true
		} else if (event.key === Qt.Key_Up) {
			if (event.modifiers & Qt.AltModifier) {
				window.directory.go_up()
			} else {
				window.directory.move_focus("up")
			}
			event.accepted = true
		} else if (event.key === Qt.Key_Down) {
			window.directory.move_focus("down")
			event.accepted = true
		} else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
			if (window.directory.focused_path.length > 0)
				window.directory.open(window.directory.focused_path)
			event.accepted = true
		} else if (event.key === Qt.Key_Backspace) {
			window.directory.go_up()
			event.accepted = true
		}
	}

	Component.onCompleted: window.directory.focus_first()

	Timer {
		interval: 80
		repeat: true
		running: true
		onTriggered: {
			const action = window.directory.poll_gamepad()
			if (action.length > 0)
				window.handleGamepad(action)
		}
	}

	Connections {
		target: window.directory
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
				window.directory.rename(targetPath, renameField.text)
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
		onAccepted: window.directory.trash(pathsJson, permanent)

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
		onOpened: apps = JSON.parse(window.directory.apps_json(targetPath))

		ColumnLayout {
			Repeater {
				model: openWithDialog.apps
				Button {
					required property var modelData
					Layout.fillWidth: true
					text: modelData.name
					onClicked: {
						window.directory.open_with(openWithDialog.targetPath, modelData.id)
						openWithDialog.close()
					}
				}
			}
		}
	}

	Menu {
		id: contextMenu
		onAboutToShow: window.contextActions = JSON.parse(
			window.directory.actions_json("context", "focus"))

		Repeater {
			model: window.contextActions

			MenuItem {
				required property var modelData
				text: window.actionLabel(modelData.id)
				enabled: modelData.enabled
				onTriggered: window.directory.invoke(modelData.id)
			}
		}
	}

	readonly property var spec: {
		window.directory.revision
		return JSON.parse(window.directory.view_json(grid.width, grid.height, 18, 4, 18))
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		RowLayout {
			Layout.fillWidth: true
			Layout.margins: 8

			Label {
				text: pathUtils.folder_name(window.directory.path)
				font.bold: true
			}

			Label {
				text: window.directory.path
				elide: Text.ElideMiddle
				Layout.fillWidth: true
			}

			Label {
				text: window.spec.mode + " · " + (window.spec.lines || 0) + " lines · "
					+ Math.round(window.spec.icon_size || 0) + "px"
			}

			Label {
				text: window.directory.selectedCount + " selected"
				visible: window.directory.selectionActive
			}

			Button {
				text: "Up"
				onClicked: window.directory.go_up()
			}

			Button {
				text: "Select all"
				onClicked: window.directory.select_all()
			}

			Button {
				text: "Clear"
				visible: window.directory.selectionActive
				onClicked: window.directory.clear_selection()
			}

			Button {
				text: "Reload"
				onClicked: window.directory.refresh_async()
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
				Component.onCompleted: currentIndex = window.directory.config.view_mode === "LIST" ? 1 : 0
				onActivated: window.directory.set_config("view_mode", index === 1 ? "LIST" : "GRID")
			}

			Label { text: "Mode" }

			ComboBox {
				model: ["Lines", "Size"]
				Component.onCompleted: currentIndex = window.directory.config.grid_mode === "SIZE" ? 1 : 0
				onActivated: window.directory.set_config("grid_mode", index === 1 ? "SIZE" : "LINES")
			}

			Label { text: "Lines" }

			SpinBox {
				from: 1
				to: 8
				Component.onCompleted: value = window.directory.config.grid_lines
				onValueModified: window.directory.set_config("grid_lines", String(value))
			}

			Label { text: "Icon" }

			SpinBox {
				from: 16
				to: 256
				stepSize: 8
				Component.onCompleted: value = window.directory.config.grid_size
				onValueModified: window.directory.set_config("grid_size", String(value))
			}

			CheckBox {
				text: "Labels"
				Component.onCompleted: checked = window.directory.config.show_labels
				onToggled: window.directory.set_config("show_labels", checked ? "true" : "false")
			}

			Item { Layout.fillWidth: true }
		}

		Frame {
			Layout.fillWidth: true
			Layout.fillHeight: true
			Layout.margins: 8

			DropArea {
				anchors.fill: parent
				onDropped: function (drop) {
					const action = drop.proposedAction === Qt.MoveAction ? "move"
						: drop.proposedAction === Qt.LinkAction ? "link" : "copy"
					const uris = drop.urls && drop.urls.length > 0
						? drop.urls.join("\n") : drop.text
					window.directory.drop(uris, window.directory.path, action)
					drop.acceptProposedAction()
				}
			}

			GridView {
				id: grid
				anchors.fill: parent
				clip: true
				focus: window.spec.free !== true
				visible: window.spec.free !== true
				model: window.directory
				cellWidth: window.spec.cell_width || 96
				cellHeight: window.spec.cell_height || 96

				Keys.onPressed: function (event) {
					window.handleKey(event)
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
						thumb = window.directory.thumbnail(path, 96)

					Drag.active: dragArea.drag.active
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": "file://" + path })
					Drag.hotSpot.x: 8
					Drag.hotSpot.y: 8

					readonly property bool selected: {
						window.directory.selectionRevision
						return window.directory.is_selected(path)
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
						visible: window.directory.focused_path === path
					}

					Column {
						anchors.centerIn: parent
						spacing: 4

						Image {
							width: window.spec.icon_size || 48
							height: width
							source: cell.thumb
							fillMode: Image.PreserveAspectCrop
							visible: cell.thumb.length > 0
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Image {
							width: window.spec.icon_size || 48
							height: width
							source: cell.icon
							fillMode: Image.PreserveAspectFit
							visible: cell.thumb.length === 0 && window.isFileIcon(cell.icon)
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Kirigami.Icon {
							width: window.spec.icon_size || 48
							height: width
							source: cell.icon
							visible: cell.thumb.length === 0 && !window.isFileIcon(cell.icon)
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
							window.directory.drop(uris, cell.path, action)
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: dragArea
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: cell
						onClicked: function (mouse) {
							if (mouse.button === Qt.RightButton) {
								window.directory.focus_path(cell.path)
								contextMenu.popup()
							} else {
								window.directory.focus_path(cell.path)
								window.directory.toggle_select(cell.path)
							}
						}
						onDoubleClicked: window.directory.open(cell.path)
					}
				}
			}

			ListView {
				anchors.fill: parent
				clip: true
				focus: window.spec.free !== true
				visible: window.spec.mode !== "grid" && window.spec.free !== true
				model: window.directory

				Keys.onPressed: function (event) {
					window.handleKey(event)
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
						thumb = window.directory.thumbnail(path, 32)

					Drag.active: rowDrag.drag.active
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": "file://" + path })
					Drag.hotSpot.x: 8
					Drag.hotSpot.y: 8

					readonly property bool selected: {
						window.directory.selectionRevision
						return window.directory.is_selected(path)
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
						visible: window.directory.focused_path === path
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
							visible: row.thumb.length === 0 && window.isFileIcon(row.icon)
						}

						Kirigami.Icon {
							source: row.icon
							width: 18
							height: 18
							visible: row.thumb.length === 0 && !window.isFileIcon(row.icon)
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
							window.directory.drop(uris, row.path, action)
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: rowDrag
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: row
						onClicked: function (mouse) {
							if (mouse.button === Qt.RightButton) {
								window.directory.focus_path(row.path)
								contextMenu.popup()
							} else {
								window.directory.focus_path(row.path)
								window.directory.toggle_select(row.path)
							}
						}
						onDoubleClicked: window.directory.open(row.path)
					}
				}
			}

			Repeater {
				model: window.spec.free === true ? window.spec.slots : []

				delegate: Item {
					id: freeSlot
					required property var modelData

					x: modelData.x
					y: modelData.y
					width: modelData.width
					height: modelData.height

					property string thumb: ""
					Component.onCompleted: if (modelData.is_image)
						thumb = window.directory.thumbnail(modelData.path, 64)

					readonly property bool selected: {
						window.directory.selectionRevision
						return window.directory.is_selected(modelData.path)
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
						visible: window.directory.focused_path === modelData.path
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
							visible: freeSlot.thumb.length === 0 && window.isFileIcon(modelData.icon)
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Kirigami.Icon {
							width: 48
							height: 48
							source: modelData.icon
							visible: freeSlot.thumb.length === 0 && !window.isFileIcon(modelData.icon)
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
							window.directory.drop(uris, modelData.path, action)
							drop.acceptProposedAction()
						}
					}

					MouseArea {
						id: freeDrag
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						drag.target: freeSlot
						onClicked: function (mouse) {
							if (mouse.button === Qt.RightButton) {
								window.directory.focus_path(modelData.path)
								contextMenu.popup()
							} else {
								window.directory.focus_path(modelData.path)
								window.directory.toggle_select(modelData.path)
							}
						}
						onDoubleClicked: window.directory.open(modelData.path)
					}
				}
			}
		}
	}
}
