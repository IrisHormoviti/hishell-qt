pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
	id: fileSlot

	required property string path
	required property string icon
	required property string title
	required property int    index
	required property bool   is_dir

	property int  gridSize: 64
	property bool labelBesideIcon: gridSize < 32

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

	GridLayout {
		id: contentLayout
		anchors.verticalCenter: parent.verticalCenter
		x: fileSlot.labelBesideIcon ? Kirigami.Units.largeSpacing : (parent.width - width) / 2
		columns: fileSlot.labelBesideIcon ? 2 : 1

		Item {
			Layout.alignment: fileSlot.labelBesideIcon ? Qt.AlignVCenter : Qt.AlignHCenter
			Layout.preferredWidth: fileSlot.gridSize
			Layout.preferredHeight: fileSlot.gridSize

			Loader {
				anchors.fill: parent
				sourceComponent: (fileSlot.icon.startsWith("file://") || fileSlot.icon.startsWith("/")) ? thumbnailComponent : iconComponent
			}

			Component {
				id: thumbnailComponent
				Image {
					source: fileSlot.icon
					asynchronous: true
					cache: true
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
			elide: fileSlot.labelBesideIcon ? Text.ElideNone : Text.ElideMiddle
			Layout.maximumWidth: fileSlot.labelBesideIcon
			? fileSlot.width - fileSlot.gridSize - Kirigami.Units.gridUnit * 2
			: fileSlot.gridSize + Kirigami.Units.gridUnit * 2
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
		Behavior on opacity { NumberAnimation { duration: 120 } }
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
		Behavior on opacity { NumberAnimation { duration: 120 } }
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
		Behavior on color { ColorAnimation { duration: 120 } }

		Kirigami.Icon {
			anchors.fill: parent
			anchors.margins: 2
			source: "emblem-ok-symbolic"
			opacity: fileSlot.isSelected ? 1.0 : 0.4
			Behavior on opacity { NumberAnimation { duration: 120 } }
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
		Behavior on opacity { NumberAnimation { duration: 120 } }
	}

	DropArea {
		id: slotDropArea
		anchors.fill: parent
		enabled: fileSlot.is_dir
		keys: ["text/uri-list", "text/plain"]

		property bool isHovered: false

		function checkValid(drag) {
			var sourcePaths = [];
			if (typeof rootDragHandle !== 'undefined' && rootDragHandle.dragSourcePaths && rootDragHandle.dragSourcePaths.length > 0) {
				sourcePaths = rootDragHandle.dragSourcePaths;
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
				if (typeof rootDragHandle !== 'undefined') rootDragHandle.tooltipActive = false;
				drag.accepted = false;
				hoverNavTimer.stop();
				return false;
			}

			slotDropArea.isHovered = true;
			if (typeof rootDragHandle !== 'undefined') {
				rootDragHandle.tooltipActive = true;
				var pt = slotDropArea.mapToItem(null, drag.x, drag.y);
				rootDragHandle.trackMouseShake(pt.x, pt.y);
			}
			drag.accept();
			return true;
		}

		onEntered: (drag) => {
			if (checkValid(drag)) {
				hoverNavTimer.restart();
			}
		}

		onPositionChanged: (drag) => {
			checkValid(drag);
		}

		onExited: {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
			if (typeof rootDragHandle !== 'undefined') rootDragHandle.tooltipActive = false;
		}

		onDropped: (drop) => {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
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
				if (typeof rootDragHandle !== 'undefined') rootDragHandle.tooltipActive = false;
				Qt.callLater(function() {
					fileSlot.navigate(targetPath);
				});
			}
		}
	}

	// ── Mouse & Drag Handling ───

	MouseArea {
		id: mouseArea
		anchors.fill: parent
		acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
		pressAndHoldInterval: 600

		drag.target: typeof rootDragHandle !== 'undefined' ? rootDragHandle : null
		drag.axis: Drag.XAndYAxis

		Connections {
			target: mouseArea.drag
			function onActiveChanged() {
				if (typeof rootDragHandle !== 'undefined') {
					if (mouseArea.drag.active) {
						rootDragHandle.Drag.active = true;
					} else {
						rootDragHandle.Drag.active = false;
						rootDragHandle.tooltipActive = false;
					}
				}
			}
		}

		onPositionChanged: (mouse) => {
			if (mouseArea.drag.active && typeof rootDragHandle !== 'undefined') {
				var pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
				rootDragHandle.trackMouseShake(pt.x, pt.y);
			}
		}

		onPressed: (mouse) => {
			if (mouse.button === Qt.LeftButton && typeof rootDragHandle !== 'undefined') {
				var uris = [];
				var rawPaths = [];
				var mainPath = fileSlot.path;
				var mainUri = mainPath.startsWith("file://") ? mainPath : ("file://" + mainPath);

				// Check selection state
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

				rootDragHandle.mainPath = mainPath;
				rootDragHandle.dragUris = uris;
				rootDragHandle.dragSourcePaths = rawPaths;
				rootDragHandle.itemCount = uris.length;
				rootDragHandle.fileTitle = fileSlot.title;
				rootDragHandle.fileIcon = fileSlot.icon;

				var urisStr = uris.join("\n");
				var mimeData = {
					"text/uri-list": urisStr,
					"text/plain": urisStr
				};

				// If single file, advertise text content for text files
				if (uris.length === 1 && !fileSlot.is_dir && typeof fileManager !== 'undefined' && fileManager) {
					var mimeType = fileManager.get_mime_type(mainPath);
					if (mimeType && mimeType !== "") {
						mimeData[mimeType] = mainUri;
						if (mimeType.startsWith("text/")) {
							var textContent = fileManager.get_text_content(mainPath);
							if (textContent && textContent !== "") {
								mimeData["text/plain"] = textContent;
							}
						}
					}
				}

				rootDragHandle.Drag.mimeData = mimeData;
				rootDragHandle.Drag.keys = Object.keys(mimeData);

				// Grab fileSlot visual item to URL for native Wayland system drag icon (Drag.imageSource)
				fileSlot.grabToImage(function(result) {
					rootDragHandle.Drag.imageSource = result.url;
				});
			}
		}

		onPressAndHold: {
			fileSlot.pressHeld(fileSlot.path, fileSlot.index);
		}

		onClicked: (mouse) => {
			if (mouse.button === Qt.RightButton) {
				return;
			}

			if (mouse.button === Qt.MiddleButton) {
				return;
			}

			if (fileSlot.selectionActive) {
				if (mouse.modifiers & Qt.ShiftModifier) {
					fileSlot.shiftSelected(fileSlot.index);
				} else {
					fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
				}
			} else if (mouse.modifiers & Qt.ControlModifier) {
				// Ctrl+click: start selection mode and select this item
				fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
			} else {
				fileSlot.navigate(fileSlot.path);
			}
		}
	}
}
