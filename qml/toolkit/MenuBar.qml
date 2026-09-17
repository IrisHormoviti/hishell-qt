import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../"

MenuBar {
	// Actions
	// Rename dialog
	// Menu declarations

	id: menuBar

	property ShellWindow window
	property var directory
	property var config: directory.config
	property bool isLocal: directory.has_meta
	readonly property ActionManager actionManager: window ? window.actionManager : null
	onActionManagerChanged: Qt.callLater(menuBar.updateDynamicMenus)

	delegate: MenuBarItem {
		id: mbi
		visible: {
			if (!mbi.menu)
				return true;
			if (mbi.menu === menuBar.openMenu || mbi.menu === menuBar.editMenu)
				return menuBar.actionManager ? menuBar.actionManager.hasSelection : false;
			if (mbi.menu === menuBar.imageMenu)
				return menuBar.actionManager ? menuBar.actionManager.isImageSelected : false;
			return true;
		}
	}

	Action {
		id: increaseSizeAction

		text: qsTr("Increase Size")
		shortcut: "Ctrl+="
		onTriggered: {
			gridSizeSlider.value = Math.min(gridSizeSlider.value + 4, gridSizeSlider.to);
		}
	}

	Action {
		id: decreaseSizeAction

		text: qsTr("Decrease Size")
		shortcut: "Ctrl+-"
		onTriggered: {
			gridSizeSlider.value = Math.max(gridSizeSlider.value - 4, 0);
		}
	}

	ButtonGroup {
		id: viewModeGroup

		onClicked: (button) => {
			menuBar.directory.set_config("VIEW", "ViewMode", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortGroup

		onClicked: (button) => {
			menuBar.directory.set_config("VIEW", "Sort", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortDateMode

		onClicked: (button) => {
			menuBar.directory.set_config("VIEW", "SortDateMode", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortAlphaMode

		onClicked: (button) => {
			menuBar.directory.set_config("VIEW", "SortAlphaMode", button.objectName, menuBar.isLocal);
		}
	}

	Connections {
		target: menuBar.actionManager

		function onHasSelectionChanged() {
			menuBar.updateDynamicMenus();
		}

		function onIsImageSelectedChanged() {
			menuBar.updateDynamicMenus();
		}
	}

	Component.onCompleted: {
		Qt.callLater(menuBar.updateDynamicMenus);
	}

	function updateDynamicMenus() {
		if (!menuBar.actionManager)
			return;

		const showSelection = menuBar.actionManager.hasSelection;
		const showImage = menuBar.actionManager.isImageSelected;

		let openIdx = -1;
		let editIdx = -1;
		let imageIdx = -1;
		let viewIdx = -1;

		for (let i = 0; i < menuBar.count; i++) {
			let m = menuBar.menuAt(i);
			if (m === openMenu) openIdx = i;
			else if (m === editMenu) editIdx = i;
			else if (m === imageMenu) imageIdx = i;
			else if (m === viewMenu) viewIdx = i;
		}

		if (showSelection) {
			if (openIdx === -1) {
				let target = (viewIdx !== -1) ? viewIdx : menuBar.count;
				menuBar.insertMenu(target, openMenu);
			}
			for (let i = 0; i < menuBar.count; i++) {
				if (menuBar.menuAt(i) === viewMenu) viewIdx = i;
				if (menuBar.menuAt(i) === editMenu) editIdx = i;
			}
			if (editIdx === -1) {
				let target = (viewIdx !== -1) ? viewIdx : menuBar.count;
				menuBar.insertMenu(target, editMenu);
			}
		} else {
			if (openIdx !== -1) menuBar.removeMenu(openMenu);
			if (editIdx !== -1) menuBar.removeMenu(editMenu);
		}

		for (let i = 0; i < menuBar.count; i++) {
			if (menuBar.menuAt(i) === viewMenu) viewIdx = i;
			if (menuBar.menuAt(i) === imageMenu) imageIdx = i;
		}

		if (showImage) {
			if (imageIdx === -1) {
				let target = (viewIdx !== -1) ? viewIdx : menuBar.count;
				menuBar.insertMenu(target, imageMenu);
			}
		} else {
			if (imageIdx !== -1) menuBar.removeMenu(imageMenu);
		}
	}

	Menu {
		id: newMenu

		title: qsTr("New")
		popupType: Popup.Window

		MenuItem {
			text: qsTr("Folder")
			icon.name: "folder-add"
			action: menuBar.actionManager ? menuBar.actionManager.newFolderAction : null
		}

		MenuItem {
			text: qsTr("Text File")
			icon.name: "text-plain"
			action: menuBar.actionManager ? menuBar.actionManager.newTextFileAction : null
		}
	}

	property Menu openMenu: Menu {
		id: openMenu

		title: qsTr("Open")
		popupType: Popup.Window

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.openAction : null
		}

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.openWithAction : null
			visible: menuBar.actionManager ? (!menuBar.actionManager.isFirstSelectedDir && menuBar.actionManager.isSingleSelection) : false
		}
	}

	property Menu editMenu: Menu {
		id: editMenu

		title: qsTr("Edit")
		popupType: Popup.Window

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.copyAction : null
		}

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.cutAction : null
		}

		MenuSeparator {
		}

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.duplicateAction : null
		}

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.linkAction : null
		}

		MenuSeparator {
		}

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.renameAction : null
		}

		MenuSeparator {
		}

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.trashAction : null
		}
	}

	property Menu imageMenu: Menu {
		id: imageMenu

		title: qsTr("Image")
		popupType: Popup.Window

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.rotateClockwiseAction : null
		}

		MenuItem {
			action: menuBar.actionManager ? menuBar.actionManager.rotateCounterClockwiseAction : null
		}
	}

	Menu {
		id: viewMenu
		title: qsTr("View")
		popupType: Popup.Window
		onClosed: {
			menuBar.directory.reload();
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

		MenuSeparator {
		}

		MenuItem {

			contentItem: RowLayout {
				Label {
					text: "Icon Size"
				}

				Slider {
					id: gridSizeSlider

					value: menuBar.config.grid_size
					from: 16
					to: 256
					stepSize: 4
					onMoved: {
						menuBar.directory.set_config("VIEW", "GridSize", value.toString(), menuBar.isLocal);
						menuBar.directory.reload();
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

		MenuSeparator {
		}

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

		MenuSeparator {
		}

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

			MenuSeparator {
			}

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

		MenuSeparator {
		}

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