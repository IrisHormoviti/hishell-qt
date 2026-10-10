import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs


Menu {
	id: viewMenu
	required property var directory
	property var config: directory ? directory.config : null
	property bool isLocal: directory ? directory.has_meta : false
	readonly property string viewConfigGroupName: "Folder View"
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

	// Write a setting to a config section. The scope follows the General/Here tab:
	// the global config, or this folder's own .directory.
	function setSectionConfig(section, key, value) {
		if (viewMenu.directory)
			viewMenu.directory.set_config(section, key, value, viewMenu.isLocal);
	}

	function setConfig(key, value) {
		viewMenu.setSectionConfig(viewConfigGroupName, key, value);
	}

	function setNavigationConfig(key, value) {
		viewMenu.setSectionConfig("Folder Navigation", key, value);
	}

	function setSort(value) {
		viewMenu.setConfig("Sort", value);
	}

	function setViewMode(value) {
		viewMenu.setConfig("ViewMode", value);
	}

	function resetFreePlacement() {
		if (viewMenu.directory)
			viewMenu.directory.reset_free_positions();
	}

	function pathFromUrl(url) {
		let path = String(url);
		if (path.startsWith("file://"))
			path = path.substring(7);
		return decodeURIComponent(path);
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
	ButtonGroup {
		id: scrollDirectionGroup
	}
	ButtonGroup {
		id: horizontalAlignGroup
	}
	ButtonGroup {
		id: verticalAlignGroup
	}

	FileDialog {
		id: wallpaperDialog
		title: qsTr("Choose Wallpaper")
		nameFilters: [qsTr("Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.gif *.svg)"), qsTr("All files (*)")]
		onAccepted: viewMenu.setConfig("Wallpaper", viewMenu.pathFromUrl(wallpaperDialog.selectedFile))
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
				onMoved: viewMenu.setConfig("GridSize", value.toString())
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

	MenuItem {
		contentItem: RowLayout {
			Label {
				text: qsTr("Lines")
			}
			Slider {
				id: linesSlider
				value: viewMenu.config ? viewMenu.config.grid_lines : 0
				from: 0
				to: 20
				stepSize: 1
				onMoved: viewMenu.setConfig("Lines", value.toString())
			}
			TextMetrics {
				id: autoMetrics
				text: qsTr("Auto")
			}
			Label {
				text: linesSlider.value === 0 ? qsTr("Auto") : linesSlider.value
				Layout.preferredWidth: autoMetrics.width
				horizontalAlignment: Text.AlignHCenter
			}
		}
	}

	Action {
		id: increaseSizeAction
		text: qsTr("Zoom In")
		shortcut: "Ctrl+="
		onTriggered: viewMenu.setConfig("GridSize", String(Math.min(gridSizeSlider.value + 4, gridSizeSlider.to)))
	}

	Action {
		id: decreaseSizeAction
		text: qsTr("Zoom Out")
		shortcut: "Ctrl+-"
		onTriggered: viewMenu.setConfig("GridSize", String(Math.max(gridSizeSlider.value - 4, gridSizeSlider.from)))
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

	Menu {
		title: qsTr("Labels")
		icon.name: "format-text"
		popupType: Popup.Item
		MenuItem {
			text: qsTr("Show Labels")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.show_labels : true
			onToggled: viewMenu.setConfig("ShowLabels", String(checked))
		}
		MenuItem {
			text: qsTr("Labels Beside Icons")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.grid_labels_beside_icons : false
			enabled: viewMenu.config ? viewMenu.config.show_labels : true
			onToggled: viewMenu.setConfig("GridLabelsBesidesIcons", String(checked))
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
				onTriggered: viewMenu.setConfig("SortDateMode", "MODIFIED")
			}
			MenuItem {
				text: qsTr("Created")
				checkable: true
				ButtonGroup.group: sortDateMode
				checked: viewMenu.config ? viewMenu.config.sort_date_mode === 1 : false
				objectName: "CREATED"
				onTriggered: viewMenu.setConfig("SortDateMode", "CREATED")
			}
			MenuItem {
				text: qsTr("Accessed")
				checkable: true
				ButtonGroup.group: sortDateMode
				checked: viewMenu.config ? viewMenu.config.sort_date_mode === 2 : false
				objectName: "ACCESSED"
				onTriggered: viewMenu.setConfig("SortDateMode", "ACCESSED")
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
				onTriggered: viewMenu.setConfig("SortAlphaMode", "TITLES")
			}
			MenuItem {
				text: qsTr("File Name")
				checkable: true
				ButtonGroup.group: sortAlphaMode
				checked: viewMenu.config ? viewMenu.config.sort_alpha_mode === 1 : false
				objectName: "FILENAMES"
				onTriggered: viewMenu.setConfig("SortAlphaMode", "FILENAMES")
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

	Menu {
		title: qsTr("Arrange")
		icon.name: "format-justify-fill"
		popupType: Popup.Item
		Menu {
			title: qsTr("Scroll Direction")
			MenuItem {
				text: qsTr("Vertical")
				checkable: true
				ButtonGroup.group: scrollDirectionGroup
				checked: viewMenu.config ? !viewMenu.config.scroll_horizontal : true
				objectName: "VERTICAL"
				onTriggered: viewMenu.setConfig("ScrollDirection", "VERTICAL")
			}
			MenuItem {
				text: qsTr("Horizontal")
				checkable: true
				ButtonGroup.group: scrollDirectionGroup
				checked: viewMenu.config ? viewMenu.config.scroll_horizontal : false
				objectName: "HORIZONTAL"
				onTriggered: viewMenu.setConfig("ScrollDirection", "HORIZONTAL")
			}
		}
		Menu {
			title: qsTr("Horizontal Align")
			MenuItem {
				text: qsTr("Fill")
				checkable: true
				ButtonGroup.group: horizontalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_horizontal_align === 0 : true
				objectName: "HALIGN_FILL"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "FILL")
			}
			MenuItem {
				text: qsTr("Left")
				checkable: true
				ButtonGroup.group: horizontalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_horizontal_align === 1 : false
				objectName: "HALIGN_LEFT"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "LEFT")
			}
			MenuItem {
				text: qsTr("Center")
				checkable: true
				ButtonGroup.group: horizontalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_horizontal_align === 2 : false
				objectName: "HALIGN_CENTER"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "CENTER")
			}
			MenuItem {
				text: qsTr("Right")
				checkable: true
				ButtonGroup.group: horizontalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_horizontal_align === 3 : false
				objectName: "HALIGN_RIGHT"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "RIGHT")
			}
		}
		Menu {
			title: qsTr("Vertical Align")
			MenuItem {
				text: qsTr("Fill")
				checkable: true
				ButtonGroup.group: verticalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_vertical_align === 0 : false
				objectName: "VALIGN_FILL"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "FILL")
			}
			MenuItem {
				text: qsTr("Top")
				checkable: true
				ButtonGroup.group: verticalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_vertical_align === 1 : true
				objectName: "VALIGN_TOP"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "TOP")
			}
			MenuItem {
				text: qsTr("Center")
				checkable: true
				ButtonGroup.group: verticalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_vertical_align === 2 : false
				objectName: "VALIGN_CENTER"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "CENTER")
			}
			MenuItem {
				text: qsTr("Bottom")
				checkable: true
				ButtonGroup.group: verticalAlignGroup
				checked: viewMenu.config ? viewMenu.config.grid_vertical_align === 3 : false
				objectName: "VALIGN_BOTTOM"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "BOTTOM")
			}
		}
	}

	Menu {
		title: qsTr("Navigation")
		icon.name: "transform-move"
		popupType: Popup.Item
		MenuItem {
			text: qsTr("Center Focus")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.center_focus : false
			onToggled: viewMenu.setNavigationConfig("CenterFocus", String(checked))
		}
		MenuItem {
			text: qsTr("Smooth Scrolling")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.smooth_scrolling : true
			onToggled: viewMenu.setNavigationConfig("SmoothScrolling", String(checked))
		}
	}

	Menu {
		title: qsTr("Wallpaper")
		icon.name: "preferences-desktop-wallpaper"
		popupType: Popup.Item
		MenuItem {
			text: qsTr("Set Wallpaper...")
			icon.name: "document-open"
			onTriggered: wallpaperDialog.open()
		}
		MenuItem {
			text: qsTr("Clear Wallpaper")
			icon.name: "edit-clear"
			enabled: viewMenu.config ? viewMenu.config.wallpaper !== "" : false
			onTriggered: viewMenu.setConfig("Wallpaper", "")
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
			onToggled: viewMenu.setConfig("StashShown", String(checked))
		}
		MenuItem {
			text: qsTr("Stash Dotfiles")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.stash_dotfiles : false
			onToggled: viewMenu.setConfig("StashDotFiles", String(checked))
		}
	}
}
