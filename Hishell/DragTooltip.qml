pragma
ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme

Item {
	id: tooltipRoot
	z: 9999
	visible: active && opacity > 0
	opacity: active ? 1.0 : 0.0

	property string action: "copy" // "copy", "move", "link", "reposition"
	property bool reposition: false
	property bool active: false
	property real cursorX: 0
	property real cursorY: 0

	x: cursorX + 16
	y: cursorY + 16

	Behavior on opacity {
		NumberAnimation {
			duration: 120; easing.type: Easing.OutCubic
		}
	}

	Rectangle {
		id: bg
		width: contentRow.implicitWidth + Units.mediumSpacing
		height: contentRow.implicitHeight + Units.mediumSpacing

		color: Qt.rgba(Theme.backgroundColor.r, Theme.backgroundColor.g, Theme.backgroundColor.b, 0.92)
		radius: Units.cornerRadius
		border.width: 1
		border.color: Qt.rgba(1, 1, 1, 0.15)

		RowLayout {
			id: contentRow
			anchors.centerIn: parent
			spacing: 6

			Icon {
				source: {
					if (tooltipRoot.reposition)
						return "transform-move";
					switch (tooltipRoot.action) {
						case "move":
							return "edit-cut";
						case "link":
							return "link-symbolic";
						default:
							return "edit-copy";
					}
				}
				Layout.preferredWidth: Units.iconSizes.small
				Layout.preferredHeight: Units.iconSizes.small
			}

			Label {
				text: {
					if (tooltipRoot.reposition)
						return qsTr("Reposition");
					switch (tooltipRoot.action) {
						case "move":
							return qsTr("Move");
						case "link":
							return qsTr("Link");
						default:
							return qsTr("Copy");
					}
				}
				font.weight: Font.DemiBold
				font.pixelSize: Units.gridUnit * 0.75
				color: Theme.textColor
			}
		}
	}
}
