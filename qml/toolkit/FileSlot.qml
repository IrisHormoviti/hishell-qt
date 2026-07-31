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
	property bool labelBesideIcon: gridSize < 32

	signal navigate(string targetPath)

	GridLayout {
		anchors.verticalCenter: parent.verticalCenter
		x: fileSlot.labelBesideIcon ? Kirigami.Units.largeSpacing : (parent.width - width) / 2
		columns: fileSlot.labelBesideIcon ? 2 : 1

		Kirigami.Icon {
			Layout.alignment: fileSlot.labelBesideIcon ? Qt.AlignVCenter : Qt.AlignHCenter
			source: fileSlot.icon
			Layout.preferredWidth: fileSlot.gridSize
			Layout.preferredHeight: fileSlot.gridSize
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

	MouseArea {
		anchors.fill: parent
		onClicked: {
			fileSlot.navigate(fileSlot.path);
		}
	}
}
