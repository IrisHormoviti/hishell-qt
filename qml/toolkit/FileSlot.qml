pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami


Item {
	id: fileSlot
	width: GridView.view.cellWidth
	height: GridView.view.cellHeight

	required property string path
	required property string icon
	required property string title

	property int gridSize: 64

	signal navigate(string targetPath)

	ColumnLayout {
		anchors.centerIn: parent
		spacing: Kirigami.Units.smallSpacing

		Kirigami.Icon {
			Layout.alignment: Qt.AlignHCenter
			source: fileSlot.icon
			Layout.preferredWidth: fileSlot.gridSize
			Layout.preferredHeight: fileSlot.gridSize
		}

		Label {
			id: labelItem
			Layout.alignment: Qt.AlignHCenter
			text: fileSlot.title
			color: Kirigami.Theme.textColor
			elide: Text.ElideMiddle
			Layout.maximumWidth: fileSlot.gridSize + Kirigami.Units.gridUnit * 2
			horizontalAlignment: Text.AlignHCenter
		}
	}

	MouseArea {
		anchors.fill: parent
		onClicked: {
			fileSlot.navigate(fileSlot.path);
		}
	}
}
