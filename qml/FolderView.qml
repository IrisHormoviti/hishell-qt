pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Hishell"
import "toolkit"

Item {
	id: folderView
	property Directory directory
	property Config config: directory.config
	property Directory windowDirectory: folderView.directory

	property var selectionState: null
	property bool selectionActive: false
	// Map of path -> true for selected items
	property var selectedPaths: ({})
	readonly property int selectedCount: Object.keys(folderView.selectedPaths).length
	// Index of the last selected item, used in range selection
	property int lastSelectedIndex: -1

	// Drag n Drop stuff
	property string dragAction: "copy" // "copy", "move", "link"
	property bool dragActive: false
	property real dragCursorX: 0
	property real dragCursorY: 0
	property string dragIcon: ""
	property string dragTitle: ""
	property int dragItemCount: 1
	property var shakePositions: []

	function trackMouseShake(x, y) {
		folderView.dragCursorX = x;
		folderView.dragCursorY = y;
		folderView.dragActive = true;

		var now = Date.now();
		var history = folderView.shakePositions.slice();
		history.push({ x: x, y: y, time: now });

		// Filter entries older than 450ms
		history = history.filter(function(p) { return now - p.time <= 450; });
		folderView.shakePositions = history;

		if (history.length < 5) return;

		var reversals = 0;
		var lastDx = 0;
		var lastDy = 0;
		var totalDistance = 0;

		for (var i = 1; i < history.length; i++) {
			var dx = history[i].x - history[i - 1].x;
			var dy = history[i].y - history[i - 1].y;
			var dist = Math.sqrt(dx * dx + dy * dy);
			totalDistance += dist;

			if ((dx > 3 && lastDx < -3) || (dx < -3 && lastDx > 3)) {
				reversals++;
			} else if ((dy > 3 && lastDy < -3) || (dy < -3 && lastDy > 3)) {
				reversals++;
			}

			if (Math.abs(dx) > 2) lastDx = dx;
			if (Math.abs(dy) > 2) lastDy = dy;
		}

		if (reversals >= 3 && totalDistance > 50) {
			cycleDragAction();
			folderView.shakePositions = [];
		}
	}

	function cycleDragAction() {
		if (folderView.dragAction === "copy") {
			folderView.dragAction = "move";
		} else if (folderView.dragAction === "move") {
			folderView.dragAction = "link";
		} else {
			folderView.dragAction = "copy";
		}
	}

	onSelectionActiveChanged: {
		if (folderView.selectionState) {
			folderView.selectionState.selectionActive = folderView.selectionActive;
		}
	}
	onSelectedPathsChanged: {
		if (folderView.selectionState) {
			folderView.selectionState.selectedPaths = folderView.selectedPaths;
			folderView.selectionState.selectedCount = folderView.selectedCount;
		}
	}

	function enterSelectionMode() {
		folderView.selectionActive = true;
	}

	function exitSelectionMode() {
		folderView.selectionActive = false;
		folderView.selectedPaths = {};
		folderView.lastSelectedIndex = -1;
	}

	function toggleSelection(path, idx) {
		if (!folderView.selectionActive) {
			folderView.enterSelectionMode();
		}
		var sel = Object.assign({}, folderView.selectedPaths);
		if (sel[path]) {
			delete sel[path];
		} else {
			sel[path] = true;
		}

		folderView.selectedPaths = Object.assign({}, sel);

		folderView.lastSelectedIndex = idx;
		if (folderView.selectedCount === 0) {
			exitSelectionMode();
		}
	}

	function rangeSelect(fromIndex, toIndex) {
		var lo = Math.min(fromIndex, toIndex);
		var hi = Math.max(fromIndex, toIndex);
		var sel = Object.assign({}, folderView.selectedPaths);
		for (var i = lo; i <= hi; i++) {
			var itemPath = folderView.directory.data(folderView.directory.index(i, 0), 0x0101);
			if (itemPath) {
				sel[itemPath] = true;
			}
		}

		folderView.selectedPaths = Object.assign({}, sel);
	}

	function selectAll() {
		var sel = {};
		var count = folderView.directory.row_count();
		for (var i = 0; i < count; i++) {
			var p = folderView.directory.data(folderView.directory.index(i, 0), 0x0101);
			if (p) sel[p] = true;
		}

		folderView.selectedPaths = Object.assign({}, sel);
	}


	function deselectAll() {
		folderView.selectedPaths = {};
		folderView.lastSelectedIndex = -1;
		exitSelectionMode();
	}

	Layout.fillWidth: true
	Layout.fillHeight: true

	Component.onCompleted: {
		Qt.callLater(() => {
			if (folderView.config && folderView.directory) {
				folderView.config.load(folderView.directory.path);
				folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
			} else {
				console.error("FolderView: missing directory or config.");
			}
		});
	}

	Timer {
		interval: 400
		running: true
		repeat: true
		onTriggered: {
			if (folderView.directory) {
				folderView.directory.poll_thumbnails()
			}
		}
	}

	Connections {
		target: folderView.directory
		function onPathChanged() {
			if (folderView.config && folderView.directory) {
				folderView.config.load(folderView.directory.path);
				folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
			}
			// Clear selection when navigating
			folderView.exitSelectionMode();
		}
		function onConfig_changed() {
			console.log("we got em")
			folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
		}
	}

	property var positions: {
		try {
			return JSON.parse(folderView.config.arbitrary_positions);
		} catch (e) {
			return {};
		}
	}

	readonly property string folderName: {
		let path = folderView.directory.path.toString();
		if (!path || path === "/" || path === ".")
			return "/";
		if (path.endsWith("/") && path.length > 1) {
			path = path.substring(0, path.length - 1);
		}
		let name = path.split("/").pop();
		return name !== "" ? name : "/";
	}

	Kirigami.Theme.colorSet: Kirigami.Theme.View

	Binding {
		target: folderView.Window.window
		property: "title"
		value: folderView.folderName
		restoreMode: Binding.RestoreBindingOrValue
	}

	// ── Background ──

	Image {
		id: wallpaper
		anchors.fill: parent
		source: String(folderView.config ? folderView.config.wallpaper : "")
		fillMode: Image.PreserveAspectCrop
		visible: status === Image.Ready
	}

	Rectangle {
		anchors.fill: parent
		color: wallpaper.status === Image.Ready ? "transparent" : Kirigami.Theme.backgroundColor
		radius: 8
		anchors.margins: 4
	}

	function isDropValid(targetPath, sourcePaths) {
		if (!targetPath || targetPath === "" || !sourcePaths || sourcePaths.length === 0) {
			return false;
		}

		var normTarget = String(targetPath);
		if (normTarget.length > 1 && normTarget.endsWith("/")) {
			normTarget = normTarget.substring(0, normTarget.length - 1);
		}

		for (var i = 0; i < sourcePaths.length; i++) {
			var src = String(sourcePaths[i]);
			if (!src || src === "") continue;

			if (src.indexOf("file://") === 0) {
				src = src.substring(7);
			}

			if (src.length > 1 && src.endsWith("/")) {
				src = src.substring(0, src.length - 1);
			}

			var lastSlash = src.lastIndexOf("/");
			var srcParent = lastSlash > 0 ? src.substring(0, lastSlash) : (lastSlash === 0 ? "/" : "");

			// Cannot drop into the exact same parent folder
			if (normTarget === srcParent) {
				return false;
			}

			// Cannot drop folder into itself or a subfolder of itself
			if (normTarget === src || normTarget.indexOf(src + "/") === 0) {
				return false;
			}
		}

		return true;
	}

	// Active Drop Highlight Border around folderView background
	Rectangle {
		anchors.fill: parent
		anchors.margins: 4
		radius: 8
		color: "transparent"
		border.color: Kirigami.Theme.highlightColor
		border.width: 3
		z: 10
		opacity: bgDropArea.isHovered ? 0.85 : 0.0
		Behavior on opacity { NumberAnimation { duration: 120 } }
	}

	// Background Drop Area for dropping files into current directory
	DropArea {
		id: bgDropArea
		anchors.fill: parent
		keys: ["text/uri-list", "text/plain"]
		z: 0

		property bool isHovered: false

		onEntered: (drag) => {
			var sourcePaths = [];
			if (typeof rootDragHandle !== 'undefined' && rootDragHandle.dragSourcePaths && rootDragHandle.dragSourcePaths.length > 0) {
				sourcePaths = rootDragHandle.dragSourcePaths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			if (!folderView.isDropValid(folderView.directory.path, sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof rootDragHandle !== 'undefined') rootDragHandle.tooltipActive = false;
				drag.accepted = false;
				return;
			}

			bgDropArea.isHovered = true;
			if (typeof rootDragHandle !== 'undefined') {
				rootDragHandle.tooltipActive = true;
				var pt = bgDropArea.mapToItem(null, drag.x, drag.y);
				rootDragHandle.trackMouseShake(pt.x, pt.y);
			}
			drag.accept();
		}

		onPositionChanged: (drag) => {
			var sourcePaths = [];
			if (typeof rootDragHandle !== 'undefined' && rootDragHandle.dragSourcePaths && rootDragHandle.dragSourcePaths.length > 0) {
				sourcePaths = rootDragHandle.dragSourcePaths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			if (!folderView.isDropValid(folderView.directory.path, sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof rootDragHandle !== 'undefined') rootDragHandle.tooltipActive = false;
				drag.accepted = false;
				return;
			}

			bgDropArea.isHovered = true;
			if (typeof rootDragHandle !== 'undefined') {
				rootDragHandle.tooltipActive = true;
				var pt = bgDropArea.mapToItem(null, drag.x, drag.y);
				rootDragHandle.trackMouseShake(pt.x, pt.y);
			}
		}

		onExited: {
			bgDropArea.isHovered = false;
			if (typeof rootDragHandle !== 'undefined') rootDragHandle.tooltipActive = false;
		}

		onDropped: (drop) => {
			bgDropArea.isHovered = false;
			if (typeof rootDragHandle !== 'undefined') rootDragHandle.tooltipActive = false;

			var uris = "";
			if (typeof rootDragHandle !== 'undefined' && rootDragHandle.dragUris && rootDragHandle.dragUris.length > 0) {
				uris = rootDragHandle.dragUris.join("\n");
			} else if (drop.source && drop.source.dragUris) {
				uris = drop.source.dragUris.join("\n");
			} else if (drop.hasUrls) {
				uris = drop.urls.join("\n");
			} else if (drop.hasText) {
				uris = drop.text;
			}

			if (uris.length > 0 && typeof fileManager !== 'undefined' && fileManager) {
				var action = (typeof rootDragHandle !== 'undefined' && rootDragHandle.dragAction) ? rootDragHandle.dragAction : "copy";
				if (fileManager.process_uris_action(folderView.directory.path, uris, action)) {
					folderView.directory.refresh();
				}
				drop.accept();
			}
		}
	}

	DragTooltip {
		active: folderView.dragActive
		action: folderView.dragAction
		cursorX: folderView.dragCursorX + 16
		cursorY: folderView.dragCursorY + 16
	}

	// ── Input stuff ---
	Keys.onPressed: (event) => {
		if (event.key === Qt.Key_Space && !folderView.selectionActive) {
			folderView.enterSelectionMode();
			event.accepted = true;
		} else if (event.key === Qt.Key_Escape && folderView.selectionActive) {
			folderView.exitSelectionMode();
			event.accepted = true;
		} else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
			if (!folderView.selectionActive) folderView.enterSelectionMode();
			folderView.selectAll();
			event.accepted = true;
		}
	}
	focus: true

	// ── Grid ───

	Flickable {
		id: flickable
		z: 1
		anchors {
			top: parent.top
			left: parent.left
			right: parent.right
			bottom: selectionBar.top
		}
		anchors.margins: Kirigami.Units.mediumSpacing
		contentWidth: width
		contentHeight: flowLayout.height

		Flow {
			id: flowLayout
			width: parent.width
			spacing: Kirigami.Units.mediumSpacing

			Repeater {
				id: itemRepeater
				model: folderView.directory

				delegate: FileSlot {

					width: labelBesideIcon ? Kirigami.Units.gridUnit * 10 : gridSize + Kirigami.Units.gridUnit * 3
					height: labelBesideIcon ? Kirigami.Units.gridUnit * 2 : gridSize + Kirigami.Units.gridUnit * 3

					gridSize: folderView.config.grid_size
					selectionActive: folderView.selectionActive
					isSelected: !!folderView.selectedPaths[path]

					onNavigate: (targetPath) => {
						(folderView.windowDirectory || folderView.directory).open_path(targetPath)
					}

					onSelectionToggled: (p, idx) => {
						folderView.toggleSelection(p, idx);
					}

					onShiftSelected: (idx) => {
						if (!folderView.selectionActive) folderView.enterSelectionMode();
						var from = folderView.lastSelectedIndex >= 0 ? folderView.lastSelectedIndex : idx;
						folderView.rangeSelect(from, idx);
						folderView.lastSelectedIndex = idx;
					}

					onPressHeld: (p, idx) => {
						folderView.toggleSelection(p, idx);
					}
				}
			}
		}
	}

	// ── Selection Toolbar ───

	Rectangle {
		id: selectionBar
		z: 2

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.margins: 4
		anchors.bottomMargin: 4

		height: selectionActive ? 48 : 0
		visible: selectionActive
		radius: 6

		Kirigami.Theme.colorSet: Kirigami.Theme.Header
		color: Kirigami.Theme.backgroundColor

		Kirigami.Separator {
			anchors.top: parent.top
			anchors.left: parent.left
			anchors.right: parent.right
		}

		Behavior on height {
			NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
		}

		RowLayout {
			anchors.fill: parent
			anchors.leftMargin: Kirigami.Units.largeSpacing
			anchors.rightMargin: Kirigami.Units.smallSpacing
			spacing: Kirigami.Units.smallSpacing

			Kirigami.Icon {
				source: "checkmark"
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Kirigami.Units.iconSizes.small
			}

			Label {
				text: {
					var n = folderView.selectedCount;
					return n === 1 ? qsTr("1 item selected") : qsTr("%1 items selected").arg(n);
				}
				font.weight: Font.Medium
				Layout.fillWidth: true
			}

			ToolButton {
				text: qsTr("Select All")
				icon.name: "edit-select-all"
				// display: AbstractButton.IconOnly
				ToolTip.text: qsTr("Select All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.selectAll()
			}

			ToolButton {
				text: qsTr("Deselect All")
				icon.name: "edit-select-none"
				// display: AbstractButton.IconOnly
				ToolTip.text: qsTr("Deselect All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.deselectAll()
			}
		}
	}
}
