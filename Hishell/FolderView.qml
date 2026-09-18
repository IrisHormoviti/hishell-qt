pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: folderView
	property ShellWindow window
	readonly property ShellWindow rootWindow: folderView.window
	property Directory directory
	property Config config: directory.config

	Layout.fillWidth: true
	Layout.fillHeight: true

	focus: true

	function selectAll() {
		const mgr = folderView.rootWindow ? folderView.rootWindow.selectionManager : null;
		if (!mgr)
			return;
		let paths = [];
		for (let i = 0; i < itemRepeater.count; i++) {
			let item = itemRepeater.itemAt(i);
			if (item && item.path) {
				paths.push(item.path);
			}
		}
		mgr.select_all(paths);
	}

	Item {
		id: externalOpenAnimation
		z: 3
		visible: false
		transformOrigin: Item.Center

		Image {
			id: externalOpenImage
			anchors.fill: parent
			fillMode: Image.PreserveAspectFit
			smooth: true
		}

		ParallelAnimation {
			id: externalOpenAnimationEffect
			NumberAnimation {
				target: externalOpenAnimation
				property: "scale"
				from: 1.0
				to: 1.5
				duration: 220
				easing.type: Easing.OutCubic
			}
			NumberAnimation {
				target: externalOpenAnimation
				property: "opacity"
				from: 1.0
				to: 0.0
				duration: 220
				easing.type: Easing.InCubic
			}
			onFinished: {
				externalOpenAnimation.visible = false;
				externalOpenAnimation.scale = 1.0;
				externalOpenAnimation.opacity = 1.0;
			}
		}
	}

	Component.onCompleted: {
		folderView.forceActiveFocus();
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
			if (folderView.rootWindow && folderView.rootWindow.selectionManager) {
				folderView.rootWindow.selectionManager.exit_selection_mode();
			}
		}

		function onConfig_changed() {
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

	ContextMenu.menu: ShellContextMenu {
		actionManager: folderView.rootWindow.actionManager
		targetIsBackground: true
	}
	ContextMenu.onRequested: {
		if (folderView.rootWindow)
			folderView.rootWindow.actionManager.pasteTargetPath = "";
	}

	MouseArea {
		id: backgroundMouseArea
		anchors.fill: parent
		z: -1
		acceptedButtons: Qt.LeftButton

		onClicked: mouse => {
			if (mouse.button === Qt.LeftButton) {
				folderView.forceActiveFocus();
				if (folderView.rootWindow && folderView.rootWindow.selectionManager)
					folderView.rootWindow.selectionManager.clear();
			}
		}
	}

	function isDropValid(targetPath, sourcePaths) {
		return window.dropValidator.is_drop_valid(targetPath, sourcePaths);
	}

	// Active Drop Highlight Border
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

	DropArea {
		id: bgDropArea
		anchors.fill: parent
		keys: ["text/uri-list", "text/plain"]
		z: 0

		property bool isHovered: false
		property FileManager fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null
		property DragDropHandler dragHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null

		onEntered: drag => {
			checkDrop(drag);
		}

		onPositionChanged: drag => {
			checkDrop(drag);
		}

		function checkDrop(drag) {
			let sourcePaths = [];
			if (typeof dragHandler !== 'undefined' && dragHandler && dragHandler.drag_source_paths && dragHandler.drag_source_paths.length > 0) {
				sourcePaths = dragHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			if (!folderView.isDropValid(folderView.directory.path, sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof dragHandler !== 'undefined' && dragHandler)
					dragHandler.tooltip_active = false;
				drag.accepted = false;
				return;
			}

			bgDropArea.isHovered = true;
			if (typeof dragHandler !== 'undefined' && dragHandler) {
				dragHandler.tooltip_active = true;
				const pt = bgDropArea.mapToItem(null, drag.x, drag.y);
				dragHandler.track_mouse_shake(pt.x, pt.y);
			}
			drag.accept();
		}

		onExited: {
			bgDropArea.isHovered = false;
			if (typeof dragHandler !== 'undefined' && dragHandler)
				dragHandler.tooltip_active = false;
		}

		onDropped: drop => {
			bgDropArea.isHovered = false;
			if (typeof dragHandler !== 'undefined' && dragHandler)
				dragHandler.tooltip_active = false;

			let uris = "";
			if (typeof dragHandler !== 'undefined' && dragHandler && dragHandler.drag_uris && dragHandler.drag_uris.length > 0) {
				uris = dragHandler.drag_uris.join("\n");
			} else if (drop.source && drop.source.dragUris) {
				uris = drop.source.dragUris.join("\n");
			} else if (drop.hasUrls) {
				uris = drop.urls.join("\n");
			} else if (drop.hasText) {
				uris = drop.text;
			}

			if (uris.length > 0 && typeof fileManager !== 'undefined' && fileManager) {
				const action = (typeof dragHandler !== 'undefined' && dragHandler) ? dragHandler.drag_action : "copy";
				if (fileManager.process_uris_action(folderView.directory.path, uris, action)) {
					folderView.directory.reload();
				}
				drop.accept();
			}
		}
	}

	DragTooltip {
		property var dragHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null

		active: dragHandler ? dragHandler.tooltip_active : false
		action: dragHandler ? dragHandler.drag_action : "copy"
		cursorX: dragHandler ? dragHandler.drag_cursor_x + 16 : 0
		cursorY: dragHandler ? dragHandler.drag_cursor_y + 16 : 0
	}

	// ── Input Shortcuts ───
	Keys.onPressed: event => {
		const mgr = folderView.rootWindow ? folderView.rootWindow.selectionManager : null;
		if (!mgr)
			return;

		if (event.key === Qt.Key_Space && !mgr.selection_active) {
			mgr.enter_selection_mode();
			event.accepted = true;
		} else if (event.key === Qt.Key_Escape && mgr.selection_active) {
			mgr.exit_selection_mode();
			event.accepted = true;
		} else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) {
			folderView.selectAll();
			event.accepted = true;
		}
	}

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
		contentHeight: Math.max(height, flowLayout.height)

		MouseArea {
			id: flickableBgMouseArea
			width: flickable.contentWidth
			height: flickable.contentHeight
			z: 0
			acceptedButtons: Qt.LeftButton
			onClicked: mouse => {
				folderView.forceActiveFocus();
				if (folderView.rootWindow && folderView.rootWindow.selectionManager)
					folderView.rootWindow.selectionManager.clear();
			}
		}

		Flow {
			id: flowLayout
			z: 1
			width: parent.width
			spacing: Kirigami.Units.mediumSpacing

			Repeater {
				id: itemRepeater
				model: folderView.directory

				delegate: FileSlot {
					property SelectionManager selectionManager: folderView.rootWindow ? folderView.rootWindow.selectionManager : null
					actionManager: folderView.rootWindow ? folderView.rootWindow.actionManager : null
					fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null

					dragDropHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null
					width: labelBesideIcon ? Kirigami.Units.gridUnit * 10 : gridSize + Kirigami.Units.gridUnit * 3
					height: labelBesideIcon ? Kirigami.Units.gridUnit * 2 : gridSize + Kirigami.Units.gridUnit * 3

					gridSize: folderView.config.grid_size
					selectionActive: selectionManager ? selectionManager.selection_active : false
					isSelected: selectionManager ? (function () {
							try {
								return !!JSON.parse(selectionManager.selected_paths)[path];
							} catch (e) {
								return false;
							}
						})() : false

					onNavigate: (targetPath, sourceSlot) => {
						if (!sourceSlot || sourceSlot.is_dir) {
							folderView.directory.open_path(targetPath);
							return;
						}

						sourceSlot.grabToImage(result => {
							externalOpenAnimation.parent = sourceSlot;
							externalOpenAnimation.x = 0;
							externalOpenAnimation.y = 0;
							externalOpenAnimation.width = sourceSlot.width;
							externalOpenAnimation.height = sourceSlot.height;
							externalOpenImage.source = result.url;
							externalOpenAnimation.visible = true;
							externalOpenAnimationEffect.restart();
						});
						folderView.directory.open_path(targetPath);
					}

					onOpenWindow: (targetPath, sourceSlot) => {
						sourceSlot.grabToImage(result => {
							externalOpenAnimation.parent = sourceSlot;
							externalOpenAnimation.x = 0;
							externalOpenAnimation.y = 0;
							externalOpenAnimation.width = sourceSlot.width;
							externalOpenAnimation.height = sourceSlot.height;
							externalOpenImage.source = result.url;
							externalOpenAnimation.visible = true;
							externalOpenAnimationEffect.restart();
						});
						folderView.directory.open_in_new_window(targetPath);
					}

					onSelectionToggled: (p, idx) => {
						folderView.forceActiveFocus();
						if (selectionManager) {
							selectionManager.toggle_selection(p, idx);
						}
					}

					onShiftSelected: idx => {
						folderView.forceActiveFocus();
						if (selectionManager) {
							if (!selectionManager.selection_active)
								selectionManager.enter_selection_mode();
							const from = selectionManager.last_selected_index >= 0 ? selectionManager.last_selected_index : idx;
							selectionManager.range_select(from, idx);
						}
					}

					onPressHeld: (p, idx) => {
						folderView.forceActiveFocus();
						if (selectionManager) {
							selectionManager.toggle_selection(p, idx);
						}
					}

					onContextMenuRequested: (slotPath, slotIndex) => {
						folderView.forceActiveFocus();
						if (selectionManager) {
							let isAlreadySelected = false;
							try {
								isAlreadySelected = !!JSON.parse(selectionManager.selected_paths)[slotPath];
							} catch (e) {}
							if (!isAlreadySelected) {
								selectionManager.clear();
								selectionManager.toggle_selection(slotPath, slotIndex);
							}
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

		height: (folderView.rootWindow && folderView.rootWindow.selectionManager && folderView.rootWindow.selectionManager.selection_active) ? 48 : 0
		visible: folderView.rootWindow && folderView.rootWindow.selectionManager && folderView.rootWindow.selectionManager.selection_active
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
					const n = (folderView.rootWindow && folderView.rootWindow.selectionManager) ? folderView.rootWindow.selectionManager.selected_count : 0;
					return n === 1 ? qsTr("1 item selected") : qsTr("%1 items selected").arg(n);
				}
				font.weight: Font.Medium
				Layout.fillWidth: true
			}

			ToolButton {
				text: qsTr("Select All")
				icon.name: "edit-select-all"
				ToolTip.text: qsTr("Select All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.selectAll()
			}

			ToolButton {
				text: qsTr("Deselect All")
				icon.name: "edit-select-none"
				ToolTip.text: qsTr("Deselect All")
				ToolTip.visible: hovered
				flat: true
				onClicked: if (folderView.rootWindow && folderView.rootWindow.selectionManager)
					folderView.rootWindow.selectionManager.deselect_all()
			}
		}
	}

	ExecuteDialog {
		id: execDialog
		directory: folderView.directory
		fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null
	}
}
