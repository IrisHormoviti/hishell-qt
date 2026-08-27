import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Hishell"
import "toolkit"

Kirigami.ApplicationWindow {
	id: root
	width: 800
	height: 600
	visible: true

	WindowOverlay {}

	Directory {
		id: directory
	}

	FileManager {
		id: fileManager
	}

	// Persistent Drag & Drop Handler
	Item {
		id: dragHandler
		visible: true
		opacity: 0
		width: 1
		height: 1

		Drag.dragType: Drag.Automatic
		Drag.supportedActions: Qt.CopyAction | Qt.MoveAction | Qt.LinkAction
		Drag.proposedAction: Qt.CopyAction

		property real dragIconWidth: 0
		property real dragIconHeight: 0
		Drag.hotSpot.x: dragIconWidth / 2
		Drag.hotSpot.y: dragIconHeight / 2

		property var activeDraggedPaths: []
		property bool isSystemDragging: Drag.active

		property string mainPath: ""
		property var dragUris: []
		property var dragSourcePaths: []
		property int itemCount: 1
		property string fileTitle: ""
		property string fileIcon: ""

		property bool tooltipActive: false
		property string dragAction: "copy"
		property real dragCursorX: 0
		property real dragCursorY: 0
		property var shakePositions: []

		property var draggedSlot: null

		function trackMouseShake(x, y) {
			dragHandler.dragCursorX = x;
			dragHandler.dragCursorY = y;

			var now = Date.now();
			var history = dragHandler.shakePositions.slice();
			history.push({ x: x, y: y, time: now });

			history = history.filter(function(p) { return now - p.time <= 450; });
			dragHandler.shakePositions = history;

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
				dragHandler.shakePositions = [];
			}
		}

		function cycleDragAction() {
			if (dragHandler.dragAction === "copy") {
				dragHandler.dragAction = "move";
			} else if (dragHandler.dragAction === "move") {
				dragHandler.dragAction = "link";
			} else {
				dragHandler.dragAction = "copy";
			}
		}

		Drag.onActiveChanged: {
			if (!Drag.active) {
				dragHandler.activeDraggedPaths = [];
				dragHandler.tooltipActive = false;
				dragHandler.shakePositions = [];
			}
		}
	}

	// Drag Tooltip
	DragTooltip {
		active: dragHandler.tooltipActive && dragHandler.Drag.active
		action: dragHandler.dragAction
		cursorX: dragHandler.dragCursorX + 16
		cursorY: dragHandler.dragCursorY + 16
	}

	// Shared selection state, written by FolderView, read by MenuBar
	QtObject {
		id: selectionState
		property bool selectionActive: false
		property var  selectedPaths: ({})
		property int  selectedCount: 0
	}

	Component.onCompleted: {
		var args = Qt.application.arguments;
		var startPath = typeof initialPath !== 'undefined' && initialPath !== null && initialPath !== '' ? initialPath : ".";
		if (args && args.length > 1) {
			var a = args[1];
			if (typeof a === 'string') {
				if (a.indexOf('file://') === 0) {
					try {
						a = decodeURIComponent(a.substring(7));
					} catch (e) {}
				}
				startPath = a;
			}
		}
		if (!startPath || startPath === "") {
			startPath = ".";
		}
		directory.config.load(startPath);
		directory.path = startPath;
	}

	pageStack.initialPage: Kirigami.Page {
		padding: 0
		topPadding: 0
		leftPadding: 0
		rightPadding: 0
		bottomPadding: 0

		// Remove Kirigami's own header
		globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

		ColumnLayout {
			anchors.fill: parent
			spacing: 0

			// Header bar
			Item {
				Layout.fillWidth: true
				Layout.preferredHeight: 44
				Kirigami.Theme.colorSet: Kirigami.Theme.Header
				Kirigami.Theme.inherit: false

				Rectangle {
					anchors.fill: parent
					z: -1
					color: Kirigami.Theme.backgroundColor
				}

				RowLayout {
					anchors.fill: parent

					Layout.fillWidth: true
					Layout.preferredHeight: 44
					Layout.margins: 0
					spacing: Kirigami.Units.smallSpacing

					// Make it draggable
					DragHandler {
						target: null
						onActiveChanged: if (active)
							root.startSystemMove()
					}

					// Left padding
					Item {
						Layout.preferredWidth: Kirigami.Units.largeSpacing
					}

					LayoutEngine {
						directory: directory
						fileManager: fileManager
						selectionState: selectionState
						layoutString: String(directory.config.header_layout)
						Layout.fillWidth: true
					}

					// Right padding
					Item {
						Layout.preferredWidth: Kirigami.Units.largeSpacing
					}
				}
			}

			// Separator line
			Kirigami.Separator {
				Layout.fillWidth: true
			}

			// Top Layout area
			LayoutEngine {
				directory: directory
				fileManager: fileManager
				selectionState: selectionState
				layoutString: String(directory.config.top_layout)
				Layout.fillWidth: true
			}

			// Main content area
			RowLayout {
				Layout.fillWidth: true
				Layout.fillHeight: true
				spacing: 0

				LayoutEngine {
					directory: directory
					fileManager: fileManager
					selectionState: selectionState
					layoutString: String(directory.config.middle_layout)
					Layout.fillHeight: true
					Layout.fillWidth: true
				}
			}

			// Bottom Layout area
			LayoutEngine {
				directory: directory
				fileManager: fileManager
				selectionState: selectionState
				layoutString: String(directory.config.bottom_layout)
				Layout.fillWidth: true
			}
		}
	}
}
