import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt
import org.kde.kirigami as Kirigami

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

	property var contextActions: []

	Menu {
		id: contextMenu
		onAboutToShow: window.contextActions = JSON.parse(
			window.directory.actions_json("context", "focus"))

		Repeater {
			model: window.contextActions

			MenuItem {
				required property var modelData
				text: modelData.id
				enabled: modelData.enabled
				onTriggered: window.directory.invoke(modelData.id)
			}
		}
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

			Label {
				text: window.directory.selectedCount + " selected"
				visible: window.directory.selectionActive
			}

			Button {
				text: "Select all"
				onClicked: window.directory.select_all()
			}

			Button {
				text: "Clear"
				visible: window.directory.selectionActive
				onClicked: window.directory.clear_selection()
			}

			Button {
				text: "Reload"
				onClicked: window.directory.refresh_async()
			}
		}

		RowLayout {
			Layout.fillWidth: true
			Layout.leftMargin: 8
			Layout.rightMargin: 8
			Layout.bottomMargin: 8

			Label { text: "View" }

			ComboBox {
				model: ["Grid", "List"]
				Component.onCompleted: currentIndex = window.directory.config.view_mode === "LIST" ? 1 : 0
				onActivated: window.directory.set_config("view_mode", index === 1 ? "LIST" : "GRID")
			}

			Label { text: "Mode" }

			ComboBox {
				model: ["Lines", "Size"]
				Component.onCompleted: currentIndex = window.directory.config.grid_mode === "SIZE" ? 1 : 0
				onActivated: window.directory.set_config("grid_mode", index === 1 ? "SIZE" : "LINES")
			}

			Label { text: "Lines" }

			SpinBox {
				from: 1
				to: 8
				Component.onCompleted: value = window.directory.config.grid_lines
				onValueModified: window.directory.set_config("grid_lines", String(value))
			}

			Label { text: "Icon" }

			SpinBox {
				from: 16
				to: 256
				stepSize: 8
				Component.onCompleted: value = window.directory.config.grid_size
				onValueModified: window.directory.set_config("grid_size", String(value))
			}

			CheckBox {
				text: "Labels"
				Component.onCompleted: checked = window.directory.config.show_labels
				onToggled: window.directory.set_config("show_labels", checked ? "true" : "false")
			}

			Item { Layout.fillWidth: true }
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
					id: cell
					required property string name
					required property string path
					required property string icon
					required property bool is_directory

					readonly property bool selected: {
						window.directory.selectionRevision
						return window.directory.is_selected(path)
					}

					width: grid.cellWidth
					height: grid.cellHeight

					Rectangle {
						anchors.fill: parent
						anchors.margins: 2
						radius: 6
						color: cell.selected ? "#8a6ff0" : "transparent"
						opacity: cell.selected ? 0.28 : 0
					}

					Column {
						anchors.centerIn: parent
						spacing: 4

						Kirigami.Icon {
							width: window.spec.icon_size || 48
							height: width
							source: cell.icon
							anchors.horizontalCenter: parent.horizontalCenter
						}

						Label {
							width: grid.cellWidth - 8
							text: name
							elide: Text.ElideMiddle
							horizontalAlignment: Text.AlignHCenter
						}
					}

					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						onClicked: function (mouse) {
							if (mouse.button === Qt.RightButton) {
								window.directory.focus_path(cell.path)
								contextMenu.popup()
							} else {
								window.directory.toggle_select(cell.path)
							}
						}
					}
				}
			}

			ListView {
				anchors.fill: parent
				clip: true
				visible: window.spec.mode !== "grid"
				model: window.directory

				delegate: Rectangle {
					id: row
					required property string name
					required property string path
					required property string icon

					readonly property bool selected: {
						window.directory.selectionRevision
						return window.directory.is_selected(path)
					}

					width: ListView.view.width
					height: 30
					color: row.selected ? "#8a6ff0" : "transparent"

					RowLayout {
						anchors.fill: parent
						anchors.leftMargin: 6
						anchors.rightMargin: 6
						spacing: 8

						Kirigami.Icon {
							source: row.icon
							width: 18
							height: 18
						}

						Label {
							text: row.name
							elide: Text.ElideRight
							Layout.fillWidth: true
						}
					}

					MouseArea {
						anchors.fill: parent
						acceptedButtons: Qt.LeftButton | Qt.RightButton
						onClicked: function (mouse) {
							if (mouse.button === Qt.RightButton) {
								window.directory.focus_path(row.path)
								contextMenu.popup()
							} else {
								window.directory.toggle_select(row.path)
							}
						}
					}
				}
			}
		}
	}
}
