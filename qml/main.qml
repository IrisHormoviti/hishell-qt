import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Hishell"

Kirigami.ApplicationWindow {
	id: root
	width: 800
	height: 600
	visible: true
	// flags: Qt.Window | Qt.FramelessWindowHint

	WindowOverlay {}

	Config {
		id: config
	}

	Directory {
		id: directory
	}

	FileManager {
		id: fileManager
	}

	property string initialPath: "."

	Component.onCompleted: {
		var startPath = root.initialPath;
		config.load(startPath);
		directory.path = startPath;
	}

	pageStack.initialPage: Kirigami.Page {
		padding: 0
		topPadding: 0
		leftPadding: 0
		rightPadding: 0
		bottomPadding: 0

		// Remove Kirigami's own header
		globalToolBarStyle: Kirigami.ApplicationHeaderStyle.None

		ColumnLayout {
			anchors.fill: parent
			spacing: 0

			// Header bar
			Item {
				Layout.fillWidth: true
				Layout.preferredHeight: 44
				Kirigami.Theme.colorSet: Kirigami.Theme.Header
				Kirigami.Theme.inherit: false

				Rectangle {
					anchors.fill: parent
					z: -1
					color: Kirigami.Theme.backgroundColor
				}

				RowLayout {
					anchors.fill: parent

					Layout.fillWidth: true
					Layout.preferredHeight: 44
					Layout.margins: 0
					spacing: Kirigami.Units.smallSpacing

					// Make it draggable
					DragHandler {
						target: null
						onActiveChanged: if (active)
							root.startSystemMove()
					}

					// Left padding
					Item {
						Layout.preferredWidth: Kirigami.Units.largeSpacing
					}

					LayoutEngine {
						directory: directory
						config: config
						layoutString: String(config.header_layout)
						Layout.fillWidth: true
					}

					// Right padding
					Item {
						Layout.preferredWidth: Kirigami.Units.largeSpacing
					}
				}
			}

			// Thin separator line
			Kirigami.Separator {
				Layout.fillWidth: true
			}

			// Top Layout area
			LayoutEngine {
				directory: directory
				config: config
				layoutString: String(config.top_layout)
				Layout.fillWidth: true
			}

			// Main content area
			RowLayout {
				Layout.fillWidth: true
				Layout.fillHeight: true
				spacing: 0

				LayoutEngine {
					directory: directory
					config: config
					layoutString: String(config.middle_layout)
					Layout.fillHeight: true
					Layout.fillWidth: true
				}
			}

			// Bottom Layout area
			LayoutEngine {
				directory: directory
				config: config
				layoutString: String(config.bottom_layout)
				Layout.fillWidth: true
			}
		}
	}
}
