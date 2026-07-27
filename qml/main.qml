import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Kirigami.ApplicationWindow {
	id: root
	width: 800
	height: 600
	visible: true
	title: "Shell"

	FolderConfig {
		id: folderConfig
	}

	FileModel {
		id: fileModel
	}

	FileManager {
		id: fileManager
	}

	Component.onCompleted: {
		var startPath = typeof initialPath !== "undefined" ? initialPath : ".";
		folderConfig.load(startPath);
		fileModel.current_path = startPath;
	}

	pageStack.initialPage: Kirigami.Page {
		padding: 0
		topPadding: 0
		leftPadding: 0
		rightPadding: 0
		bottomPadding: 0

		// Remove Kirigami's own header so ours is the only one
		globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

		ColumnLayout {
			anchors.fill: parent
			spacing: 0

			// Header bar — uses theme background, no hardcoded color
			RowLayout {
				Layout.fillWidth: true
				Layout.preferredHeight: 44
				Layout.margins: 0
				spacing: Kirigami.Units.smallSpacing

				// Left padding
				Item {
					Layout.preferredWidth: Kirigami.Units.largeSpacing
				}

				LayoutEngine {
					fileModel: fileModel
					layoutString: String(folderConfig.header_layout)
					Layout.fillWidth: true
				}

				// Right padding
				Item {
					Layout.preferredWidth: Kirigami.Units.largeSpacing
				}
			}

			// Thin separator line
			Kirigami.Separator {
				Layout.fillWidth: true
			}

			// Top Layout area (from config)
			LayoutEngine {
				fileModel: fileModel
				layoutString: String(folderConfig.top_layout)
				Layout.fillWidth: true
			}

			// Main content area
			RowLayout {
				Layout.fillWidth: true
				Layout.fillHeight: true
				spacing: 0

				LayoutEngine {
					fileModel: fileModel
					layoutString: String(folderConfig.middle_layout)
					Layout.fillHeight: true
				}

				FolderView {
					Layout.fillWidth: true
					Layout.fillHeight: true
					model: fileModel
					config: folderConfig
				}
			}

			// Bottom Layout area (from config)
			LayoutEngine {
				fileModel: fileModel
				layoutString: String(folderConfig.bottom_layout)
				Layout.fillWidth: true
			}
		}
	}
}
