pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

Item {
	id: folderView
	property var model
	property var config

	Connections {
		target: folderView.model
		function onCurrent_pathChanged() {
			if (folderView.config && folderView.model) {
				// Load config for the target directory first
				folderView.config.load(folderView.model.current_path);
				// Reload directory items using the updated config setting
				folderView.model.load_directory(folderView.model.current_path, !folderView.config.stash_dotfiles);
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
		var path = folderView.model ? folderView.model.current_path : "";
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

		model: folderView.model

		cellWidth: folderView.config.grid_size + Kirigami.Units.gridUnit * 3
		cellHeight: folderView.config.grid_size + Kirigami.Units.gridUnit * 3

		delegate: FileSlot {
			config: folderView.config


			onNavigate: (targetPath) => {
				folderView.model.open_path(targetPath)
			}
		}
	}
}
