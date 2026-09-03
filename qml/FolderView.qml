pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Hishell"
import "toolkit"
import "."

Item {
	id: folderView
	property ShellWindow window
	property Directory directory
	property Config config: directory.config

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
				folderView.directory.poll_thumbnails();
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
			if (folderView.window.selectionManager) {
				folderView.window.selectionManager.exit_selection_mode();
			}
		}
		function onConfig_changed() {
			console.log("we got em");
			folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
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

	// Use DropValidator from Rust
	function isDropValid(targetPath, sourcePaths) {
		return dropValidator.is_drop_valid(targetPath, sourcePaths);
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
		Behavior on opacity {
			NumberAnimation {
				duration: 120
			}
		}
	}

	// Background Drop Area for dropping files into current directory
	DropArea {
		id: bgDropArea
		anchors.fill: parent
		keys: ["text/uri-list", "text/plain"]
		z: 0

		property bool isHovered: false
		property var dragHandler: folderView.window.dragDropHandler

		onEntered: drag => {
			var sourcePaths = [];
			if (typeof dragHandler !== 'undefined' && dragHandler.drag_source_paths && dragHandler.drag_source_paths.length > 0) {
				sourcePaths = dragHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			if (!folderView.isDropValid(folderView.directory.path, sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof dragHandler !== 'undefined')
					dragHandler.tooltip_active = false;
				drag.accepted = false;
				return;
			}

			bgDropArea.isHovered = true;
			if (typeof dragHandler !== 'undefined') {
				dragHandler.tooltip_active = true;
				var pt = bgDropArea.mapToItem(null, drag.x, drag.y);
				dragHandler.track_mouse_shake(pt.x, pt.y);
			}
			drag.accept();
		}

		onPositionChanged: drag => {
			var sourcePaths = [];
			if (typeof dragHandler !== 'undefined' && dragHandler.drag_source_paths && dragHandler.drag_source_paths.length > 0) {
				sourcePaths = dragHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			if (!folderView.isDropValid(folderView.directory.path, sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof dragHandler !== 'undefined')
					dragHandler.tooltip_active = false;
				drag.accepted = false;
				return;
			}

			bgDropArea.isHovered = true;
			if (typeof dragHandler !== 'undefined') {
				dragHandler.tooltip_active = true;
				var pt = bgDropArea.mapToItem(null, drag.x, drag.y);
				dragHandler.track_mouse_shake(pt.x, pt.y);
			}
			drag.accept();
		}

		onExited: {
			bgDropArea.isHovered = false;
			if (typeof dragHandler !== 'undefined')
				dragHandler.tooltip_active = false;
		}

		onDropped: drop => {
			bgDropArea.isHovered = false;
			if (typeof dragHandler !== 'undefined')
				dragHandler.tooltip_active = false;

			var uris = "";
			if (typeof dragHandler !== 'undefined' && dragHandler.drag_uris && dragHandler.drag_uris.length > 0) {
				uris = dragHandler.drag_uris.join("\n");
			} else if (drop.source && drop.source.dragUris) {
				uris = drop.source.dragUris.join("\n");
			} else if (drop.hasUrls) {
				uris = drop.urls.join("\n");
			} else if (drop.hasText) {
				uris = drop.text;
			}

			if (uris.length > 0 && typeof fileManager !== 'undefined' && fileManager) {
				var action = (typeof dragHandler !== 'undefined' && dragHandler.drag_action) ? dragHandler.drag_action : "copy";
				if (fileManager.process_uris_action(folderView.directory.path, uris, action)) {
					folderView.directory.refresh();
				}
				drop.accept();
			}
		}
	}

	DragTooltip {
		property var dragHandler: folderView.window.dragDropHandler

		active: dragHandler.tooltip_active
		action: dragHandler.drag_action
		cursorX: dragHandler.drag_cursor_x + 16
		cursorY: dragHandler.drag_cursor_y + 16
	}

	// ── Input stuff ---
	Keys.onPressed: event => {
		if (event.key === Qt.Key_Space && !(folderView.window.selectionManager && folderView.window.selectionManager.selection_active)) {
			if (folderView.window.selectionManager) {
				folderView.window.selectionManager.enter_selection_mode();
			}
			event.accepted = true;
		} else if (event.key === Qt.Key_Escape && folderView.window.selectionManager && folderView.window.selectionManager.selection_active) {
			folderView.window.selectionManager.exit_selection_mode();
			event.accepted = true;
		} else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
			if (folderView.window.selectionManager) {
				if (!folderView.window.selectionManager.selection_active)
					folderView.window.selectionManager.enter_selection_mode();
				folderView.window.selectionManager.select_all();
			}
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
					property SelectionManager selectionManager: folderView.window.selectionManager

					dragDropHandler: folderView.window.dragDropHandler
					width: labelBesideIcon ? Kirigami.Units.gridUnit * 10 : gridSize + Kirigami.Units.gridUnit * 3
					height: labelBesideIcon ? Kirigami.Units.gridUnit * 2 : gridSize + Kirigami.Units.gridUnit * 3

					gridSize: folderView.config.grid_size
					selectionActive: selectionManager ? selectionManager.selection_active : false
					isSelected: selectionManager ? !!selectionManager.selected_paths[path] : false

					onNavigate: targetPath => {
						(folderView.window.directory || folderView.directory).open_path(targetPath);
					}

					onSelectionToggled: (p, idx) => {
						if (selectionManager) {
							selectionManager.toggle_selection(p, idx);
						}
					}

					onShiftSelected: idx => {
						if (selectionManager) {
							if (!selectionManager.selection_active)
								selectionManager.enter_selection_mode();
							var from = selectionManager.last_selected_index >= 0 ? selectionManager.last_selected_index : idx;
							selectionManager.range_select(from, idx);
						}
					}

					onPressHeld: (p, idx) => {
						if (selectionManager) {
							selectionManager.toggle_selection(p, idx);
						}
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

		height: (folderView.window.selectionManager && folderView.window.selectionManager.selection_active) ? 48 : 0
		visible: folderView.window.selectionManager && folderView.window.selectionManager.selection_active
		radius: 6

		Kirigami.Theme.colorSet: Kirigami.Theme.Header
		color: Kirigami.Theme.backgroundColor

		Kirigami.Separator {
			anchors.top: parent.top
			anchors.left: parent.left
			anchors.right: parent.right
		}

		Behavior on height {
			NumberAnimation {
				duration: 180
				easing.type: Easing.OutCubic
			}
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
					var n = folderView.window.selectionManager ? folderView.window.selectionManager.selected_count : 0;
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
				onClicked: if (folderView.window.selectionManager)
					folderView.window.selectionManager.select_all()
			}

			ToolButton {
				text: qsTr("Deselect All")
				icon.name: "edit-select-none"
				// display: AbstractButton.IconOnly
				ToolTip.text: qsTr("Deselect All")
				ToolTip.visible: hovered
				flat: true
				onClicked: if (folderView.window.selectionManager)
					folderView.window.selectionManager.deselect_all()
			}
		}
	}
}
