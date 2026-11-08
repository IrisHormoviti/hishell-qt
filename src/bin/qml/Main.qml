import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt

ApplicationWindow {
	id: window
	width: 720
	height: 520
	visible: true
	title: "hishell qtbridge preview"

	required property var directory

	PathBridge {
		id: pathUtils
	}

	readonly property var spec: {
		window.directory.revision
		return JSON.parse(window.directory.view_json(grid.width, grid.height, 18, 4, 18))
	}

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		RowLayout {
			Layout.fillWidth: true
			Layout.margins: 8

			Label {
				text: pathUtils.folder_name(window.directory.path)
				font.bold: true
			}

			Label {
				text: window.directory.path
				elide: Text.ElideMiddle
				Layout.fillWidth: true
			}

			Label {
				text: window.spec.mode + " · " + (window.spec.lines || 0) + " lines · "
					+ Math.round(window.spec.icon_size || 0) + "px"
			}

			Button {
				text: "Reload"
				onClicked: window.directory.refresh_async()
			}
		}

		Frame {
			Layout.fillWidth: true
			Layout.fillHeight: true
			Layout.margins: 8

			GridView {
				id: grid
				anchors.fill: parent
				clip: true
				model: window.directory
				cellWidth: window.spec.cell_width || 96
				cellHeight: window.spec.cell_height || 96

				delegate: Item {
					required property string name
					required property bool is_directory

					width: grid.cellWidth
					height: grid.cellHeight

					Column {
						anchors.centerIn: parent
						spacing: 4

						Rectangle {
							width: window.spec.icon_size || 48
							height: width
							radius: 6
							anchors.horizontalCenter: parent.horizontalCenter
							color: is_directory ? "#d9b45b" : "#7a8b99"
						}

						Label {
							width: grid.cellWidth - 8
							text: name
							elide: Text.ElideMiddle
							horizontalAlignment: Text.AlignHCenter
						}
					}
				}
			}
		}
	}
}
