pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Hishell"

Item {
	id: folderView
	property Directory directory
	property Config config: directory.config

	Layout.fillWidth: true
	Layout.fillHeight: true

	Component.onCompleted: {
		Qt.callLater(() => {
			if (folderView.config && folderView.directory) {
				folderView.config.load(folderView.directory.path);
				folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
			} else {
				console.error("FolderView: missing directory or config.");
			}
		});
	}

	Connections {
		target: folderView.directory
		function onPathChanged() {
			if (folderView.config && folderView.directory) {
				folderView.config.load(folderView.directory.path);
				folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
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
		let path = folderView.directory.path.toString();
		if (!path || path === "/" || path === ".")
			return "/";
		if (path.endsWith("/") && path.length > 1) {
			path = path.substring(0, path.length - 1);
		}
		let name = path.split("/").pop();
		return name !== "" ? name : "/";
	}

    Kirigami.Theme.colorSet: Kirigami.Theme.View

	Binding {
		target: folderView.Window.window
		property: "title"
		value: folderView.folderName
		restoreMode: Binding.RestoreBindingOrValue
	}

	Image {
		id: wallpaper
		anchors.fill: parent
		source: String(folderView.config ? folderView.config.wallpaper : "")
		fillMode: Image.PreserveAspectCrop
		visible: status === Image.Ready
	}

	Rectangle {
		anchors.fill: parent
		color: wallpaper.status === Image.Ready ? "transparent" : Kirigami.Theme.backgroundColor
		radius: 8
		anchors.margins: 4
	}

	GridView {
		anchors.fill: parent
		anchors.margins: Kirigami.Units.largeSpacing

		// Align content to the top-left
		flow: GridView.FlowLeftToRight
		verticalLayoutDirection: GridView.TopToBottom

		model: folderView.directory

		cellWidth: folderView.config.grid_size + Kirigami.Units.gridUnit * 3
		cellHeight: folderView.config.grid_size + Kirigami.Units.gridUnit * 3

		delegate: FileSlot {
			gridSize: folderView.config.grid_size

			onNavigate: (targetPath) => {
				folderView.directory.open_path(targetPath)
			}
		}
	}
}
