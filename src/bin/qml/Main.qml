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

	ColumnLayout {
		anchors.fill: parent
		spacing: 0

		RowLayout {
			Layout.fillWidth: true
			Layout.margins: 8

			Label {
				text: window.directory.path
				elide: Text.ElideMiddle
				Layout.fillWidth: true
			}

			Label {
				text: window.directory.config.gridMode + " · " + window.directory.config.gridLines + " lines"
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

			ListView {
				anchors.fill: parent
				clip: true
				model: window.directory

				delegate: RowLayout {
					required property string name
					required property bool is_directory

					width: ListView.view.width

					Label {
						text: is_directory ? "folder" : "file"
						opacity: 0.6
					}

					Label {
						text: name
						elide: Text.ElideRight
						Layout.fillWidth: true
					}
				}
			}
		}
	}
}
