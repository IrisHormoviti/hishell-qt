pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Item {
	id: folderView
	property var model
	property var config

	property var positions: {
		try {
			return JSON.parse(folderView.config.arbitrary_positions);
		} catch (e) {
			return {};
		}
	}

	readonly property string folderName: {
		var path = folderView.model ? folderView.model.current_path : "";
		if (!path || path === "/" || path === ".")
			return "Root";
		if (path.endsWith("/") && path.length > 1) {
			path = path.substring(0, path.length - 1);
		}
		var name = path.split("/").pop();
		return name !== "" ? name : "Root";
	}

	Binding {
		target: folderView.Window.window
		property: "title"
		value: folderView.folderName
		restoreMode: Binding.RestoreBindingOrValue
	}

	GridView {
		anchors.fill: parent
		anchors.margins: Kirigami.Units.largeSpacing

		// Align content to the top-left
		flow: GridView.FlowLeftToRight
		verticalLayoutDirection: GridView.TopToBottom

		model: folderView.model

		cellWidth: folderView.config.grid_size + Kirigami.Units.gridUnit * 3
		cellHeight: folderView.config.grid_size + Kirigami.Units.gridUnit * 3

		delegate: Item {
			id: delegateRoot
			width: GridView.view.cellWidth
			height: GridView.view.cellHeight

			required property string name
			required property bool is_dir
			required property string path

			ColumnLayout {
				anchors.centerIn: parent
				spacing: Kirigami.Units.smallSpacing

				Kirigami.Icon {
					Layout.alignment: Qt.AlignHCenter
					source: delegateRoot.is_dir ? "folder" : "text-plain"
					Layout.preferredWidth: folderView.config.grid_size
					Layout.preferredHeight: folderView.config.grid_size
				}

				Label {
					Layout.alignment: Qt.AlignHCenter
					text: delegateRoot.name
					color: Kirigami.Theme.textColor
					elide: Text.ElideMiddle
					Layout.maximumWidth: folderView.config.grid_size + Kirigami.Units.gridUnit * 2
					horizontalAlignment: Text.AlignHCenter
				}
			}

			MouseArea {
				anchors.fill: parent
				onDoubleClicked: {
					if (delegateRoot.is_dir) {
						folderView.model.current_path = delegateRoot.path;
					}
				}
			}
		}
	}
}
