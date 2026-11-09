import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The old FileSlot rendering: selection plate, focus border, icon/thumbnail and
// label. Pointer, drag and drop handling stay with the view so the input path
// remains unchanged while the slot markup is shared.
Item {
	id: fileSlot

	property string name
	property string title
	property string icon
	property string thumb
	property bool isDirectory: false
	property bool selected: false
	property bool active: false
	property bool showLabels: true
	property bool labelsBeside: false
	property bool showIcon: true
	property int iconSize: 48
	property int gridSize: 0

	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: 6
		color: Kirigami.Theme.highlightColor
		opacity: fileSlot.selected ? 0.28 : 0
	}

	Rectangle {
		anchors.fill: parent
		anchors.margins: 1
		color: "transparent"
		border.width: 2
		border.color: Kirigami.Theme.highlightColor
		visible: fileSlot.active
	}

	GridLayout {
		anchors.centerIn: parent
		columns: fileSlot.labelsBeside && fileSlot.showLabels ? 2 : 1
		columnSpacing: 4
		rowSpacing: 4

		Item {
			Layout.preferredWidth: fileSlot.iconSize
			Layout.preferredHeight: fileSlot.iconSize
			Layout.alignment: Qt.AlignHCenter

			Image {
				anchors.fill: parent
				source: fileSlot.thumb
				fillMode: Image.PreserveAspectCrop
				visible: fileSlot.thumb.length > 0 && fileSlot.showIcon
			}

			Image {
				anchors.fill: parent
				source: fileSlot.icon.length > 0 && fileSlot.icon.startsWith("file:")
					? fileSlot.icon : ""
				fillMode: Image.PreserveAspectFit
				visible: fileSlot.thumb.length === 0 && fileSlot.showIcon
					&& fileSlot.icon.startsWith("file:")
			}

			Kirigami.Icon {
				anchors.fill: parent
				source: fileSlot.icon
				visible: fileSlot.thumb.length === 0 && fileSlot.showIcon
					&& !fileSlot.icon.startsWith("file:")
			}
		}

		Label {
			Layout.fillWidth: fileSlot.labelsBeside && fileSlot.showLabels
			Layout.preferredWidth: fileSlot.labelsBeside && fileSlot.showLabels
				? Math.max(0, fileSlot.width - fileSlot.iconSize - 12)
				: fileSlot.width - 8
			Layout.alignment: Qt.AlignVCenter
			visible: fileSlot.showLabels
			text: fileSlot.title.length > 0 ? fileSlot.title : fileSlot.name
			elide: Text.ElideMiddle
			horizontalAlignment: fileSlot.labelsBeside && fileSlot.showLabels
				? Text.AlignLeft : Text.AlignHCenter
		}
	}
}
