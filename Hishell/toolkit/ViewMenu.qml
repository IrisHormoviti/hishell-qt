pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import org.kde.kirigami as Kirigami


Menu {
	id: viewMenu
	required property var directory
	// The owning window, for event sounds. A menu is not a visual child of the
	// window, so `Window.window` is not reliable here; the owner passes it in.
	property var window

	// The menu and the ViewButton dialog act on the same shared settings
	// object, so the two surfaces cannot drift apart. See ViewActions.qml.
	ViewActions {
		id: viewActions
		directory: viewMenu.directory
		window: viewMenu.window ? viewMenu.window : viewMenu.Window.window
	}

	readonly property var config: viewActions.config
	// The General/Here tab switches the shared write scope.
	property alias isLocal: viewActions.isLocal
	readonly property bool hasFreePlacementPositions: viewActions.hasFreePlacementPositions
	// Native platform menus are separate windows the compositor places on its
	// own; on multi-output targets they can land on the wrong output and crash
	// when reopened, so in-window popups are the default.
	readonly property int menuPopupType: (viewMenu.config && viewMenu.config.native_menus) ? Popup.Native : Popup.Item
	visible: false
	height: contentHeight

	title: qsTr("&View")
	popupType: viewMenu.menuPopupType

	// All writes are delegated to the shared object; the scope follows the
	// General/Here tab. Kept as methods so the menu body reads unchanged.
	//
	// Picking a menu item is a "decide" in the 3DS vocabulary, so every one of
	// these setters plays it — except the ones the sliders and switches call,
	// which have their own feedback and use the *Silent variants.
	//
	// The sound is gated on the menu being on screen: the same Action objects
	// are triggered programmatically (a shortcut, the gamepad), and those must
	// not sound like a menu choice.
	function decideSound() {
		if (viewMenu.visible)
			viewActions.playSound("menu-item");
	}

	function setSectionConfig(section, key, value) {
		viewActions.setSectionConfig(section, key, value);
		viewMenu.decideSound();
	}

	function setConfig(key, value) {
		viewActions.setConfig(key, value);
		viewMenu.decideSound();
	}

	function setNavigationConfig(key, value) {
		viewActions.setNavigationConfig(key, value);
		viewMenu.decideSound();
	}

	// Set a value without the menu-decide sound, for controls that give their
	// own feedback (sliders, switches).
	function setConfigSilent(key, value) {
		viewActions.setConfig(key, value);
	}

	function setViewMode(value) {
		viewActions.setViewModeSilent(value);
		viewMenu.decideSound();
	}

	function setSort(value) {
		viewActions.setSortSilent(value);
		viewMenu.decideSound();
	}

	function resetFreePlacement() {
		viewActions.resetFreePlacement();
	}

	function pathFromUrl(url) {
		return viewActions.pathFromUrl(url);
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
		id: labelTextGroup
	}
	ButtonGroup {
		id: horizontalAlignGroup
	}
	ButtonGroup {
		id: verticalAlignGroup
	}

	// One row in the List Columns menu: the column's name toggles it, and the
	// two arrow buttons move it one place left or right. Uses a custom content
	// item rather than MenuItem.checkable so the reorder buttons can live on
	// the same row as the toggle.
	component ListColumnItem: MenuItem {
		id: listColumnItem
		property string columnKey
		readonly property bool shown: viewActions.hasListColumn(listColumnItem.columnKey)

		onTriggered: viewActions.setListColumnVisible(listColumnItem.columnKey, !listColumnItem.shown)

		contentItem: RowLayout {
			spacing: Kirigami.Units.smallSpacing

			Label {
				Layout.preferredWidth: Kirigami.Units.gridUnit
				horizontalAlignment: Text.AlignHCenter
				text: listColumnItem.shown ? "\u2713" : ""
				color: Kirigami.Theme.highlightColor
				font.bold: true
			}
			Label {
				Layout.fillWidth: true
				text: listColumnItem.text
			}
			ToolButton {
				icon.name: "go-up"
				display: AbstractButton.IconOnly
				enabled: viewActions.canMoveListColumn(listColumnItem.columnKey, -1)
				ToolTip.text: qsTr("Move left")
				ToolTip.visible: hovered
				onClicked: viewActions.moveListColumn(listColumnItem.columnKey, -1)
			}
			ToolButton {
				icon.name: "go-down"
				display: AbstractButton.IconOnly
				enabled: viewActions.canMoveListColumn(listColumnItem.columnKey, 1)
				ToolTip.text: qsTr("Move right")
				ToolTip.visible: hovered
				onClicked: viewActions.moveListColumn(listColumnItem.columnKey, 1)
			}
		}
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
			onClicked: {
				viewMenu.isLocal = false;
				viewActions.playSound("button-pressed");
			}
		}
		TabButton {
			text: qsTr("Here")
			onClicked: {
				viewMenu.isLocal = true;
				viewActions.playSound("button-pressed");
			}
		}
	}

	MenuSeparator {}

	MenuItem {
		contentItem: RowLayout {
			Label {
				text: qsTr("Icon Size")
			}
			ViewSlider {
				id: gridSizeSlider
				boundValue: viewMenu.config ? viewMenu.config.grid_size : 64
				from: 16
				to: 256
				stepSize: 12
				onMovedTo: value => viewMenu.setConfigSilent("GridSize", value.toString())
				onDragStarted: viewActions.playSound("button-pressed")
				onStepped: viewActions.playSound("slider-tick")
				onReachedEdge: viewActions.playSound("scroll-edge")
			}
		}
	}

	readonly property bool showShortcuts: (viewMenu.config) ? viewMenu.config.show_shortcuts : false

	Action {
		id: increaseSizeAction
		text: qsTr("Zoom In")
		shortcut: viewMenu.showShortcuts ? "Ctrl+=" : ""
		onTriggered: viewMenu.setConfig("GridSize", String(Math.min(gridSizeSlider.value + 12, gridSizeSlider.to)))
	}

	Action {
		id: decreaseSizeAction
		text: qsTr("Zoom Out")
		shortcut: viewMenu.showShortcuts ? "Ctrl+-" : ""
		onTriggered: viewMenu.setConfig("GridSize", String(Math.max(gridSizeSlider.value - 12, gridSizeSlider.from)))
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
				onPressed: viewActions.playSound("button-pressed")
				onReleased: viewActions.playSound("button-released")
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
				onPressed: viewActions.playSound("button-pressed")
				onReleased: viewActions.playSound("button-released")
				onClicked: viewMenu.setViewMode("LIST")
			}
		}
	}

	Menu {
		title: qsTr("List Columns")
		icon.name: "view-list-details"
		popupType: viewMenu.menuPopupType
		onOpened: viewActions.playSound("menu-open")
		onClosed: viewActions.playSound("menu-close")

		ListColumnItem {
			columnKey: "SIZE"
			text: viewActions.listColumnLabel("SIZE")
		}
		ListColumnItem {
			columnKey: "MODIFIED"
			text: viewActions.listColumnLabel("MODIFIED")
		}
		ListColumnItem {
			columnKey: "CREATED"
			text: viewActions.listColumnLabel("CREATED")
		}
		ListColumnItem {
			columnKey: "ACCESSED"
			text: viewActions.listColumnLabel("ACCESSED")
		}
		ListColumnItem {
			columnKey: "TYPE"
			text: viewActions.listColumnLabel("TYPE")
		}
	}

	MenuSeparator {}

	Menu {
		title: qsTr("Sort By...")
		icon.name: "view-sort"
		popupType: viewMenu.menuPopupType
		onOpened: viewActions.playSound("menu-open")
		onClosed: viewActions.playSound("menu-close")
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
			popupType: viewMenu.menuPopupType
			onOpened: viewActions.playSound("menu-open")
			onClosed: viewActions.playSound("menu-close")
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
			popupType: viewMenu.menuPopupType
			onOpened: viewActions.playSound("menu-open")
			onClosed: viewActions.playSound("menu-close")
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
		title: qsTr("Labels")
		icon.name: "label"
		popupType: viewMenu.menuPopupType
		onOpened: viewActions.playSound("menu-open")
		onClosed: viewActions.playSound("menu-close")
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
		MenuSeparator {}
		MenuItem {
			text: qsTr("Show Titles")
			checkable: true
			ButtonGroup.group: labelTextGroup
			checked: viewMenu.config ? viewMenu.config.label_text === 0 : true
			enabled: viewMenu.config ? viewMenu.config.show_labels : true
			objectName: "TITLE"
			onTriggered: viewMenu.setConfig("LabelText", "TITLE")
		}
		MenuItem {
			text: qsTr("Show File Names")
			checkable: true
			ButtonGroup.group: labelTextGroup
			checked: viewMenu.config ? viewMenu.config.label_text === 1 : false
			enabled: viewMenu.config ? viewMenu.config.show_labels : true
			objectName: "FILENAME"
			onTriggered: viewMenu.setConfig("LabelText", "FILENAME")
		}
	}

	Menu {
		title: qsTr("Arrange")
		icon.name: "format-justify-fill"
		popupType: viewMenu.menuPopupType
		onOpened: viewActions.playSound("menu-open")
		onClosed: viewActions.playSound("menu-close")

		MenuItem {
			contentItem: RowLayout {
				Label {
					text: qsTr("Lines")
				}
				ViewSlider {
					id: linesSlider
					boundValue: viewMenu.config ? viewMenu.config.grid_lines : 0
					from: 0
					to: 10
					stepSize: 1
					onMovedTo: value => viewMenu.setConfig("Lines", value.toString())
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

		Menu {
			title: qsTr("Scroll Direction")
			popupType: viewMenu.menuPopupType
			onOpened: viewActions.playSound("menu-open")
			onClosed: viewActions.playSound("menu-close")
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
			popupType: viewMenu.menuPopupType
			onOpened: viewActions.playSound("menu-open")
			onClosed: viewActions.playSound("menu-close")
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
			popupType: viewMenu.menuPopupType
			onOpened: viewActions.playSound("menu-open")
			onClosed: viewActions.playSound("menu-close")
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
		popupType: viewMenu.menuPopupType
		onOpened: viewActions.playSound("menu-open")
		onClosed: viewActions.playSound("menu-close")
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
		MenuItem {
			text: qsTr("Open on Click")
			checkable: true
			checked: viewMenu.config ? viewMenu.config.open_on_click : true
			onToggled: viewMenu.setNavigationConfig("OpenOnClick", String(checked))
		}
		MenuItem {
			text: qsTr("Focus Empty Slots")
			checkable: true
			// Empty cells only exist in free placement.
			enabled: viewActions.freePlacement
			checked: viewMenu.config ? viewMenu.config.focus_empty_slots : false
			onToggled: viewMenu.setNavigationConfig("FocusEmptySlots", String(checked))
		}
	}

	Menu {
		title: qsTr("Wallpaper")
		icon.name: "games-config-background-symbolic"
		popupType: viewMenu.menuPopupType
		onOpened: viewActions.playSound("menu-open")
		onClosed: viewActions.playSound("menu-close")
		MenuItem {
			text: qsTr("Set Wallpaper...")
			icon.name: "document-open"
			onTriggered: wallpaperDialog.open()
		}
		MenuItem {
			text: qsTr("Clear Wallpaper")
			icon.name: "edit-clear"
			enabled: viewMenu.config ? String(viewMenu.config.wallpaper).trim() !== "" : false
			onTriggered: viewMenu.setConfig("Wallpaper", "")
		}
	}

	MenuSeparator {}

	Menu {
		title: qsTr("Stash")
		icon.name: "folder-stash-symbolic"
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
