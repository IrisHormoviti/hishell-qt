pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MenuBar {
	id: menuBar

	property var directory
	property var config: directory.config
	property bool isLocal: directory.has_meta
property var fileManager

	Action {
		id: newFolderAction
		text: qsTr("New Folder")
		shortcut: "Ctrl+Shift+N"
		onTriggered: {
			if (menuBar.fileManager && menuBar.directory) {
				if (menuBar.fileManager.new_folder(menuBar.directory.path)) {
					menuBar.directory.refresh();
				}
			}
		}
	}

	Action {
		id: newTextFileAction
		text: qsTr("New Text File")
		shortcut: "Alt+Shift+N"
		onTriggered: {
			if (menuBar.fileManager && menuBar.directory) {
				if (menuBar.fileManager.new_text_file(menuBar.directory.path)) {
					menuBar.directory.refresh();
				}
			}
		}
	}

	Action {
		id: copyAction
		text: qsTr("Copy")
		shortcut: "Ctrl+C"
		onTriggered: {}
	}

	Action {
		id: cutAction
		text: qsTr("Cut")
		shortcut: Qt.CTRL | Qt.Key_X
		onTriggered: {}
	}

	Action {
		id: duplicateAction
		text: qsTr("Duplicate")
		shortcut: "Ctrl+D"
		onTriggered: {}
	}

	Action {
		id: linkAction
		text: qsTr("Create Link")
		shortcut: "Ctrl+S"
		onTriggered: {}
	}

	Action {
		id: renameAction
		text: qsTr("Rename")
		shortcut: "F2"
		onTriggered: {}
	}

	Action {
		id: increaseSizeAction
		text: qsTr("Increase Size")
		shortcut: "Ctrl+="
		onTriggered: {
			gridSizeSlider.value = Math.min(gridSizeSlider.value + 4, gridSizeSlider.to)
		}
	}

	Action {
		id: decreaseSizeAction
		text: qsTr("Decrease Size")
		shortcut: "Ctrl+-"
		onTriggered: {
			gridSizeSlider.value = Math.max(gridSizeSlider.value - 4, 0)
		}
	}

	ButtonGroup {
		id: viewModeGroup
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "ViewMode", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortGroup
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "Sort", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortDateMode
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "SortDateMode", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortAlphaMode
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "SortAlphaMode", button.objectName, menuBar.isLocal);
		}
	}

	Menu {
		title: qsTr("New")
		popupType: Popup.Window

		MenuItem {
			text: qsTr("Folder")
			icon.name: "folder-add"
			action: newFolderAction
		}
		MenuItem {
			text: qsTr("Text File")
			icon.name: "text-plain"
			action: newTextFileAction
		}
	}

	Menu {
		title: qsTr("Edit")
		popupType: Popup.Window

		MenuItem {
			text: qsTr("Copy")
			icon.name: "edit-copy"
			action: copyAction
		}
		MenuItem {
			text: qsTr("Cut")
			icon.name: "edit-cut"
			action: cutAction
		}
		MenuItem {
			text: qsTr("Duplicate")
			icon.name: "edit-duplicate"
			action: duplicateAction
		}
		MenuItem {
			text: qsTr("Create Link");
			icon.name: "edit-link"
			action: linkAction
		}
		MenuItem {
			text: qsTr("Rename")
			icon.name: "edit-rename"
			action: renameAction
		}
	}

	Menu {
		title: qsTr("View")
		popupType: Popup.Window

		onClosed: {
			menuBar.directory.refresh();
		}

		TabBar {
			id: viewTabBar
			Layout.fillWidth: true
			currentIndex: menuBar.isLocal ? 1 : 0

			TabButton {
				text: qsTr("General")
				onClicked: menuBar.isLocal = false
			}
			TabButton {
				text: qsTr("Here")
				onClicked: menuBar.isLocal = true
			}
		}

		MenuSeparator {}

		MenuItem {
			contentItem: RowLayout {
				Label {
					text: "Icon Size"
				}

				Slider {
					id: gridSizeSlider
					value: menuBar.config.grid_size
					from: 0
					to: 128
					stepSize: 4
					onMoved: {
						menuBar.directory.set_config("VIEW", "GridSize", value.toString(), menuBar.isLocal);
						menuBar.directory.refresh()
					}
				}

				TextMetrics {
					id: charMetrics
					text: "000"
				}

				Label {
					text: gridSizeSlider.value
					Layout.preferredWidth: charMetrics.width
					horizontalAlignment: Text.AlignHCenter
				}
			}
		}

		MenuSeparator {}

		MenuItem {
			contentItem: RowLayout {
				spacing: 4

				Label {
					text: qsTr("View Mode")
				}

				ToolButton {
					icon.name: "view-grid"
					checkable: true
					checked: menuBar.config.view_mode === 0
					display: AbstractButton.IconOnly
					ToolTip.text: qsTr("Grid View")
					ToolTip.visible: hovered
					ButtonGroup.group: viewModeGroup
					objectName: "GRID"
				}

				ToolButton {
					icon.name: "view-list-details"
					checkable: true
					checked: menuBar.config.view_mode === 1
					display: AbstractButton.IconOnly
					ToolTip.text: qsTr("List View")
					ButtonGroup.group: viewModeGroup
					ToolTip.visible: hovered
					objectName: "LIST"
				}
			}
		}

		MenuSeparator {}

		Menu {
			title: qsTr("Sort By...")
			icon.name: "view-sort"
			popupType: Popup.Window

			MenuItem {
				text: qsTr("Newest")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: menuBar.config.sort === 0
				objectName: "NEWEST"
			}
			MenuItem {
				text: qsTr("Oldest")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: menuBar.config.sort === 1
				objectName: "OLDEST"
			}
			Menu {
				title: qsTr("Which date...")
				popupType: Popup.Window

				MenuItem {
					text: qsTr("Modified")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: menuBar.config.sort_date_mode === 0
					objectName: "MODIFIED"
				}
				MenuItem {
					text: qsTr("Created")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: menuBar.config.sort_date_mode === 1
					objectName: "CREATED"
				}
				MenuItem {
					text: qsTr("Accessed")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: menuBar.config.sort_date_mode === 2
					objectName: "ACCESSED"
				}
			}

			MenuSeparator { }

			MenuItem {
				text: qsTr("Alphabetical")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: menuBar.config.sort === 2
				objectName: "ALPHABETICAL"
			}

			Menu {
				title: qsTr("Which name...")
				popupType: Popup.Window

				MenuItem {
					text: qsTr("Title")
					checkable: true
					ButtonGroup.group: sortAlphaMode
					checked: menuBar.config.sort_alpha_mode === 0
					objectName: "TITLES"
				}
				MenuItem {
					text: qsTr("File Name")
					checkable: true
					ButtonGroup.group: sortAlphaMode
					checked: menuBar.config.sort_alpha_mode === 1
					objectName: "FILENAMES"
				}
			}
		}

		MenuSeparator {}

		Menu {
			title: qsTr("Stash")
			icon.name: "pane-hide"
			popupType: Popup.Window

			MenuItem {
				text: qsTr("Show Stash")
				checkable: true
				checked: menuBar.config.stash_shown
				onToggled: {
					menuBar.config.set(menuBar.directory.path, "VIEW", "StashShown", String(checked), menuBar.isLocal);
				}
			}
			MenuItem {
				text: qsTr("Stash Dotfiles")
				checkable: true
				checked: menuBar.config.stash_dotfiles
				onToggled: {
					menuBar.config.set(menuBar.directory.path, "VIEW", "StashDotFiles", String(checked), menuBar.isLocal);
				}
			}
		}
	}
}
