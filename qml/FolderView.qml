pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Hishell"
import "toolkit"

Item {
	id: folderView
	property Directory directory
	property Config config: directory.config
	property Directory windowDirectory: folderView.directory

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
		function onConfig_changed() {
			console.log("we got em")
			folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
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

	Flickable {
		anchors.fill: parent
		anchors.margins: Kirigami.Units.mediumSpacing
		contentWidth: width
		contentHeight: flowLayout.height

		Flow {
			id: flowLayout
			width: parent.width
			spacing: Kirigami.Units.mediumSpacing

			Repeater {
				model: folderView.directory

				delegate: FileSlot {
					width: labelBesideIcon ? Kirigami.Units.gridUnit * 10 : gridSize + Kirigami.Units.gridUnit * 3
					height: labelBesideIcon ? Kirigami.Units.gridUnit * 2 : gridSize + Kirigami.Units.gridUnit * 3

					gridSize: folderView.config.grid_size

					onNavigate: (targetPath) => {
						(folderView.windowDirectory || folderView.directory).open_path(targetPath)
					}
				}
			}
		}
	}
}
