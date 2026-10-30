import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme

// Segmented control for a build without the ClamOS QQC2 style (a desktop with
// the KDE palette). Draws from the theme tokens: the chosen segment takes the
// accent, the others the button surface.

Item {
	id: generic

	property var options: []
	property var currentValue: undefined
	signal activated(var value)

	implicitHeight: Math.max(Units.gridUnit * 2.4, 40)
	implicitWidth: Units.gridUnit * 20

	RowLayout {
		anchors.fill: parent
		spacing: Units.smallSpacing

		Repeater {
			model: generic.options

			delegate: Item {
				id: segment
				required property var modelData

				readonly property bool selected: generic.currentValue === modelData.value
				readonly property string label: modelData.text !== undefined ? String(modelData.text) : ""
				readonly property string iconName: modelData.icon !== undefined ? String(modelData.icon) : ""

				Layout.fillWidth: true
				Layout.fillHeight: true

				Rectangle {
					anchors.fill: parent
					radius: Units.cornerRadius
					color: segment.selected ? Theme.highlightColor : Theme.buttonBackgroundColor
					border.width: segment.selected ? 0 : 1
					border.color: Theme.disabledTextColor
					opacity: segment.selected ? 1.0 : 0.85
				}
				Rectangle {
					anchors.fill: parent
					anchors.margins: 1
					radius: Math.max(0, Units.cornerRadius - 1)
					color: "transparent"
					border.width: 1
					border.color: Qt.rgba(1, 1, 1, segment.selected ? 0.22 : 0.35)
				}

				RowLayout {
					anchors.centerIn: parent
					spacing: Units.smallSpacing

					Icon {
						visible: segment.iconName !== ""
						source: segment.iconName
						implicitWidth: Units.iconSizes.small
						implicitHeight: Units.iconSizes.small
					}

					Label {
						text: segment.label
						color: segment.selected ? Theme.highlightedTextColor : Theme.textColor
						font.pixelSize: Theme.defaultFont.pixelSize
						font.weight: Font.Medium
						elide: Text.ElideRight
					}
				}

				MouseArea {
					anchors.fill: parent
					onClicked: generic.activated(segment.modelData.value)
				}
			}
		}
	}
}
