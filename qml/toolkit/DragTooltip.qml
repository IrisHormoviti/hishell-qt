pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
	id: tooltipRoot
	z: 9999
	visible: active && opacity > 0
	opacity: active ? 1.0 : 0.0

	property string action: "copy" // "copy", "move", "link"
	property bool active: false
	property real cursorX: 0
	property real cursorY: 0

	x: cursorX + 16
	y: cursorY + 16

	Behavior on opacity {
		NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
	}

	Rectangle {
		id: bg
		width: contentRow.implicitWidth + 20
		height: contentRow.implicitHeight + 12
		radius: 14

		Kirigami.Theme.colorSet: Kirigami.Theme.Header
		color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, 0.92)
		border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
		border.width: 1

		RowLayout {
			id: contentRow
			anchors.centerIn: parent
			spacing: 6

			Kirigami.Icon {
				source: {
					switch (tooltipRoot.action) {
						case "move": return "edit-cut";
						case "link": return "link-symbolic";
						default:     return "edit-copy";
					}
				}
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Kirigami.Units.iconSizes.small
			}

			Label {
				text: {
					switch (tooltipRoot.action) {
						case "move": return qsTr("Move");
						case "link": return qsTr("Link");
						default:     return qsTr("Copy");
					}
				}
				font.weight: Font.DemiBold
				font.pixelSize: Kirigami.Units.gridUnit * 0.75
				color: Kirigami.Theme.textColor
			}
		}
	}
}
