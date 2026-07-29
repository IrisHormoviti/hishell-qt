pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Hishell"

Item {
	id: folderView
	property FileModel fileModel
	property FolderConfig config

	Layout.fillWidth: true
	Layout.fillHeight: true

	Component.onCompleted: {
		Qt.callLater(() => {
			if (folderView.config && folderView.fileModel) {
				folderView.config.load(folderView.fileModel.current_path);
				folderView.fileModel.load_directory(folderView.fileModel.current_path, !folderView.config.stash_dotfiles);
			} else {
				console.error("FolderView: missing fileModel or config.");
			}
		});
	}

	Connections {
		target: folderView.fileModel
		function onCurrent_pathChanged() {
			if (folderView.config && folderView.fileModel) {
				folderView.config.load(folderView.fileModel.current_path);
				folderView.fileModel.load_directory(folderView.fileModel.current_path, !folderView.config.stash_dotfiles);
			}
		}
	}

	property var positions: {
		try {
			return JSON.parse(folderView.config.arbitrary_positions);
		} catch (e) {
			return {};
		}
	}

	readonly property string folderName: {
		var path = folderView.fileModel ? folderView.fileModel.current_path : "";
		if (!path || path === "/" || path === ".")
			return "Root";
		if (path.endsWith("/") && path.length > 1) {
			path = path.substring(0, path.length - 1);
		}
		var name = path.split("/").pop();
		return name !== "" ? name : "Root";
	}

    Kirigami.Theme.colorSet: Kirigami.Theme.View

	Binding {
		target: folderView.Window.window
		property: "title"
		value: folderView.folderName
		restoreMode: Binding.RestoreBindingOrValue
	}

    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.backgroundColor
        radius: 8
        anchors.margins: 4
    }

	GridView {
		anchors.fill: parent
		anchors.margins: Kirigami.Units.largeSpacing

		// Align content to the top-left
		flow: GridView.FlowLeftToRight
		verticalLayoutDirection: GridView.TopToBottom

		model: folderView.fileModel

		cellWidth: folderView.config.grid_size + Kirigami.Units.gridUnit * 3
		cellHeight: folderView.config.grid_size + Kirigami.Units.gridUnit * 3

		delegate: FileSlot {
			config: folderView.config


			onNavigate: (targetPath) => {
				folderView.fileModel.open_path(targetPath)
			}
		}
	}
}
