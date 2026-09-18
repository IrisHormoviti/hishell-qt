pragma
ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Hishell"

Item {
	id: fileSlot

	required property string path
	required property string icon
	required property string title
	required property int index
	required property bool is_dir
	required property DragDropHandler dragDropHandler

	property int gridSize: 64
	property bool labelBesideIcon: gridSize < 32
	property bool fixedWidth: true
	property bool showIcon: icon !== ""

	// Selection state passed from FolderView
	property bool selectionActive: false
	property bool isSelected: false

	property int currentDragCount: 1

	property bool isDraggingThisSlot: localDragTarget.Drag.active
	onIsDraggingThisSlotChanged: {
		if (!isDraggingThisSlot && mouseArea.dragStarted) {
			mouseArea.dragStarted = false;
			mouseArea.dragInitiated = false;
			if (typeof fileSlot.dragDropHandler !== 'undefined' && fileSlot.dragDropHandler) {
				fileSlot.dragDropHandler.active_dragged_paths = [];
				fileSlot.dragDropHandler.tooltip_active = false;
				fileSlot.dragDropHandler.end_drag();
			}
		}
	}

	// Emitted on navigation
	signal navigate(string targetPath)

	// Emitted when toggling this item's selection
	signal selectionToggled(string path, int idx)

	// Emitted for range selection
	signal shiftSelected(int idx)

	// Emitted on press and hold
	signal pressHeld(string path, int idx)

	// Emitted on right click context menu request
	signal contextMenuRequested(string path, bool isDir, int mouseX, int mouseY, var mouseAreaItem)

	// --- Slot ---
	implicitWidth: contentLayout.implicitWidth + (fileSlot.labelBesideIcon && fileSlot.showIcon ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2)
	implicitHeight: contentLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
	opacity: (fileSlot.dragDropHandler && fileSlot.dragDropHandler.active_dragged_paths && fileSlot.dragDropHandler.active_dragged_paths.indexOf(fileSlot.path) !== -1) ? 0.2 : 1.0

	Behavior on opacity {
		NumberAnimation {
			duration: 100
		}
	}

	// ── Offscreen Visual Container for Multi-Drag Stack ──
	Item {
		id: stackPreviewContainer
		width: fileSlot.width + 12
		height: fileSlot.height + 12
		visible: false

		Repeater {
			model: Math.min(3, fileSlot.currentDragCount)
			delegate: Rectangle {
				required property int index
				x: (2 - index) * 5
				y: (2 - index) * 5
				width: fileSlot.width
				height: fileSlot.height
				radius: Kirigami.Units.cornerRadius
				color: Kirigami.Theme.backgroundColor
				border.color: Kirigami.Theme.highlightColor
				border.width: 1
				opacity: 1.0 - (index * 0.15)

				Kirigami.Icon {
					anchors.centerIn: parent
					width: fileSlot.gridSize
					height: fileSlot.gridSize
					source: fileSlot.icon
				}
			}
		}
	}

	// ── Layout ──

	GridLayout {
		id: contentLayout
		anchors.verticalCenter: parent.verticalCenter
		x: (fileSlot.labelBesideIcon && fileSlot.showIcon) ? Kirigami.Units.largeSpacing : (parent.width - width) / 2
		columns: (fileSlot.labelBesideIcon && fileSlot.showIcon) ? 2 : 1

		Item {
			visible: fileSlot.showIcon
			Layout.alignment: (fileSlot.labelBesideIcon && fileSlot.showIcon) ? Qt.AlignVCenter : Qt.AlignHCenter
			Layout.preferredWidth: fileSlot.gridSize
			Layout.preferredHeight: fileSlot.gridSize

			Loader {
				anchors.fill: parent
				active: fileSlot.showIcon
				sourceComponent: (fileSlot.icon.startsWith("file://") || fileSlot.icon.startsWith("/")) ? thumbnailComponent : iconComponent
			}

			Component {
				id: thumbnailComponent
				Image {
					source: fileSlot.icon
					asynchronous: true
					cache: false
					fillMode: Image.PreserveAspectFit
					smooth: true
					anchors.fill: parent
					clip: true
					anchors.centerIn: parent
				}
			}

			Component {
				id: iconComponent
				Kirigami.Icon {
					source: fileSlot.icon
					Layout.preferredWidth: fileSlot.gridSize
					Layout.preferredHeight: fileSlot.gridSize
					Layout.fillWidth: false
					Layout.fillHeight: false
				}
			}
		}

		Label {
			id: labelItem
			Layout.alignment: fileSlot.labelBesideIcon ? Qt.AlignVCenter : Qt.AlignHCenter
			text: {
				let t = fileSlot.title;
				let idx = t.lastIndexOf('.');
				if (idx > 0 && !(t.startsWith('.') && t.indexOf('.', 1) === -1)) {
					let name = t.substring(0, idx);
					let ext = t.substring(idx);
					return name + '<font color="' + Kirigami.Theme.disabledTextColor + '">' + ext + '</font>';
				}
				return t;
			}
			textFormat: Text.StyledText
			color: Kirigami.Theme.textColor
			wrapMode: Text.Wrap
			maximumLineCount: 2
			elide: fileSlot.labelBesideIcon ? Text.ElideMiddle : Text.ElideMiddle
			Layout.maximumWidth: fileSlot.labelBesideIcon ? (fileSlot.fixedWidth ? fileSlot.width - fileSlot.gridSize - Kirigami.Units.gridUnit * 2 : 250) : fileSlot.gridSize + Kirigami.Units.gridUnit * 2
			horizontalAlignment: fileSlot.labelBesideIcon ? Text.AlignLeft : Text.AlignHCenter
		}
	}

	// ── Selection ──

	// Accent color bg
	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.highlightColor
		opacity: fileSlot.isSelected ? 0.25 : 0.0
		Behavior on opacity {
			NumberAnimation {
				duration: 120
			}
		}
	}

	// Border
	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: Kirigami.Units.cornerRadius
		color: "transparent"
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
		opacity: fileSlot.isSelected ? 1.0 : 0.0
		Behavior on opacity {
			NumberAnimation {
				duration: 120
			}
		}
	}

	// Checkmark
	Rectangle {
		anchors.top: parent.top
		anchors.right: parent.right
		anchors.margins: 4
		width: Kirigami.Units.iconSizes.small
		height: Kirigami.Units.iconSizes.small
		radius: width / 2
		color: fileSlot.isSelected ? Kirigami.Theme.highlightColor : "transparent"
		visible: fileSlot.selectionActive
		Behavior on color {
			ColorAnimation {
				duration: 120
			}
		}

		Kirigami.Icon {
			anchors.fill: parent
			anchors.margins: 2
			source: "emblem-ok-symbolic"
			opacity: fileSlot.isSelected ? 1.0 : 0.4
			Behavior on opacity {
				NumberAnimation {
					duration: 120
				}
			}
		}
	}

	// ── Drop Target ───

	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.focusColor
		opacity: slotDropArea.isHovered ? 0.35 : 0.0
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
		Behavior on opacity {
			NumberAnimation {
				duration: 120
			}
		}
	}

	DropArea {
		id: slotDropArea
		anchors.fill: parent
		enabled: fileSlot.is_dir
		keys: ["text/uri-list", "text/plain"]

		property bool isHovered: false
		property DragDropHandler dragDropHandler: fileSlot.dragDropHandler ? fileSlot.dragDropHandler : null

		function checkValid(drag) {
			let sourcePaths = [];
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_source_paths && dragDropHandler.drag_source_paths.length > 0) {
				sourcePaths = dragDropHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			let fView = null;
			let p = fileSlot.parent;
			while (p) {
				if (typeof p.isDropValid === 'function') {
					fView = p;
					break;
				}
				p = p.parent;
			}

			if (fView && !fView.isDropValid(fileSlot.path, sourcePaths)) {
				slotDropArea.isHovered = false;
				if (typeof dragDropHandler !== 'undefined')
					dragDropHandler.tooltip_active = false;
				drag.accepted = false;
				hoverNavTimer.stop();
				return false;
			}

			slotDropArea.isHovered = true;
			if (typeof dragDropHandler !== 'undefined') {
				dragDropHandler.tooltip_active = true;
			}
			drag.accept();
			return true;
		}

		onEntered: drag => {
			if (checkValid(drag)) {
				hoverNavTimer.restart();
			}
		}

		onPositionChanged: drag => {
			checkValid(drag);
		}

		onExited: {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
			if (typeof dragDropHandler !== 'undefined')
				dragDropHandler.tooltip_active = false;
		}

		onDropped: drop => {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
			if (typeof dragDropHandler !== 'undefined')
				dragDropHandler.tooltip_active = false;

			let uris = "";
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_uris && dragDropHandler.drag_uris.length > 0) {
				uris = dragDropHandler.drag_uris.join("\n");
			} else if (drop.source && drop.source.dragUris) {
				uris = drop.source.dragUris.join("\n");
			} else if (drop.hasUrls) {
				uris = drop.urls.join("\n");
			} else if (drop.hasText) {
				uris = drop.text;
			}

			if (uris.length > 0 && typeof fileManager !== 'undefined' && fileManager) {
				const action = (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_action) ? dragDropHandler.drag_action : "copy";
				if (fileManager.process_uris_action(fileSlot.path, uris, action)) {
					let p = fileSlot.parent;
					while (p) {
						if (p.directory) {
							p.directory.reload();
							break;
						}
						p = p.parent;
					}
				}
				drop.accept();
			}
		}
	}

	Timer {
		id: hoverNavTimer
		interval: 800
		repeat: false
		onTriggered: {
			if (slotDropArea.isHovered && fileSlot.is_dir) {
				const targetPath = fileSlot.path;
				if (typeof fileSlot.dragDropHandler !== 'undefined')
					fileSlot.dragDropHandler.tooltip_active = false;
				Qt.callLater(function () {
					fileSlot.navigate(targetPath);
				});
			}
		}
	}

	// ── Mouse & Drag Handling ───

	Item {
		id: localDragTarget
		width: fileSlot.width > 0 ? fileSlot.width : fileSlot.implicitWidth
		height: fileSlot.height > 0 ? fileSlot.height : fileSlot.implicitHeight
		Drag.keys: ["text/uri-list", "text/plain"]
		Drag.mimeData: {
			"text/uri-list": dragDropHandler ? dragDropHandler.drag_uris.join("\n") : ""
		}
		Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
		Drag.proposedAction: Qt.MoveAction
		Drag.dragType: Drag.Automatic
		Drag.active: false
		Drag.hotSpot: Qt.point(Math.round(width / 2), Math.round(height / 2))
	}

	MouseArea {
		id: mouseArea
		anchors.fill: parent
		acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
		pressAndHoldInterval: 600

		drag.target: localDragTarget
		drag.axis: Drag.XAndYAxis

		property DragDropHandler dragDropHandler: fileSlot.dragDropHandler ? fileSlot.dragDropHandler : null
		property bool dragStarted: false
		property bool isPressAndHoldActive: false

		// Track where the mouse was first pressed down
		property int startX: 0
		property int startY: 0
		property bool dragInitiated: false

		Component.onDestruction: {
			if (typeof dragDropHandler !== 'undefined' && mouseArea.dragStarted) {
				localDragTarget.Drag.active = false;
				dragDropHandler.active_dragged_paths = [];
				dragDropHandler.tooltip_active = false;
				dragDropHandler.end_drag();
			}
		}

		// Reusable function to assemble metadata only when a true drag is confirmed
		function initiateDragPayload(mouse) {
			if (dragInitiated)
				return;
			dragInitiated = true;

			const uris = [];
			const rawPaths = [];
			const mainPath = fileSlot.path;
			const mainUri = mainPath.startsWith("file://") ? mainPath : ("file://" + mainPath);

			let mgr = null;
			let p = fileSlot.parent;
			while (p) {
				if (p.selectionManager) {
					mgr = p.selectionManager;
					break;
				}
				if (p.rootWindow && p.rootWindow.selectionManager) {
					mgr = p.rootWindow.selectionManager;
					break;
				}
				p = p.parent;
			}

			let selectedMap = {};
			try {
				selectedMap = JSON.parse(mgr ? mgr.selected_paths : "{}");
			} catch (e) {
			}

			if (mgr && mgr.selected_count > 1 && selectedMap[mainPath]) {
				const keys = Object.keys(selectedMap);
				for (let i = 0; i < keys.length; i++) {
					const pathKey = keys[i];
					if (selectedMap[pathKey]) {
						rawPaths.push(pathKey);
						uris.push(pathKey.startsWith("file://") ? pathKey : ("file://" + pathKey));
					}
				}
			} else {
				rawPaths.push(mainPath);
				uris.push(mainUri);
			}

			fileSlot.currentDragCount = rawPaths.length;

			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				dragDropHandler.active_dragged_paths = rawPaths;
				dragDropHandler.set_drag_data(mainPath, uris, rawPaths, uris.length, fileSlot.title, fileSlot.icon);
			}

			const targetToGrab = (rawPaths.length > 1) ? stackPreviewContainer : fileSlot;

			targetToGrab.grabToImage(function (result) {
				if (mouseArea.isPressAndHoldActive) {
					if (typeof dragDropHandler !== 'undefined' && dragDropHandler)
						dragDropHandler.active_dragged_paths = [];
					return;
				}

				localDragTarget.Drag.imageSource = result.url;
				localDragTarget.Drag.hotSpot = Qt.point(Math.round(targetToGrab.width / 2), Math.round(targetToGrab.height / 2));

				if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
					const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
					dragDropHandler.track_mouse_shake(pt.x, pt.y);
					dragDropHandler.begin_drag(result.url.toString(), targetToGrab.width, targetToGrab.height);
				}

				mouseArea.dragStarted = true;
				localDragTarget.Drag.active = true;
			});
		}

		onPositionChanged: mouse => {
			if (typeof dragDropHandler !== 'undefined') {
				if (!mouseArea.dragStarted && !mouseArea.isPressAndHoldActive && mouseArea.drag.active) {
					const deltaX = mouse.x - mouseArea.startX;
					const deltaY = mouse.y - mouseArea.startY;
					const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);

					if (distance > 10) {
						mouseArea.initiateDragPayload(mouse);
					}
				}

				if (mouseArea.dragStarted) {
					const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
					dragDropHandler.track_mouse_shake(pt.x, pt.y);
				}
			}
		}

		onPressed: mouse => {
			if (mouse.button === Qt.LeftButton && typeof dragDropHandler !== 'undefined') {
				mouseArea.isPressAndHoldActive = false;
				mouseArea.dragInitiated = false;

				mouseArea.startX = mouse.x;
				mouseArea.startY = mouse.y;
			}
		}

		onReleased: mouse => {
			mouseArea.isPressAndHoldActive = false;
			mouseArea.dragInitiated = false;

			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				dragDropHandler.active_dragged_paths = [];
				dragDropHandler.tooltip_active = false;
				dragDropHandler.end_drag();
			}
			localDragTarget.Drag.active = false;
			localDragTarget.Drag.imageSource = "";
			mouseArea.dragStarted = false;
		}

		onPressAndHold: {
			mouseArea.isPressAndHoldActive = true;
			fileSlot.pressHeld(fileSlot.path, fileSlot.index);
		}

		onClicked: mouse => {
			if (mouse.button === Qt.RightButton) {
				fileSlot.contextMenuRequested(fileSlot.path, fileSlot.is_dir, mouse.x, mouse.y, mouseArea);
				return;
			}
			if (mouse.button === Qt.MiddleButton)
				return;

			if (fileSlot.selectionActive) {
				if (mouse.modifiers & Qt.ShiftModifier) {
					fileSlot.shiftSelected(fileSlot.index);
				} else {
					fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
				}
			} else if (mouse.modifiers & Qt.ControlModifier) {
				fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
			} else {
				fileSlot.navigate(fileSlot.path);
			}
		}
	}
}