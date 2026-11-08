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
		onAboutToShow: {
			const background = pane.contextTarget === "location"
			pane.contextActions = JSON.parse(
				pane.directory.actions_json("context", pane.contextTarget))
				.filter(action => background ? action.here : action.items)
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
	readonly property bool showLabels: pane.directory
		? pane.directory.config.show_labels : true
	readonly property bool labelsBeside: pane.directory
		? pane.directory.config.gridLabelsBesidesIcons : false
	readonly property string labelText: pane.directory
		? String(pane.directory.config.label_text) : "TITLE"

	function displayName(name, title) {
		return pane.labelText === "TITLE" && title.length > 0 ? title : name
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
				anchors.leftMargin: pane.gridOffsetX
				anchors.topMargin: pane.gridOffsetY
				anchors.rightMargin: pane.spec.horizontal ? 0
					: Math.max(0, content.width - pane.gridOffsetX - pane.naturalWidth)
				anchors.bottomMargin: pane.spec.horizontal
					? Math.max(0, content.height - pane.gridOffsetY - pane.naturalHeight) : 0
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
					required property string title
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
						visible: pane.active && pane.directory.focused_path === path
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
							source: pane.isFileIcon(cell.icon) ? cell.icon : ""
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
							visible: pane.showLabels
							text: pane.displayName(name, title)
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
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(cell.path)
								pane.contextTarget = "focus"
								contextMenu.popup()
							} else {
								pane.clickTarget(cell.path, mouse.modifiers)
							}
						}
						onPressAndHold: pane.holdTarget(cell.path)
						onDoubleClicked: pane.doubleTarget(cell.path)
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
					required property string title
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

						Label {
							visible: pane.showLabels
							text: pane.displayName(row.name, row.title)
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
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(row.path)
								pane.contextTarget = "focus"
								contextMenu.popup()
							} else {
								pane.clickTarget(row.path, mouse.modifiers)
							}
						}
						onPressAndHold: pane.holdTarget(row.path)
						onDoubleClicked: pane.doubleTarget(row.path)
					}
				}
			}

			Repeater {
				model: pane.spec.free === true ? pane.spec.slots : []

				delegate: Item {
					id: freeSlot
					required property var modelData

					x: pane.freeOffsetX + modelData.x
					y: pane.freeOffsetY + modelData.y
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
						visible: pane.active && pane.directory.focused_path === modelData.path
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
							source: pane.isFileIcon(modelData.icon) ? modelData.icon : ""
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
							visible: pane.showLabels
							text: pane.displayName(modelData.name, modelData.title || "")
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
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(modelData.path)
								pane.contextTarget = "focus"
								contextMenu.popup()
							} else {
								pane.clickTarget(modelData.path, mouse.modifiers)
							}
						}
						onPressAndHold: pane.holdTarget(modelData.path)
						onDoubleClicked: pane.doubleTarget(modelData.path)
					}
				}
			}
		}
}
