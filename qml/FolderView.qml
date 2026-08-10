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

	// ── Selection state (shared upward via selectionState) ────────────────
	property var selectionState: null

	property bool selectionActive: false
	// Map of path -> true for selected items
	property var selectedPaths: ({})
	readonly property int selectedCount: Object.keys(folderView.selectedPaths).length
	// Index of the last item touched (for shift-click range)
	property int lastSelectedIndex: -1

	// Propagate our selection state up to the shared object
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

	// ── Selection functions ───────────────────────────────────────────────

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
		folderView.selectedPaths = sel;
		folderView.lastSelectedIndex = idx;
	}

	// Select all items between fromIndex and toIndex (inclusive), adding to selection
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
		folderView.selectedPaths = sel;
	}

	function selectAll() {
		var sel = {};
		var count = folderView.directory.row_count();
		for (var i = 0; i < count; i++) {
			var p = folderView.directory.data(folderView.directory.index(i, 0), 0x0101);
			if (p) sel[p] = true;
		}
		folderView.selectedPaths = sel;
	}

	function deselectAll() {
		folderView.selectedPaths = {};
		folderView.lastSelectedIndex = -1;
	}

	// ── Lifecycle / connections ───────────────────────────────────────────

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

	// ── Background ────────────────────────────────────────────────────────

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

	// ── Keyboard: Space to enter selection mode ───────────────────────────
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

	// ── File grid ─────────────────────────────────────────────────────────

	Flickable {
		id: flickable
		anchors {
			top: parent.top
			left: parent.left
			right: parent.right
			// Leave room for the selection bar at the bottom when active
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

	// ── Selection bar ─────────────────────────────────────────────────────

	Rectangle {
		id: selectionBar

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

		// Top separator
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
				display: AbstractButton.IconOnly
				ToolTip.text: qsTr("Select All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.selectAll()
			}

			ToolButton {
				text: qsTr("Deselect All")
				icon.name: "edit-select-none"
				display: AbstractButton.IconOnly
				ToolTip.text: qsTr("Deselect All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.deselectAll()
			}

			// Separator
			Rectangle {
				width: 1
				height: 24
				color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
				Layout.leftMargin: Kirigami.Units.smallSpacing
				Layout.rightMargin: Kirigami.Units.smallSpacing
			}

			ToolButton {
				icon.name: "window-close"
				display: AbstractButton.IconOnly
				flat: true
				ToolTip.text: qsTr("Exit Selection Mode")
				ToolTip.visible: hovered
				onClicked: folderView.exitSelectionMode()
			}
		}
	}
}
