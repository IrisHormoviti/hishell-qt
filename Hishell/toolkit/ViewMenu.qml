import QtQuick
import QtQuick.Controls
import QtQuick.Layouts


Menu {
	id: viewMenu
	required property var directory
	property var config: directory ? directory.config : null
	property bool isLocal: directory ? directory.has_meta : false
	readonly property bool hasFreePlacementPositions: {
		if (!viewMenu.config)
			return false;
		try {
			const positions = JSON.parse(viewMenu.config.free_placement_positions);
			return !!positions && Object.keys(positions).length > 0;
		} catch (e) {
			return false;
		}
	}
	visible: false
	height: contentHeight

	title: qsTr("&View")
	popupType: Popup.Native

	function setSort(value) {
		if (viewMenu.directory) {
			viewMenu.directory.set_config("VIEW", "Sort", value, viewMenu.isLocal);
			viewMenu.directory.reload();
		}
	}

	function setViewMode(value) {
		if (viewMenu.directory) {
			viewMenu.directory.set_config("VIEW", "ViewMode", value, viewMenu.isLocal);
			viewMenu.directory.reload();
		}
	}

	function resetFreePlacement() {
		if (viewMenu.directory)
			viewMenu.directory.reset_free_positions();
	}

	ButtonGroup {
		id: viewModeGroup
	}
	ButtonGroup {
		id: sortGroup
	}
	ButtonGroup {
		id: sortDateMode
	}
	ButtonGroup {
		id: sortAlphaMode
	}

	TabBar {
		Layout.fillWidth: true
		currentIndex: viewMenu.isLocal ? 1 : 0
		TabButton {
			text: qsTr("General")
			onClicked: viewMenu.isLocal = false
		}
		TabButton {
			text: qsTr("Here")
			onClicked: viewMenu.isLocal = true
		}
	}

	MenuSeparator {}

	MenuItem {
		contentItem: RowLayout {
			Label {
				text: qsTr("Icon Size")
			}
			Slider {
				id: gridSizeSlider
				value: viewMenu.config ? viewMenu.config.grid_size : 64
				from: 16
				to: 256
				stepSize: 4
				onMoved: if (viewMenu.directory) {
					viewMenu.directory.set_config("VIEW", "GridSize", value.toString(), viewMenu.isLocal);
					viewMenu.directory.reload();
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

	Action {
		id: increaseSizeAction
		text: qsTr("Zoom In")
		shortcut: "Ctrl+="
		onTriggered: gridSizeSlider.value = Math.min(gridSizeSlider.value + 4, gridSizeSlider.to)
	}

	Action {
		id: decreaseSizeAction
		text: qsTr("Zoom Out")
		shortcut: "Ctrl+-"
		onTriggered: gridSizeSlider.value = Math.max(gridSizeSlider.value - 4, gridSizeSlider.from)
	}

	MenuSeparator {}

	MenuItem {
		contentItem: RowLayout {
			Label {
				text: qsTr("View Mode")
			}
			ToolButton {
				icon.name: "view-grid"
				checkable: true
				checked: viewMenu.config ? viewMenu.config.view_mode === 0 : false
				display: AbstractButton.IconOnly
				ToolTip.text: qsTr("Grid View")
				ToolTip.visible: hovered
				ButtonGroup.group: viewModeGroup
				objectName: "GRID"
				onClicked: viewMenu.setViewMode("GRID")
			}
			ToolButton {
				icon.name: "view-list-details"
				checkable: true
				checked: viewMenu.config ? viewMenu.config.view_mode === 1 : false
				display: AbstractButton.IconOnly
				ToolTip.text: qsTr("List View")
				ToolTip.visible: hovered
				ButtonGroup.group: viewModeGroup
				objectName: "LIST"
				onClicked: viewMenu.setViewMode("LIST")
			}
		}
	}

	MenuSeparator {}

	Menu {
		title: qsTr("Sort By...")
		icon.name: "view-sort"
		popupType: Popup.Item
		MenuItem {
			text: qsTr("Newest")
			checkable: true
			ButtonGroup.group: sortGroup
			checked: viewMenu.config ? viewMenu.config.sort === 0 : false
			objectName: "NEWEST"
			onTriggered: viewMenu.setSort("NEWEST")
		}
		MenuItem {
			text: qsTr("Oldest")
			checkable: true
			ButtonGroup.group: sortGroup
			checked: viewMenu.config ? viewMenu.config.sort === 1 : false
			objectName: "OLDEST"
			onTriggered: viewMenu.setSort("OLDEST")
		}
		Menu {
			title: qsTr("Which date...")
			MenuItem {
				text: qsTr("Modified")
				checkable: true
				ButtonGroup.group: sortDateMode
				checked: viewMenu.config ? viewMenu.config.sort_date_mode === 0 : false
				objectName: "MODIFIED"
			}
			MenuItem {
				text: qsTr("Created")
				checkable: true
				ButtonGroup.group: sortDateMode
				checked: viewMenu.config ? viewMenu.config.sort_date_mode === 1 : false
				objectName: "CREATED"
			}
			MenuItem {
				text: qsTr("Accessed")
				checkable: true
				ButtonGroup.group: sortDateMode
				checked: viewMenu.config ? viewMenu.config.sort_date_mode === 2 : false
				objectName: "ACCESSED"
			}
		}
		MenuSeparator {}
		MenuItem {
			text: qsTr("Alphabetical")
			checkable: true
			ButtonGroup.group: sortGroup
			checked: viewMenu.config ? viewMenu.config.sort === 2 : false
			objectName: "ALPHABETICAL"
			onTriggered: viewMenu.setSort("ALPHABETICAL")
		}
		Menu {
			title: qsTr("Which name...")
			MenuItem {
				text: qsTr("Title")
				checkable: true
				ButtonGroup.group: sortAlphaMode
				checked: viewMenu.config ? viewMenu.config.sort_alpha_mode === 0 : false
				objectName: "TITLES"
			}
			MenuItem {
				text: qsTr("File Name")
				checkable: true
				ButtonGroup.group: sortAlphaMode
				checked: viewMenu.config ? viewMenu.config.sort_alpha_mode === 1 : false
				objectName: "FILENAMES"
			}
		}
		MenuSeparator {}
		MenuItem {
			text: qsTr("Free Placement")
			checkable: true
			ButtonGroup.group: sortGroup
			checked: viewMenu.config ? viewMenu.config.sort === 3 : false
			enabled: viewMenu.isLocal
			objectName: "FREE"
			onTriggered: viewMenu.setSort("FREE")
		}
		MenuItem {
			text: qsTr("Reset Manual Placement")
			icon.name: "edit-reset"
			enabled: viewMenu.hasFreePlacementPositions
			onTriggered: viewMenu.resetFreePlacement()
		}
	}

	MenuSeparator {}

	Menu {
		title: qsTr("Stash")
		icon.name: "pane-hide"
		MenuItem {
			text: qsTr("Show Stash")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.stash_shown : false
			onToggled: if (viewMenu.config && viewMenu.directory)
				viewMenu.config.set(viewMenu.directory.path, "VIEW", "StashShown", String(checked), viewMenu.isLocal)
		}
		MenuItem {
			text: qsTr("Stash Dotfiles")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.stash_dotfiles : false
			onToggled: if (viewMenu.config && viewMenu.directory)
				viewMenu.config.set(viewMenu.directory.path, "VIEW", "StashDotFiles", String(checked), viewMenu.isLocal)
		}
	}
}
