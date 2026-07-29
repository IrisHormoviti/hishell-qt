import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Hishell"

Item {
	id: fileSlot
	width: GridView.view.cellWidth
	height: GridView.view.cellHeight

	required property FolderConfig config

	required property string name
	required property bool is_dir
	required property string path
	required property string icon

	signal navigate(string targetPath)

	ColumnLayout {
		anchors.centerIn: parent
		spacing: Kirigami.Units.smallSpacing

		Kirigami.Icon {
			Layout.alignment: Qt.AlignHCenter
			source: fileSlot.icon
			Layout.preferredWidth: fileSlot.config.grid_size
			Layout.preferredHeight: fileSlot.config.grid_size
		}

		Label {
			Layout.alignment: Qt.AlignHCenter
			text: fileSlot.name
			color: Kirigami.Theme.textColor
			elide: Text.ElideMiddle
			Layout.maximumWidth: fileSlot.config.grid_size + Kirigami.Units.gridUnit * 2
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
