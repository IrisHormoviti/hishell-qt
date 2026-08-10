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

	property int  gridSize: 64
	property bool labelBesideIcon: gridSize < 32

	// Selection state passed from FolderView
	property bool selectionActive: false
	property bool isSelected: false

	// Emitted on normal navigation
	signal navigate(string targetPath)

	// Emitted when the user wants to toggle this item's selection
	signal selectionToggled(string path, int idx)

	// Emitted for shift-click range selection
	signal shiftSelected(int idx)

	// Emitted on press-and-hold to enter selection mode
	signal pressHeld(string path, int idx)

	// ── Layout ────────────────────────────────────────────────────────────

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

	// ── Selection overlay ─────────────────────────────────────────────────

	// Tinted background when selected
	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.highlightColor
		opacity: fileSlot.isSelected ? 0.25 : 0.0
		Behavior on opacity { NumberAnimation { duration: 120 } }
	}

	// Selection border
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

	// Checkmark badge in top-right corner
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

	// ── Mouse handling ─────────────────────────────────────────────────────

	MouseArea {
		id: mouseArea
		anchors.fill: parent
		acceptedButtons: Qt.LeftButton | Qt.RightButton
		pressAndHoldInterval: 600

		onPressAndHold: {
			fileSlot.pressHeld(fileSlot.path, fileSlot.index);
		}

		onClicked: (mouse) => {
			if (mouse.button === Qt.RightButton) {
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
