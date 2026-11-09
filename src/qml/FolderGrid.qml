import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// Old FolderGrid role: owns the view geometry, grid/list/free delegates and
// their delegate-owned drag. FolderPane keeps the pane chrome and actions.
Item {
	id: folderGrid

	property var pane: null
	property real filterHeight: 0

	readonly property var directory: folderGrid.pane ? folderGrid.pane.directory : null
	readonly property bool showLabels: folderGrid.directory
		? folderGrid.directory.config.show_labels : true
	readonly property bool labelsBeside: folderGrid.directory
		? folderGrid.directory.config.gridLabelsBesidesIcons : false
	readonly property bool filterActive: folderGrid.directory
		? String(folderGrid.directory.filter).length > 0 : false

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
		if (folderGrid.spec.free !== true || !pane.directory)
			return false
		if (!drop.urls || drop.urls.length === 0)
			return false
		const source = folderGrid.pathFromUri(drop.urls[0])
		if (!pane.directory.row_visible(source))
			return false
		const name = source.split("/").pop()
		const cw = folderGrid.spec.cell_width || 96
		const ch = folderGrid.spec.cell_height || 96
		const gap = folderGrid.spec.gap || 0
		const column = Math.max(0, Math.round(
			(drop.x - folderGrid.freeOffsetX - cw / 2) / Math.max(1, cw + gap)))
		const row = Math.max(0, Math.round(
			(drop.y - folderGrid.freeOffsetY - ch / 2) / Math.max(1, ch + gap)))
		pane.directory.set_free_position(name, column, row)
		drop.acceptProposedAction()
		return true
	}

	function applyDrop(drop, dest) {
		const uris = drop.urls && drop.urls.length > 0
			? drop.urls.join("\n") : drop.text
		pane.directory.drop(uris, dest, pane.dropAction(drop))
		drop.acceptProposedAction()
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

	readonly property int gridLineCount: folderGrid.spec.lines || 4
	readonly property int gridCount: folderGrid.spec.count || 0
	readonly property real gridGap: folderGrid.spec.gap || 0
	readonly property real naturalWidth: {
		const pitch = (folderGrid.spec.cell_width || 96) + folderGrid.gridGap
		if (folderGrid.spec.horizontal)
			return Math.ceil(folderGrid.gridCount / Math.max(1, folderGrid.gridLineCount)) * pitch
		return folderGrid.gridLineCount * pitch
	}
	readonly property real naturalHeight: {
		const pitch = (folderGrid.spec.cell_height || 96) + folderGrid.gridGap
		if (folderGrid.spec.horizontal)
			return folderGrid.gridLineCount * pitch
		return Math.ceil(folderGrid.gridCount / Math.max(1, folderGrid.gridLineCount)) * pitch
	}
	readonly property real gridOffsetX: pane.alignOffset(folderGrid.horizontalAlign,
		content.width, folderGrid.naturalWidth)
	readonly property real gridOffsetY: pane.alignOffset(folderGrid.verticalAlign,
		content.height, folderGrid.naturalHeight)
	readonly property real freeNaturalWidth: {
		let width = 0
		for (const slot of folderGrid.spec.slots || [])
			width = Math.max(width, slot.x + slot.width)
		return width
	}
	readonly property real freeNaturalHeight: {
		let height = 0
		for (const slot of folderGrid.spec.slots || [])
			height = Math.max(height, slot.y + slot.height)
		return height
	}
	readonly property real freeOffsetX: pane.alignOffset(folderGrid.horizontalAlign,
		content.width, folderGrid.freeNaturalWidth)
	readonly property real freeOffsetY: pane.alignOffset(folderGrid.verticalAlign,
		content.height, folderGrid.freeNaturalHeight)
			function displayName(name, title) {
		return folderGrid.labelText === "TITLE" && title.length > 0 ? title : name
	}


	readonly property var listColumns: {
		const columns = folderGrid.spec.columns
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
			return row.is_directory ? "" : folderGrid.formatSize(row.size_bytes)
		if (key === "MODIFIED")
			return folderGrid.formatTime(row.modified_time)
		if (key === "CREATED")
			return folderGrid.formatTime(row.created_time)
		if (key === "ACCESSED")
			return folderGrid.formatTime(row.accessed_time)
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
				source: folderGrid.wallpaperUrl
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
					pane.openContextMenu()
				}
			}

			DropArea {
				anchors.fill: parent
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
				anchors.leftMargin: folderGrid.gridOffsetX
				anchors.topMargin: folderGrid.gridOffsetY
					+ (folderGrid.filterActive ? folderGrid.filterHeight + 8 : 0)
				anchors.rightMargin: folderGrid.spec.horizontal ? 0
					: Math.max(0, content.width - folderGrid.gridOffsetX - folderGrid.naturalWidth)
				anchors.bottomMargin: folderGrid.spec.horizontal
					? Math.max(0, content.height - folderGrid.gridOffsetY - folderGrid.naturalHeight) : 0
				clip: true
				focus: pane.active && folderGrid.spec.mode === "grid" && folderGrid.spec.free !== true
				visible: folderGrid.spec.mode === "grid" && folderGrid.spec.free !== true
					&& folderGrid.spec.grouped !== true
				model: pane.directory
				cellWidth: folderGrid.spec.cell_width || 96
				cellHeight: folderGrid.spec.cell_height || 96

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
					Component.onCompleted: {
						if (is_image)
							thumb = pane.directory.thumbnail(path, 96)
						cell.grabToImage(function (result) {
							cell.Drag.imageSource = result.url
						}, Qt.size(64, 64))
					}

					Drag.active: dragArea.dragging
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": pane.dragUrl(path) })
					Drag.hotSpot.x: 24
					Drag.hotSpot.y: 24
					Drag.imageSourceSize: Qt.size(64, 64)
					Drag.onDragStarted: pane.dragSourceUris = pane.dragUrl(path)
					Drag.onDragFinished: {
						pane.dragSourceUris = ""
										dragArea.dragging = false
					}

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: grid.cellWidth
					height: grid.cellHeight
					opacity: dragArea.dragging ? 0.4 : 1.0

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
						columns: folderGrid.labelsBeside && folderGrid.showLabels ? 2 : 1
						columnSpacing: 4
						rowSpacing: 4

						Item {
							Layout.preferredWidth: folderGrid.spec.icon_size || 48
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
							Layout.fillWidth: folderGrid.labelsBeside && folderGrid.showLabels
							Layout.preferredWidth: folderGrid.labelsBeside && folderGrid.showLabels
								? Math.max(0, grid.cellWidth - (folderGrid.spec.icon_size || 48) - 12)
								: grid.cellWidth - 8
							Layout.alignment: Qt.AlignVCenter
							visible: folderGrid.showLabels
							text: folderGrid.displayName(name, title)
							elide: Text.ElideMiddle
							horizontalAlignment: folderGrid.labelsBeside && folderGrid.showLabels
								? Text.AlignLeft : Text.AlignHCenter
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: cell.is_directory
						onEntered: if (cell.is_directory) {
							const point = cell.mapToItem(pane, cell.width / 2, cell.height / 2)
							pane.springEnter(cell.path, point.x, point.y)
						}
						onExited: pane.springLeave(cell.path)
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
							cell.Drag.active = true
						}
						onReleased: {
							dragging = false
							cell.Drag.active = false
						}
						onClicked: function (mouse) {
							if (dragging) {
								dragging = false
								return
							}
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(cell.path)
								pane.contextTarget = "focus"
								pane.openContextMenu()
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
				anchors.topMargin: folderGrid.filterActive ? folderGrid.filterHeight + 8 : 0
				clip: true
				focus: pane.active && folderGrid.spec.mode !== "grid" && folderGrid.spec.free !== true
				visible: folderGrid.spec.mode !== "grid" && folderGrid.spec.free !== true
				model: pane.directory

				Keys.onPressed: function (event) {
					pane.handleKey(event)
				}

				header: Item {
					width: list.width
					height: folderGrid.spec.header === true ? 28 : 0
					visible: folderGrid.spec.header === true

					RowLayout {
						anchors.fill: parent
						anchors.leftMargin: 6
						anchors.rightMargin: 6
						spacing: 8

						Item {
							Layout.preferredWidth: 24
						}
						Repeater {
							model: folderGrid.listColumns
							Label {
								required property string modelData
								Layout.fillWidth: folderGrid.isFillColumn(modelData)
								Layout.preferredWidth: folderGrid.isFillColumn(modelData)
									? -1 : folderGrid.columnWidth(modelData)
								text: folderGrid.columnLabel(modelData)
								elide: Text.ElideRight
								font.bold: true
							}
						}
					}
				}

				section.property: folderGrid.spec.grouped === true ? "group_label" : ""
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
					Component.onCompleted: {
						if (is_image)
							thumb = pane.directory.thumbnail(path, 32)
						row.grabToImage(function (result) {
							row.Drag.imageSource = result.url
						}, Qt.size(64, 64))
					}

					Drag.active: rowDrag.dragging
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": pane.dragUrl(path) })
					Drag.hotSpot.x: 24
					Drag.hotSpot.y: 24
					Drag.imageSourceSize: Qt.size(64, 64)
					Drag.onDragStarted: pane.dragSourceUris = pane.dragUrl(path)
					Drag.onDragFinished: {
						pane.dragSourceUris = ""
										rowDrag.dragging = false
					}

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: ListView.view.width
					height: 30
					opacity: rowDrag.dragging ? 0.4 : 1.0
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
							model: folderGrid.listColumns
							Label {
								required property string modelData
								Layout.fillWidth: folderGrid.isFillColumn(modelData)
								Layout.preferredWidth: folderGrid.isFillColumn(modelData)
									? -1 : folderGrid.columnWidth(modelData)
								visible: folderGrid.showLabels
								text: folderGrid.columnText(modelData, row)
								elide: Text.ElideRight
							}
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: row.is_directory
						onEntered: if (row.is_directory) {
							const point = row.mapToItem(pane, row.width / 2, row.height / 2)
							pane.springEnter(row.path, point.x, point.y)
						}
						onExited: pane.springLeave(row.path)
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
							row.Drag.active = true
						}
						onReleased: {
							dragging = false
							row.Drag.active = false
						}
						onClicked: function (mouse) {
							if (dragging) {
								dragging = false
								return
							}
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(row.path)
								pane.contextTarget = "focus"
								pane.openContextMenu()
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
				anchors.topMargin: folderGrid.filterActive ? folderGrid.filterHeight + 8 : 0
				visible: folderGrid.spec.free === true || folderGrid.spec.grouped === true
				clip: true
				focus: pane.active && visible
				contentWidth: Math.max(width, folderGrid.freeNaturalWidth + folderGrid.freeOffsetX)
				contentHeight: Math.max(height, folderGrid.freeNaturalHeight + folderGrid.freeOffsetY)
				boundsBehavior: Flickable.StopAtBounds

				Keys.onPressed: function (event) {
					pane.handleKey(event)
				}

				DropArea {
					anchors.fill: parent
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
				model: (folderGrid.spec.free === true || folderGrid.spec.grouped === true)
					? folderGrid.spec.slots : []

				delegate: Item {
					id: freeSlot
					required property var modelData

					x: folderGrid.freeOffsetX + modelData.x
					y: folderGrid.freeOffsetY + modelData.y
					width: modelData.width
					height: modelData.height
					opacity: freeDrag.dragging ? 0.4 : 1.0

					property string thumb: ""
					Component.onCompleted: {
						if (modelData.is_image)
							thumb = pane.directory.thumbnail(modelData.path, 64)
						freeSlot.grabToImage(function (result) {
							freeSlot.Drag.imageSource = result.url
						}, Qt.size(64, 64))
					}

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(modelData.path)
					}

					Drag.active: freeDrag.dragging
					Drag.dragType: Drag.Automatic
					Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
					Drag.mimeData: ({ "text/uri-list": pane.dragUrl(modelData.path) })
					Drag.hotSpot.x: 24
					Drag.hotSpot.y: 24
					Drag.imageSourceSize: Qt.size(64, 64)
					Drag.onDragStarted: pane.dragSourceUris = pane.dragUrl(modelData.path)
					Drag.onDragFinished: {
						pane.dragSourceUris = ""
										freeDrag.dragging = false
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
						columns: folderGrid.labelsBeside && folderGrid.showLabels ? 2 : 1
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
							Layout.fillWidth: folderGrid.labelsBeside && folderGrid.showLabels
							Layout.preferredWidth: folderGrid.labelsBeside && folderGrid.showLabels
								? Math.max(0, freeSlot.width - 60) : freeSlot.width - 8
							Layout.alignment: Qt.AlignVCenter
							visible: folderGrid.showLabels
							text: folderGrid.displayName(modelData.name, modelData.title || "")
							elide: Text.ElideMiddle
							horizontalAlignment: folderGrid.labelsBeside && folderGrid.showLabels
								? Text.AlignLeft : Text.AlignHCenter
						}
					}

					DropArea {
						anchors.fill: parent
						enabled: modelData.is_directory === true
						onEntered: if (modelData.is_directory === true) {
							const point = freeSlot.mapToItem(pane,
								freeSlot.width / 2, freeSlot.height / 2)
							pane.springEnter(modelData.path, point.x, point.y)
						}
						onExited: pane.springLeave(modelData.path)
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
							freeSlot.Drag.active = true
						}
						onReleased: {
							dragging = false
							freeSlot.Drag.active = false
						}
						onClicked: function (mouse) {
							if (dragging) {
								dragging = false
								return
							}
							if (mouse.button === Qt.RightButton) {
								pane.activated()
								pane.directory.focus_path(modelData.path)
								pane.contextTarget = "focus"
								pane.openContextMenu()
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
				model: folderGrid.spec.headers || []

				Label {
					required property var modelData
					x: folderGrid.freeOffsetX + modelData.x
					y: folderGrid.freeOffsetY + modelData.y
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



	Rectangle {
		id: springPopup
		visible: pane.springPopupVisible && pane.springFolders.length > 0
		x: Math.max(8, Math.min(pane.width - width - 8, pane.springAnchorX + 20))
		y: Math.max(8, Math.min(pane.height - height - 8, pane.springAnchorY))
		width: 220
		height: Math.min(320, 34 + pane.springFolders.length * 30)
		z: 40
		radius: 6
		color: Kirigami.Theme.backgroundColor
		border.width: 1
		border.color: Kirigami.Theme.highlightColor

		DropArea {
			anchors.fill: parent
			onDropped: function (drop) {
				pane.applyDrop(drop, pane.springFolderPath)
			}
		}

		Column {
			anchors.fill: parent
			anchors.margins: 4
			spacing: 0

			Label {
				height: 26
				width: parent.width
				text: String(pane.springFolderPath).split("/").pop()
				font.bold: true
				elide: Text.ElideRight
			}

			Repeater {
				model: pane.springFolders

				Rectangle {
					required property var modelData
					width: parent.width
					height: 30
					color: "transparent"

					Label {
						anchors.left: parent.left
						anchors.leftMargin: 6
						anchors.verticalCenter: parent.verticalCenter
						text: modelData.name
						elide: Text.ElideRight
					}

					DropArea {
						anchors.fill: parent
						onEntered: {
							pane.springNestedPath = modelData.path
							springNestedTimer.restart()
						}
						onExited: if (pane.springNestedPath === modelData.path) {
							springNestedTimer.stop()
							pane.springNestedPath = ""
						}
						onDropped: function (drop) {
							pane.applyDrop(drop, modelData.path)
						}
					}
				}
			}
		}
	}
}
