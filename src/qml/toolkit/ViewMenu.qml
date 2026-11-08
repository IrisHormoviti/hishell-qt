import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Menu {
	id: viewMenu

	required property var directory
	property var window

	ViewActions {
		id: viewActions
		directory: viewMenu.directory
		window: viewMenu.window
	}

	readonly property var config: viewActions.config
	property alias isLocal: viewActions.isLocal
	readonly property int menuPopupType: (viewMenu.config && viewMenu.config.native_menus)
		? Popup.Native : Popup.Item
	readonly property bool showShortcuts: viewMenu.config
		? viewMenu.config.show_shortcuts : true

	title: "&View"
	popupType: viewMenu.menuPopupType
	onOpened: viewActions.isLocal = viewMenu.directory ? viewMenu.directory.has_meta() : false

	function decideSound() {}

	function setConfig(key, value) {
		viewActions.setConfig(key, value)
		viewMenu.decideSound()
	}

	function setNavigationConfig(key, value) {
		viewActions.setNavigationConfig(key, value)
		viewMenu.decideSound()
	}

	function setConfigSilent(key, value) {
		viewActions.setConfig(key, value)
	}

	function setViewMode(value) {
		viewActions.setViewMode(value)
		viewMenu.decideSound()
	}

	function setSort(value) {
		viewActions.setSort(value)
		viewMenu.decideSound()
	}

	function setGroup(value) {
		viewActions.setGroup(value)
		viewMenu.decideSound()
	}

	function setListHeaderVisible(visible) {
		viewActions.setListHeaderVisible(visible)
		viewMenu.decideSound()
	}

	function resetFreePlacement() {
		viewActions.resetFreePlacement()
	}

	function pathFromUrl(url) {
		return viewActions.pathFromUrl(url)
	}

	component ListColumnItem: MenuItem {
		id: listColumnItem
		property string columnKey
		readonly property bool shown: viewActions.hasListColumn(listColumnItem.columnKey)

		onTriggered: viewActions.setListColumnVisible(listColumnItem.columnKey,
			!listColumnItem.shown)

		contentItem: RowLayout {
			spacing: Kirigami.Units.smallSpacing

			Label {
				Layout.preferredWidth: Kirigami.Units.gridUnit
				horizontalAlignment: Text.AlignHCenter
				text: listColumnItem.shown ? "✓" : ""
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
				ToolTip.text: "Move left"
				ToolTip.visible: hovered
				onClicked: viewActions.moveListColumn(listColumnItem.columnKey, -1)
			}
			ToolButton {
				icon.name: "go-down"
				display: AbstractButton.IconOnly
				enabled: viewActions.canMoveListColumn(listColumnItem.columnKey, 1)
				ToolTip.text: "Move right"
				ToolTip.visible: hovered
				onClicked: viewActions.moveListColumn(listColumnItem.columnKey, 1)
			}
		}
	}

	FileDialog {
		id: wallpaperDialog
		title: "Choose Wallpaper"
		nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.gif *.svg)",
			"All files (*)"]
		onAccepted: viewMenu.setConfig("Wallpaper", viewMenu.pathFromUrl(wallpaperDialog.selectedFile))
	}

	TabBar {
		id: scopeTabs
		width: 220
		currentIndex: viewMenu.isLocal ? 1 : 0
		TabButton {
			text: "General"
			onClicked: viewMenu.isLocal = false
		}
		TabButton {
			text: "Here"
			onClicked: viewMenu.isLocal = true
		}
	}

	ShellMenuItem {
		text: viewActions.isIconSize ? "Size by Lines" : "Size by Icon Size"
		iconName: viewActions.isIconSize ? "view-grid" : "zoom-fit-best"
		onTriggered: viewActions.setGridMode(viewActions.isIconSize ? "LINES" : "SIZE")
	}

	Menu {
		title: viewActions.isIconSize ? "Icon Size" : viewActions.lineCountLabel
		icon.name: viewActions.isIconSize ? "zoom-fit-best" : "view-grid"

		Repeater {
			model: viewActions.isIconSize
				? [16, 24, 32, 48, 64, 72, 96, 128, 192, 256]
				: [1, 2, 3, 4, 5, 6, 7, 8]

			ShellMenuItem {
				required property int modelData
				text: String(modelData)
				marked: viewActions.isIconSize
					? viewActions.iconSize === modelData
					: viewActions.lineCount === modelData
				onTriggered: {
					if (viewActions.isIconSize)
						viewActions.setIconSize(modelData)
					else
						viewActions.setLineCount(modelData)
				}
			}
		}
	}

	Shortcut {
		sequence: viewMenu.showShortcuts ? "Ctrl+=" : ""
		onActivated: viewActions.nudgeZoom(-1)
	}

	Shortcut {
		sequence: viewMenu.showShortcuts ? "Ctrl+-" : ""
		onActivated: viewActions.nudgeZoom(1)
	}

	ShellMenuItem {
		text: "Zoom In"
		iconName: "zoom-in"
		shortcutText: viewMenu.showShortcuts ? "Ctrl+=" : ""
		enabled: !viewActions.isListView
		onTriggered: viewActions.nudgeZoom(-1)
	}

	ShellMenuItem {
		text: "Zoom Out"
		iconName: "zoom-out"
		shortcutText: viewMenu.showShortcuts ? "Ctrl+-" : ""
		enabled: !viewActions.isListView
		onTriggered: viewActions.nudgeZoom(1)
	}

	MenuSeparator {}

	ShellMenuItem {
		text: "Grid View"
		iconName: "view-grid"
		marked: !viewActions.isListView
		onTriggered: viewMenu.setViewMode("GRID")
	}
	ShellMenuItem {
		text: "List View"
		iconName: "view-list-details"
		marked: viewActions.isListView
		onTriggered: viewMenu.setViewMode("LIST")
	}

	Menu {
		id: listColumnsMenu
		title: "List Columns"
		icon.name: "view-list-details"
		popupType: viewMenu.menuPopupType
		enabled: viewActions.isListView

		ShellMenuItem {
			text: "Show Header"
			iconName: "view-list-header"
			marked: viewActions.showListHeader
			onTriggered: viewMenu.setListHeaderVisible(!viewActions.showListHeader)
		}
		MenuSeparator {}

		Repeater {
			model: viewActions.listColumnMenuOrder

			delegate: ListColumnItem {
				required property string modelData
				columnKey: modelData
				text: viewActions.listColumnLabel(modelData)
			}
		}
	}

	MenuSeparator {}

	Menu {
		id: sortMenu
		title: "Sort By…"
		icon.name: "view-sort"
		popupType: viewMenu.menuPopupType

		ShellMenuItem {
			text: "Newest"
			iconName: "view-sort-descending"
			marked: viewActions.sort === "NEWEST"
			onTriggered: viewMenu.setSort("NEWEST")
		}
		ShellMenuItem {
			text: "Oldest"
			iconName: "view-sort-ascending"
			marked: viewActions.sort === "OLDEST"
			onTriggered: viewMenu.setSort("OLDEST")
		}
		Menu {
			title: "Which date…"
			icon.name: "appointment-new"
			popupType: viewMenu.menuPopupType

			ShellMenuItem {
				text: "Modified"
				marked: viewActions.sortDateMode === "MODIFIED"
				onTriggered: viewMenu.setConfig("SortDateMode", "MODIFIED")
			}
			ShellMenuItem {
				text: "Created"
				marked: viewActions.sortDateMode === "CREATED"
				onTriggered: viewMenu.setConfig("SortDateMode", "CREATED")
			}
			ShellMenuItem {
				text: "Accessed"
				marked: viewActions.sortDateMode === "ACCESSED"
				onTriggered: viewMenu.setConfig("SortDateMode", "ACCESSED")
			}
		}
		MenuSeparator {}
		ShellMenuItem {
			text: "Alphabetical"
			iconName: "insert-text"
			marked: viewActions.sort === "ALPHABETICAL"
			onTriggered: viewMenu.setSort("ALPHABETICAL")
		}
		Menu {
			title: "Which name…"
			icon.name: "insert-text"
			popupType: viewMenu.menuPopupType

			ShellMenuItem {
				text: "Title"
				marked: viewActions.sortAlphaMode === "TITLES"
				onTriggered: viewMenu.setConfig("SortAlphaMode", "TITLES")
			}
			ShellMenuItem {
				text: "File Name"
				marked: viewActions.sortAlphaMode === "FILENAMES"
				onTriggered: viewMenu.setConfig("SortAlphaMode", "FILENAMES")
			}
		}
		MenuSeparator {}
		ShellMenuItem {
			text: "Free Placement"
			iconName: "transform-move"
			visible: !viewActions.isListView
			enabled: viewActions.isLocal && !viewActions.customGroups
			marked: viewActions.sort === "FREE"
			onTriggered: viewMenu.setSort("FREE")
		}
		ShellMenuItem {
			text: "Reset Manual Placement"
			iconName: "edit-reset"
			visible: !viewActions.isListView
			enabled: viewActions.hasFreePlacementPositions
			onTriggered: viewMenu.resetFreePlacement()
		}
	}

	Menu {
		id: groupMenu
		title: "Group By…"
		icon.name: "view-group"
		popupType: viewMenu.menuPopupType
		enabled: !viewActions.freePlacement && !viewActions.customGroups

		ShellMenuItem {
			text: "None"
			marked: viewActions.groupMode === "NONE"
			onTriggered: viewMenu.setGroup("NONE")
		}
		ShellMenuItem {
			text: "Date"
			iconName: "appointment-new"
			marked: viewActions.groupMode === "DATE"
			onTriggered: viewMenu.setGroup("DATE")
		}
		ShellMenuItem {
			text: "Letters"
			iconName: "insert-text"
			marked: viewActions.groupMode === "LETTERS"
			onTriggered: viewMenu.setGroup("LETTERS")
		}
		ShellMenuItem {
			text: "Type"
			iconName: "view-group"
			marked: viewActions.groupMode === "TYPE"
			onTriggered: viewMenu.setGroup("TYPE")
		}
	}

	Menu {
		id: labelsMenu
		title: "Labels"
		icon.name: "label"
		popupType: viewMenu.menuPopupType

		ShellMenuItem {
			text: "Show Labels"
			iconName: "label"
			marked: viewActions.showLabels
			onTriggered: viewMenu.setConfig("ShowLabels", String(!viewActions.showLabels))
		}
		ShellMenuItem {
			text: "Labels Beside Icons"
			iconName: "label"
			marked: viewActions.labelsBesideIcons
			enabled: viewActions.showLabels
			onTriggered: viewMenu.setConfig("GridLabelsBesidesIcons",
				String(!viewActions.labelsBesideIcons))
		}
		MenuSeparator {}
		ShellMenuItem {
			text: "Show Titles"
			marked: viewActions.labelText === "TITLE"
			enabled: viewActions.showLabels
			onTriggered: viewMenu.setConfig("LabelText", "TITLE")
		}
		ShellMenuItem {
			text: "Show File Names"
			marked: viewActions.labelText === "FILENAME"
			enabled: viewActions.showLabels
			onTriggered: viewMenu.setConfig("LabelText", "FILENAME")
		}
	}

	Menu {
		id: arrangeMenu
		title: "Arrange"
		icon.name: "format-justify-fill"
		popupType: viewMenu.menuPopupType

		Menu {
			title: "Scroll Direction"
			icon.name: "go-next"
			popupType: viewMenu.menuPopupType

			ShellMenuItem {
				text: "Vertical"
				marked: !viewActions.scrollHorizontal
				onTriggered: viewMenu.setConfig("ScrollDirection", "VERTICAL")
			}
			ShellMenuItem {
				text: "Horizontal"
				marked: viewActions.scrollHorizontal
				onTriggered: viewMenu.setConfig("ScrollDirection", "HORIZONTAL")
			}
		}
		Menu {
			title: "Horizontal Align"
			icon.name: "format-justify-fill"
			popupType: viewMenu.menuPopupType

			ShellMenuItem {
				text: "Fill"
				marked: viewActions.horizontalAlign === "FILL"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "FILL")
			}
			ShellMenuItem {
				text: "Left"
				marked: viewActions.horizontalAlign === "LEFT"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "LEFT")
			}
			ShellMenuItem {
				text: "Center"
				marked: viewActions.horizontalAlign === "CENTER"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "CENTER")
			}
			ShellMenuItem {
				text: "Right"
				marked: viewActions.horizontalAlign === "RIGHT"
				onTriggered: viewMenu.setConfig("GridHorizontalAlign", "RIGHT")
			}
		}
		Menu {
			title: "Vertical Align"
			icon.name: "format-justify-fill"
			popupType: viewMenu.menuPopupType

			ShellMenuItem {
				text: "Fill"
				marked: viewActions.verticalAlign === "FILL"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "FILL")
			}
			ShellMenuItem {
				text: "Top"
				marked: viewActions.verticalAlign === "TOP"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "TOP")
			}
			ShellMenuItem {
				text: "Center"
				marked: viewActions.verticalAlign === "CENTER"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "CENTER")
			}
			ShellMenuItem {
				text: "Bottom"
				marked: viewActions.verticalAlign === "BOTTOM"
				onTriggered: viewMenu.setConfig("GridVerticalAlign", "BOTTOM")
			}
		}
	}

	Menu {
		title: "Navigation"
		icon.name: "transform-move"
		popupType: viewMenu.menuPopupType

		ShellMenuItem {
			text: "Center Focus"
			iconName: "zoom-fit-best"
			marked: viewActions.centerFocus
			onTriggered: viewMenu.setNavigationConfig("CenterFocus",
				String(!viewActions.centerFocus))
		}
		ShellMenuItem {
			text: "Smooth Scrolling"
			iconName: "transform-move"
			marked: viewActions.smoothScrolling
			onTriggered: viewMenu.setNavigationConfig("SmoothScrolling",
				String(!viewActions.smoothScrolling))
		}
		ShellMenuItem {
			text: "Open on Click"
			iconName: "document-open"
			marked: viewActions.openOnClick
			onTriggered: viewMenu.setNavigationConfig("OpenOnClick",
				String(!viewActions.openOnClick))
		}
		ShellMenuItem {
			text: "Focus Empty Slots"
			iconName: "zoom-fit-best"
			enabled: viewActions.freePlacement
			marked: viewActions.focusEmptySlots
			onTriggered: viewMenu.setNavigationConfig("FocusEmptySlots",
				String(!viewActions.focusEmptySlots))
		}
	}

	Menu {
		title: "Wallpaper"
		icon.name: "games-config-background-symbolic"
		popupType: viewMenu.menuPopupType

		ShellMenuItem {
			text: "Set Wallpaper…"
			iconName: "document-open"
			onTriggered: wallpaperDialog.open()
		}
		ShellMenuItem {
			text: "Clear Wallpaper"
			iconName: "edit-clear"
			enabled: viewActions.wallpaper.trim().length > 0
			onTriggered: viewMenu.setConfig("Wallpaper", "")
		}
	}

	MenuSeparator {}

	Menu {
		title: "Stash"
		icon.name: "folder-stash-symbolic"
		popupType: viewMenu.menuPopupType

		ShellMenuItem {
			text: "Show Stash"
			iconName: "folder-stash-symbolic"
			marked: viewActions.stashShown
			onTriggered: viewMenu.setConfig("ShowStash", String(!viewActions.stashShown))
		}
		ShellMenuItem {
			text: "Stash Dotfiles"
			iconName: "folder-stash-symbolic"
			marked: viewActions.stashDotfiles
			onTriggered: viewMenu.setConfig("StashDotFiles",
				String(!viewActions.stashDotfiles))
		}
	}
}
