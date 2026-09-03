pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Hishell"

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
	property bool showIcon: icon != ""

	// Selection state passed from FolderView
	property bool selectionActive: false
	property bool isSelected: false

	// Emitted on navigation
	signal navigate(string targetPath)

	// Emitted when toggling this item's selection
	signal selectionToggled(string path, int idx)

	// Emitted for range selection
	signal shiftSelected(int idx)

	// Emitted on press and hold
	signal pressHeld(string path, int idx)

	// --- Slot ---
	implicitWidth: contentLayout.implicitWidth + (fileSlot.labelBesideIcon && fileSlot.showIcon ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2)
	implicitHeight: contentLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
	opacity: !(fileSlot.dragDropHandler && fileSlot.dragDropHandler.Drag.active && fileSlot.dragDropHandler.active_dragged_paths.indexOf(fileSlot.path) !== -1)

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
			var sourcePaths = [];
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_source_paths && dragDropHandler.drag_source_paths.length > 0) {
				sourcePaths = dragDropHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			var fView = null;
			var p = fileSlot.parent;
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
				var pt = slotDropArea.mapToItem(null, drag.x, drag.y);
				dragDropHandler.track_mouse_shake(pt.x, pt.y);
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

			var uris = "";
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
				var action = (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_action) ? dragDropHandler.drag_action : "copy";
				if (fileManager.process_uris_action(fileSlot.path, uris, action)) {
					var p = fileSlot.parent;
					while (p) {
						if (p.directory) {
							p.directory.refresh();
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
				var targetPath = fileSlot.path;
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
		visible: false
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
				dragDropHandler.Drag.active = false;
				dragDropHandler.tooltip_active = false;
			}
		}

		// Reusable function to assemble metadata only when a true drag is confirmed
		function initiateDragPayload() {
			if (dragInitiated)
				return;
			dragInitiated = true;

			var uris = [];
			var rawPaths = [];
			var mainPath = fileSlot.path;
			var mainUri = mainPath.startsWith("file://") ? mainPath : ("file://" + mainPath);

			var fView = null;
			var p = fileSlot.parent;
			while (p) {
				if (typeof p.selectedCount !== 'undefined' && typeof p.selectedPaths !== 'undefined') {
					fView = p;
					break;
				}
				p = p.parent;
			}

			if (fView && fView.selectedCount > 1 && fView.selectedPaths[mainPath]) {
				var keys = Object.keys(fView.selectedPaths);
				for (var i = 0; i < keys.length; i++) {
					var pathKey = keys[i];
					rawPaths.push(pathKey);
					uris.push(pathKey.startsWith("file://") ? pathKey : ("file://" + pathKey));
				}
			} else {
				rawPaths.push(mainPath);
				uris.push(mainUri);
			}

			if (typeof dragDropHandler !== 'undefined') {
				dragDropHandler.set_drag_data(mainPath, uris, rawPaths, uris.length, fileSlot.title, fileSlot.icon);
			}
			fileSlot.grabToImage(function (result) {
				if (mouseArea.isPressAndHoldActive) {
					if (typeof dragDropHandler !== 'undefined')
						dragDropHandler.active_dragged_paths = [];
					return;
				}

				dragDropHandler.Drag.imageSource = result.url;
				mouseArea.dragStarted = true;
				dragDropHandler.Drag.active = true;
			});
		}

		onPositionChanged: mouse => {
			if (typeof dragDropHandler !== 'undefined') {
				if (!mouseArea.dragStarted && !mouseArea.isPressAndHoldActive && mouseArea.drag.active) {
					var deltaX = mouse.x - mouseArea.startX;
					var deltaY = mouse.y - mouseArea.startY;
					var distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);

					if (distance > 10) {
						mouseArea.initiateDragPayload();
					}
				}

				if (mouseArea.dragStarted) {
					var pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
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

			if (typeof dragDropHandler !== 'undefined') {
				dragDropHandler.Drag.active = false;
				dragDropHandler.Drag.imageSource = "";
				dragDropHandler.tooltip_active = false;
			}
			mouseArea.dragStarted = false;
		}

		onPressAndHold: {
			mouseArea.isPressAndHoldActive = true;
			fileSlot.pressHeld(fileSlot.path, fileSlot.index);
		}

		onClicked: mouse => {
			if (mouse.button === Qt.RightButton)
				return;
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
