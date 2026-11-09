import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import NativeDrag 1.0

// Old FolderGrid role: owns the view geometry, grid/list/free delegates and
// their delegate-owned drag. FolderView keeps the pane chrome and actions.
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

	property bool repositionActive: false
	property var repositionEntries: []
	property var repositionAnchor: null
	property var dragPaths: []

	Connections {
		target: DragHelper
		function onDragFinished() {
			folderGrid.dragPaths = []
		}
	}

	Timer {
		id: dragEdgeScrollTimer
		interval: 24
		repeat: true
		running: folderGrid.repositionActive
			|| (folderGrid.pane && folderGrid.pane.window
				&& folderGrid.pane.window.dragActive)
		onTriggered: {
			if (folderGrid.repositionActive) {
				folderGrid.updateReposition()
				if (!DragHelper.mousePressed()) {
					const scene = folderGrid.cursorScene()
					if (scene) {
						const local = folderGrid.mapFromItem(null,
							scene.x, scene.y)
						folderGrid.endReposition(local.x, local.y)
					} else {
						folderGrid.clearReposition()
					}
					return
				}
			}
			folderGrid.updateDragEdgeScroll()
		}
	}

	function isDragging(path) {
		return folderGrid.dragPaths.indexOf(path) !== -1
	}

	function dragPathsFor(path) {
		const selected = folderGrid.selectedPaths()
		return selected.indexOf(path) !== -1 ? selected : [path]
	}

	function startDrag(grab, path, modifiers, width, height) {
		const paths = folderGrid.dragPathsFor(path)
		folderGrid.dragPaths = paths
		folderGrid.beginDragTooltip(modifiers)
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (window) {
			window.dragGhostGrab = grab
			window.dragGhostSource = grab ? String(grab.url) : ""
			window.dragGhostWidth = width
			window.dragGhostHeight = height
			window.dragGhostActive = true
		}
		const nativeDrag = folderGrid.directory
			? folderGrid.directory.config.native_drag : false
		DragHelper.startDragManyFromGrab(grab,
			paths.map(entry => folderGrid.dragUrl(entry)).join("\n"),
			nativeDrag)
	}

	function isRadioMember(path, isDir, name) {
		const config = folderGrid.directory ? folderGrid.directory.config : null
		if (!config || !config.radio_enabled)
			return false
		if (String(name).startsWith("."))
			return false
		const only = String(config.radio_only)
		if (only === "DIRECTORIES")
			return isDir
		if (only === "FILES")
			return !isDir
		return true
	}

	function isRadioSelected(path, isDir, name) {
		if (!folderGrid.isRadioMember(path, isDir, name))
			return false
		return String(folderGrid.directory.config.radio_selected)
			=== String(folderGrid.directory.radio_value(path))
	}

	function selectedPaths() {
		if (!folderGrid.directory)
			return []
		try {
			return JSON.parse(folderGrid.directory.selected_paths_json())
		} catch (error) {
			return []
		}
	}

	function freeSlotList() {
		const cw = folderGrid.spec.cell_width || 96
		const ch = folderGrid.spec.cell_height || 96
		const gap = folderGrid.spec.gap || 0
		return (folderGrid.spec.slots || []).map(slot => ({
			"path": slot.path,
			"name": slot.name,
			"title": slot.title || "",
			"icon": slot.icon,
			"isDir": slot.is_directory === true,
			"c": Math.round(slot.x / Math.max(1, cw + gap)),
			"r": Math.round(slot.y / Math.max(1, ch + gap))
		}))
	}

	function itemName(path) {
		const sep = String(path).lastIndexOf("/")
		return sep >= 0 ? String(path).substring(sep + 1) : String(path)
	}

	function nearestFreeCell(taken, columns, rows, col, row) {
		let best = null
		let bestDist = Infinity
		for (let r = 0; r < rows; r++) {
			for (let c = 0; c < columns; c++) {
				if (taken[c + "," + r])
					continue
				const dist = Math.abs(r - row) + Math.abs(c - col)
				if (dist < bestDist) {
					bestDist = dist
					best = { "c": c, "r": r }
				}
			}
		}
		return best
	}

	function beginReposition(path, sceneX, sceneY, hotspotX, hotspotY) {
		if (!folderGrid.pane || folderGrid.spec.free !== true)
			return false
		let paths = folderGrid.selectedPaths()
		if (paths.indexOf(path) === -1)
			paths = [path]
		const entries = folderGrid.freeSlotList()
			.filter(entry => paths.indexOf(entry.path) !== -1)
		if (entries.length === 0)
			return false
		let anchor = null
		for (const entry of entries) {
			if (entry.path === path) {
				anchor = entry
				break
			}
		}
		if (!anchor) {
			anchor = entries[0]
			for (const entry of entries) {
				if (entry.c < anchor.c || (entry.c === anchor.c && entry.r < anchor.r))
					anchor = entry
			}
		}

		const cw = folderGrid.spec.cell_width || 96
		const ch = folderGrid.spec.cell_height || 96
		const gap = folderGrid.spec.gap || 0
		const items = entries.map(entry => ({
			"path": entry.path,
			"title": entry.title,
			"icon": entry.icon,
			"isDir": entry.isDir,
			"x": (entry.c - anchor.c) * (cw + gap),
			"y": (entry.r - anchor.r) * (ch + gap),
			"w": cw,
			"h": ch
		}))

		folderGrid.repositionActive = true
		if (folderGrid.pane && folderGrid.pane.window)
			folderGrid.pane.window.dragActive = true
		folderGrid.repositionEntries = entries
		folderGrid.repositionAnchor = anchor
		folderGrid.dragPaths = entries.map(entry => entry.path)
		folderGrid.updateReposition(sceneX, sceneY)

		const window = folderGrid.pane.window
		if (window) {
			window.dragPreviewData = {
				"hotspotX": hotspotX,
				"hotspotY": hotspotY,
				"gridSize": folderGrid.spec.icon_size || 48,
				"showLabels": folderGrid.showLabels,
				"labelsBeside": folderGrid.labelsBeside,
				"items": items
			}
			window.dragPreviewActive = true
			window.dragTooltipActive = true
			window.dragTooltipReposition = true
			window.dragTooltipAction = "move"
		}
		return true
	}

	readonly property var viewFlickable: {
		if (folderGrid.spec.free === true || folderGrid.spec.grouped === true)
			return absoluteView
		return folderGrid.spec.mode === "grid" ? grid : list
	}

	// Scroll the view when the drag cursor is within an edge margin. Farther
	// into the margin scrolls faster.
	function updateDragEdgeScroll() {
		const flickable = folderGrid.viewFlickable
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (!flickable || !window || flickable.width <= 0 || flickable.height <= 0)
			return
		const local = flickable.mapFromItem(null, window.dragCursorX,
			window.dragCursorY)
		const margin = Kirigami.Units.gridUnit * 2
		const maxStep = 28
		const horizontal = folderGrid.spec.horizontal === true
		let dx = 0
		let dy = 0
		if (horizontal) {
			if (local.x >= 0 && local.x < margin)
				dx = -Math.ceil((1 - local.x / margin) * maxStep)
			else if (local.x > flickable.width - margin
					&& local.x <= flickable.width)
				dx = Math.ceil((1 - (flickable.width - local.x) / margin) * maxStep)
		} else {
			if (local.y >= 0 && local.y < margin)
				dy = -Math.ceil((1 - local.y / margin) * maxStep)
			else if (local.y > flickable.height - margin
					&& local.y <= flickable.height)
				dy = Math.ceil((1 - (flickable.height - local.y) / margin) * maxStep)
		}
		if (dx !== 0) {
			const maxX = Math.max(0, flickable.contentWidth - flickable.width)
			flickable.contentX = Math.max(0, Math.min(
				flickable.contentX + dx, maxX))
		}
		if (dy !== 0) {
			const maxY = Math.max(0, flickable.contentHeight - flickable.height)
			flickable.contentY = Math.max(0, Math.min(
				flickable.contentY + dy, maxY))
		}
	}

	function beginDragTooltip(modifiers) {
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (!window)
			return
		window.dragActive = true
		window.dragTooltipReposition = false
		if (modifiers & Qt.ShiftModifier)
			window.dragTooltipAction =
				(modifiers & Qt.ControlModifier) ? "link" : "move"
		else
			window.dragTooltipAction = "copy"
		window.dragTooltipActive = true
	}

	function cursorScene() {
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (!window || !window.contentItem)
			return null
		const global = DragHelper.cursorPosition()
		return window.contentItem.mapFromGlobal(global.x, global.y)
	}

	function cursorOutsideWindow(x, y) {
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (!window || !window.contentItem)
			return false
		return x < 0 || y < 0
			|| x > window.contentItem.width || y > window.contentItem.height
	}

	function handOffReposition(grab, width, height) {
		const paths = folderGrid.repositionEntries.map(entry => entry.path)
		const uris = paths.map(path => folderGrid.dragUrl(path))
		folderGrid.clearReposition()
		if (uris.length === 0)
			return
		folderGrid.dragPaths = paths
		folderGrid.beginDragTooltip(0)
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (window) {
			window.dragGhostGrab = grab
			window.dragGhostSource = grab ? String(grab.url) : ""
			window.dragGhostWidth = width
			window.dragGhostHeight = height
			window.dragGhostActive = true
		}
		const nativeDrag = folderGrid.directory
			? folderGrid.directory.config.native_drag : false
		DragHelper.startDragManyFromGrab(grab, uris.join("\n"), nativeDrag)
	}

	function updateReposition(sceneX, sceneY) {
		if (!folderGrid.repositionActive)
			return
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (!window)
			return
		const point = folderGrid.cursorScene()
			|| Qt.point(sceneX, sceneY)
		window.dragCursorX = point.x
		window.dragCursorY = point.y
	}

	function clearReposition() {
		if (folderGrid.pane && folderGrid.pane.window)
			folderGrid.pane.window.dragActive = false
		folderGrid.repositionActive = false
		folderGrid.repositionEntries = []
		folderGrid.repositionAnchor = null
		folderGrid.dragPaths = []
		const window = folderGrid.pane ? folderGrid.pane.window : null
		if (window) {
			window.dragPreviewActive = false
			window.dragPreviewData = null
			window.dragTooltipActive = false
			window.dragTooltipReposition = false
			window.dragTooltipAction = "copy"
		}
	}

	function freeColumns() {
		const cw = folderGrid.spec.cell_width || 96
		const gap = folderGrid.spec.gap || 0
		return Math.max(1, Math.floor((absoluteView.width + gap) / Math.max(1, cw + gap)))
	}

	function freeRows() {
		const ch = folderGrid.spec.cell_height || 96
		const gap = folderGrid.spec.gap || 0
		return Math.max(1, Math.floor((absoluteView.height + gap) / Math.max(1, ch + gap)))
	}

	function freeSlotAt(x, y) {
		const cw = folderGrid.spec.cell_width || 96
		const ch = folderGrid.spec.cell_height || 96
		const gap = folderGrid.spec.gap || 0
		const cx = x + absoluteView.contentX
		const cy = y + absoluteView.contentY
		return {
			"col": Math.max(0, Math.min(folderGrid.freeColumns() - 1, Math.round(
				(cx - folderGrid.freeOffsetX - cw / 2) / Math.max(1, cw + gap)))),
			"row": Math.max(0, Math.min(folderGrid.freeRows() - 1, Math.round(
				(cy - folderGrid.freeOffsetY - ch / 2) / Math.max(1, ch + gap))))
		}
	}

	function endReposition(x, y) {
		if (!folderGrid.repositionActive)
			return false
		const slot = folderGrid.freeSlotAt(x, y)
		const entries = folderGrid.repositionEntries
		const anchor = folderGrid.repositionAnchor
		folderGrid.clearReposition()
		if (!entries.length || !anchor || !folderGrid.directory)
			return false

		const all = folderGrid.freeSlotList()

		let dCol = slot.col - anchor.c
		let dRow = slot.row - anchor.r
		let minCol = 0
		let minRow = 0
		for (const entry of entries) {
			minCol = Math.min(minCol, entry.c + dCol)
			minRow = Math.min(minRow, entry.r + dRow)
		}
		dCol -= minCol
		dRow -= minRow

		const movingTo = ({})
		const movingNames = ({})
		for (const entry of entries) {
			movingTo[(entry.c + dCol) + "," + (entry.r + dRow)] = true
			movingNames[entry.name] = true
		}

		const taken = ({})
		for (const cell in movingTo)
			taken[cell] = true

		const displaced = []
		for (const entry of all) {
			if (movingNames[entry.name])
				continue
			const cell = entry.c + "," + entry.r
			if (movingTo[cell])
				displaced.push(entry)
			else
				taken[cell] = true
		}

		const moved = ({})
		for (const entry of entries)
			moved[entry.name] = [entry.c + dCol, entry.r + dRow]
		folderGrid.directory.set_free_positions(JSON.stringify(moved))

		if (entries.length === 1 && displaced.length === 1) {
			folderGrid.directory.set_free_position(
				displaced[0].name, entries[0].c, entries[0].r)
		} else {
			for (const entry of displaced) {
				const cell = folderGrid.nearestFreeCell(
					taken, folderGrid.freeColumns(), folderGrid.freeRows(),
					entry.c, entry.r)
				if (!cell)
					continue
				taken[cell.c + "," + cell.r] = true
				folderGrid.directory.set_free_position(entry.name, cell.c, cell.r)
			}
		}
		folderGrid.directory.clear_selection()
		return true
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
		const cx = drop.x + absoluteView.contentX
		const cy = drop.y + absoluteView.contentY
		const column = Math.max(0, Math.round(
			(cx - folderGrid.freeOffsetX - cw / 2) / Math.max(1, cw + gap)))
		const row = Math.max(0, Math.round(
			(cy - folderGrid.freeOffsetY - ch / 2) / Math.max(1, ch + gap)))
		pane.directory.set_free_position(name, column, row)
		drop.acceptProposedAction()
		return true
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
	readonly property real gridOffsetX: folderGrid.alignOffset(folderGrid.horizontalAlign,
		content.width, folderGrid.naturalWidth)
	readonly property real gridOffsetY: folderGrid.alignOffset(folderGrid.verticalAlign,
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
	readonly property real freeOffsetX: folderGrid.alignOffset(folderGrid.horizontalAlign,
		content.width, folderGrid.freeNaturalWidth)
	readonly property real freeOffsetY: folderGrid.alignOffset(folderGrid.verticalAlign,
		content.height, folderGrid.freeNaturalHeight)
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

	function dragUrl(path) {
		return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
	}

	function listColumnValues(row) {
		return folderGrid.listColumns.map(key => ({
			"text": folderGrid.columnText(key, row),
			"width": folderGrid.columnWidth(key),
			"fill": folderGrid.isFillColumn(key),
			"nameColumn": folderGrid.isFillColumn(key),
			"align": key === "SIZE" ? Text.AlignRight : Text.AlignLeft
		}))
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
					if (folderGrid.repositionFromDrop(drop))
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
				flow: folderGrid.spec.horizontal
					? GridView.TopToBottom : GridView.LeftToRight
				cacheBuffer: Math.max(folderGrid.spec.cell_width || 96,
					folderGrid.spec.cell_height || 96) * 4

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
					required property bool is_symlink
					required property int control_kind
					required property string number_value

					property string thumb: ""
					property var dragGrab: null
					Component.onCompleted: {
						if (is_image)
							thumb = pane.directory.thumbnail(path, 96)
						dragGrab = cell.grabToImage(function (result) {
							cell.dragGrab = result
						})
					}


					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: grid.cellWidth
					height: grid.cellHeight

					FileSlot {
						anchors.fill: parent
						name: cell.name
						title: cell.title
						icon: cell.icon
						thumb: cell.thumb
						isDirectory: cell.is_directory
						isSymlink: cell.is_symlink
						controlKind: cell.control_kind
						numberValue: cell.number_value
						radioActive: folderGrid.isRadioMember(
							cell.path, cell.is_directory, cell.name)
						radioSelected: folderGrid.isRadioSelected(
							cell.path, cell.is_directory, cell.name)
						selected: cell.selected
						active: (pane.active && pane.directory.focused_path === cell.path)
							|| folderGrid.isRadioSelected(
								cell.path, cell.is_directory, cell.name)
						showLabels: folderGrid.showLabels
						labelsBeside: folderGrid.labelsBeside
						iconSize: folderGrid.spec.icon_size || 48
						hovered: dragArea.containsMouse
						pressed: dragArea.pressed
						dragging: folderGrid.isDragging(cell.path)
						dotfile: cell.name.startsWith(".")
						selectionActive: pane.directory.selectionActive
						labelShowsFilename: String(
							pane.directory.config.label_text) === "FILENAME"
						dropHovered: cellDrop.containsDrag
					}
					DropArea {
						id: cellDrop
						anchors.fill: parent
						enabled: cell.is_directory
						onEntered: if (cell.is_directory) pane.springEnter(cell.path)
						onExited: pane.springLeave()
						onDropped: function (drop) {
							pane.springLeave()
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
						hoverEnabled: true
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
							folderGrid.startDrag(cell.dragGrab, path, mouse.modifiers,
								cell.width, cell.height)
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
					required property bool is_symlink
					required property int control_kind
					required property string number_value
					required property var size_bytes
					required property var modified_time
					required property var created_time
					required property var accessed_time

					property string thumb: ""
					property var dragGrab: null
					Component.onCompleted: {
						if (is_image)
							thumb = pane.directory.thumbnail(path, 32)
						dragGrab = row.grabToImage(function (result) {
							row.dragGrab = result
						})
					}


					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(path)
					}

					width: ListView.view.width
					height: 30
					color: "transparent"

					FileSlot {
						anchors.fill: parent
						listMode: true
						name: row.name
						title: row.title
						icon: row.icon
						thumb: row.thumb
						isDirectory: row.is_directory
						isSymlink: row.is_symlink
						controlKind: row.control_kind
						numberValue: row.number_value
						radioActive: folderGrid.isRadioMember(
							row.path, row.is_directory, row.name)
						radioSelected: folderGrid.isRadioSelected(
							row.path, row.is_directory, row.name)
						selected: row.selected
						active: (pane.active && pane.directory.focused_path === row.path)
							|| folderGrid.isRadioSelected(
								row.path, row.is_directory, row.name)
						showLabels: true
						columnValues: folderGrid.listColumnValues(row)
						hovered: rowDrag.containsMouse
						pressed: rowDrag.pressed
						dragging: folderGrid.isDragging(row.path)
						dotfile: row.name.startsWith(".")
						selectionActive: pane.directory.selectionActive
						labelShowsFilename: String(
							pane.directory.config.label_text) === "FILENAME"
						dropHovered: rowDrop.containsDrag
					}
					DropArea {
						id: rowDrop
						anchors.fill: parent
						enabled: row.is_directory
						onEntered: if (row.is_directory) pane.springEnter(row.path)
						onExited: pane.springLeave()
						onDropped: function (drop) {
							pane.springLeave()
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
						hoverEnabled: true
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
							folderGrid.startDrag(row.dragGrab, path, mouse.modifiers,
								row.width, row.height)
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
						if (folderGrid.repositionFromDrop(drop))
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

					property string thumb: ""
					property var dragGrab: null
					Component.onCompleted: {
						if (modelData.is_image)
							thumb = pane.directory.thumbnail(modelData.path, 64)
						dragGrab = freeSlot.grabToImage(function (result) {
							freeSlot.dragGrab = result
						})
					}

					readonly property bool selected: {
						pane.directory.selectionRevision
						return pane.directory.is_selected(modelData.path)
					}


					FileSlot {
						anchors.fill: parent
						name: modelData.name
						title: modelData.title || ""
						icon: modelData.icon
						thumb: freeSlot.thumb
						isDirectory: modelData.is_directory
						isSymlink: modelData.is_symlink === true
						controlKind: modelData.control_kind || 0
						numberValue: modelData.number_value || ""
						radioActive: folderGrid.isRadioMember(
							modelData.path, modelData.is_directory, modelData.name)
						radioSelected: folderGrid.isRadioSelected(
							modelData.path, modelData.is_directory, modelData.name)
						selected: freeSlot.selected
						active: (pane.active
								&& pane.directory.focused_path === modelData.path)
							|| folderGrid.isRadioSelected(
								modelData.path, modelData.is_directory, modelData.name)
						showLabels: folderGrid.showLabels
						labelsBeside: folderGrid.labelsBeside
						iconSize: folderGrid.spec.icon_size || 48
						hovered: freeDrag.containsMouse
						pressed: freeDrag.pressed
						dragging: folderGrid.isDragging(modelData.path)
						dotfile: modelData.name.startsWith(".")
						selectionActive: pane.directory.selectionActive
						labelShowsFilename: String(
							pane.directory.config.label_text) === "FILENAME"
						dropHovered: freeDrop.containsDrag
					}
					DropArea {
						id: freeDrop
						anchors.fill: parent
						enabled: modelData.is_directory === true
						onEntered: if (modelData.is_directory === true) pane.springEnter(modelData.path)
						onExited: pane.springLeave()
						onDropped: function (drop) {
							pane.springLeave()
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
						hoverEnabled: true
						acceptedButtons: Qt.LeftButton | Qt.RightButton

						property bool dragging: false
						property bool repositioning: false
						property bool handedOff: false
						property bool suppressClick: false
						property point pressPoint
						property point lastPoint

						onPressed: function (mouse) {
							dragging = false
							repositioning = false
							handedOff = false
							suppressClick = false
							pressPoint = Qt.point(mouse.x, mouse.y)
							lastPoint = pressPoint
						}
						onPositionChanged: function (mouse) {
							lastPoint = Qt.point(mouse.x, mouse.y)
							if (repositioning) {
								const scene = folderGrid.cursorScene()
									|| freeDrag.mapToItem(null, mouse.x, mouse.y)
								if (folderGrid.cursorOutsideWindow(scene.x, scene.y)) {
									folderGrid.handOffReposition(freeSlot.dragGrab,
									freeSlot.width, freeSlot.height)
									repositioning = false
									handedOff = true
									suppressClick = true
									return
								}
								folderGrid.updateReposition(scene.x, scene.y)
								return
							}
							if (dragging || !pressed)
								return
							const dx = mouse.x - pressPoint.x
							const dy = mouse.y - pressPoint.y
							if (dx * dx + dy * dy < 36)
								return
							dragging = true
							const scene = folderGrid.cursorScene()
								|| freeDrag.mapToItem(null, mouse.x, mouse.y)
							if (folderGrid.beginReposition(modelData.path,
									scene.x, scene.y, pressPoint.x, pressPoint.y)) {
								repositioning = true
								return
							}
							folderGrid.startDrag(freeSlot.dragGrab,
								modelData.path, mouse.modifiers,
								freeSlot.width, freeSlot.height)
						}
						onReleased: {
							if (handedOff) {
								handedOff = false
								dragging = false
								return
							}
							if (repositioning) {
								folderGrid.updateReposition()
								const window = folderGrid.pane
									? folderGrid.pane.window : null
								let point = null
								if (window)
									point = folderGrid.mapFromItem(null,
										window.dragCursorX, window.dragCursorY)
								else
									point = freeDrag.mapToItem(folderGrid,
										lastPoint.x, lastPoint.y)
								folderGrid.endReposition(point.x, point.y)
								repositioning = false
								suppressClick = true
							}
							dragging = false
						}
						onClicked: function (mouse) {
							if (dragging || repositioning || suppressClick) {
								dragging = false
								repositioning = false
								suppressClick = false
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



}
