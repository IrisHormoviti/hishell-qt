pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

MenuBar {
	id: rootMenuBar

	property ShellWindow window
	property var directory
	property var config: directory ? directory.config : null
	property bool isLocal: directory ? directory.has_meta : false
	readonly property ActionManager actionManager: window ? window.actionManager : null
	onActionManagerChanged: Qt.callLater(rootMenuBar.updateDynamicMenus)

	spacing: Kirigami.Units.mediumSpacing

	property bool hasOpenMenu: false

	delegate: MenuBarItem {
		id: mbi
		hoverEnabled: true
		visible: {
			if (!mbi.menu || !rootMenuBar)
				return true;
			if (mbi.menu === rootMenuBar.openMenu || mbi.menu === rootMenuBar.editMenu)
				return rootMenuBar.actionManager ? rootMenuBar.actionManager.hasSelection : false;
			if (mbi.menu === rootMenuBar.imageMenu)
				return rootMenuBar.actionManager ? rootMenuBar.actionManager.isImageSelected : false;
			return true;
		}
		onHoveredChanged: {
			if (hovered && rootMenuBar.hasOpenMenu && mbi.menu && !mbi.menu.opened) {
				rootMenuBar.closeAllMenus();
				mbi.menu.popup(mbi, 0, mbi.height);
			}
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

		onClicked: button => {
			if (rootMenuBar.directory)
				rootMenuBar.directory.set_config("VIEW", "ViewMode", button.objectName, rootMenuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortGroup

		onClicked: button => {
			if (rootMenuBar.directory)
				rootMenuBar.directory.set_config("VIEW", "Sort", button.objectName, rootMenuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortDateMode

		onClicked: button => {
			if (rootMenuBar.directory)
				rootMenuBar.directory.set_config("VIEW", "SortDateMode", button.objectName, rootMenuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortAlphaMode

		onClicked: button => {
			if (rootMenuBar.directory)
				rootMenuBar.directory.set_config("VIEW", "SortAlphaMode", button.objectName, rootMenuBar.isLocal);
		}
	}

	Connections {
		target: rootMenuBar.actionManager

		function onHasSelectionChanged() {
			rootMenuBar.updateDynamicMenus();
		}

		function onIsImageSelectedChanged() {
			rootMenuBar.updateDynamicMenus();
		}
	}

	Component.onCompleted: {
		Qt.callLater(rootMenuBar.updateDynamicMenus);
	}

	function isAnyMenuOpen() {
		for (let i = 0; i < rootMenuBar.count; i++) {
			const m = rootMenuBar.menuAt(i);
			if (m && m.opened)
				return true;
		}
		return false;
	}

	function closeAllMenus() {
		for (let i = 0; i < rootMenuBar.count; i++) {
			const m = rootMenuBar.menuAt(i);
			if (m && m.opened)
				m.close();
		}
	}

	function updateDynamicMenus() {
		if (!rootMenuBar.actionManager)
			return;

		const showSelection = rootMenuBar.actionManager.hasSelection;
		const showImage = rootMenuBar.actionManager.isImageSelected;

		let openIdx = -1;
		let editIdx = -1;
		let imageIdx = -1;
		let viewIdx = -1;

		for (let i = 0; i < rootMenuBar.count; i++) {
			let m = rootMenuBar.menuAt(i);
			if (m === openMenu)
				openIdx = i;
			else if (m === editMenu)
				editIdx = i;
			else if (m === imageMenu)
				imageIdx = i;
			else if (m === viewMenu)
				viewIdx = i;
		}

		if (showSelection) {
			if (openIdx === -1) {
				let target = (viewIdx !== -1) ? viewIdx : rootMenuBar.count;
				rootMenuBar.insertMenu(target, openMenu);
			}
			for (let i = 0; i < rootMenuBar.count; i++) {
				if (rootMenuBar.menuAt(i) === viewMenu)
					viewIdx = i;
				if (rootMenuBar.menuAt(i) === editMenu)
					editIdx = i;
			}
			if (editIdx === -1) {
				let target = (viewIdx !== -1) ? viewIdx : rootMenuBar.count;
				rootMenuBar.insertMenu(target, editMenu);
			}
		} else {
			if (openIdx !== -1)
				rootMenuBar.removeMenu(openMenu);
			if (editIdx !== -1)
				rootMenuBar.removeMenu(editMenu);
		}

		for (let i = 0; i < rootMenuBar.count; i++) {
			if (rootMenuBar.menuAt(i) === viewMenu)
				viewIdx = i;
			if (rootMenuBar.menuAt(i) === imageMenu)
				imageIdx = i;
		}

		if (showImage) {
			if (imageIdx === -1) {
				let target = (viewIdx !== -1) ? viewIdx : rootMenuBar.count;
				rootMenuBar.insertMenu(target, imageMenu);
			}
		} else {
			if (imageIdx !== -1)
				rootMenuBar.removeMenu(imageMenu);
		}
	}

	Menu {
		id: newMenu

		title: qsTr("New")
		popupType: Popup.Window
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		MenuItem {
			text: qsTr("Folder")
			icon.name: "folder-add"
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.newFolderAction : null
		}

		MenuItem {
			text: qsTr("Text File")
			icon.name: "text-plain"
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.newTextFileAction : null
		}
	}

	property Menu openMenu: Menu {
		id: openMenu

		title: qsTr("Open")
		popupType: Popup.Window
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.openAction : null
		}

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.openWithAction : null
			visible: rootMenuBar.actionManager ? (!rootMenuBar.actionManager.isFirstSelectedDir && rootMenuBar.actionManager.isSingleSelection) : false
		}
	}

	property Menu editMenu: Menu {
		id: editMenu

		title: qsTr("Edit")
		popupType: Popup.Window
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.copyAction : null
		}

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.cutAction : null
		}

		MenuSeparator {}

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.duplicateAction : null
		}

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.linkAction : null
		}

		MenuSeparator {}

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.renameAction : null
		}

		MenuSeparator {}

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.trashAction : null
		}
	}

	property Menu imageMenu: Menu {
		id: imageMenu

		title: qsTr("Image")
		popupType: Popup.Window
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.rotateClockwiseAction : null
		}

		MenuItem {
			action: rootMenuBar.actionManager ? rootMenuBar.actionManager.rotateCounterClockwiseAction : null
		}
	}

	Menu {
		id: viewMenu
		title: qsTr("View")
		popupType: Popup.Window
		spacing: Kirigami.Units.mediumSpacing
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: {
			rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen();
			if (rootMenuBar.directory)
				rootMenuBar.directory.reload();
		}

		TabBar {
			id: viewTabBar

			Layout.fillWidth: true
			currentIndex: rootMenuBar.isLocal ? 1 : 0

			TabButton {
				text: qsTr("General")
				onClicked: rootMenuBar.isLocal = false
			}

			TabButton {
				text: qsTr("Here")
				onClicked: rootMenuBar.isLocal = true
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

					value: rootMenuBar.config ? rootMenuBar.config.grid_size : 64
					from: 16
					to: 256
					stepSize: 4
					onMoved: {
						if (rootMenuBar.directory) {
							rootMenuBar.directory.set_config("VIEW", "GridSize", value.toString(), rootMenuBar.isLocal);
							rootMenuBar.directory.reload();
						}
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
				Label {
					text: qsTr("View Mode")
				}

				ToolButton {
					icon.name: "view-grid"
					checkable: true
					checked: rootMenuBar.config ? rootMenuBar.config.view_mode === 0 : false
					display: AbstractButton.IconOnly
					ToolTip.text: qsTr("Grid View")
					ToolTip.visible: hovered
					ButtonGroup.group: viewModeGroup
					objectName: "GRID"
				}

				ToolButton {
					icon.name: "view-list-details"
					checkable: true
					checked: rootMenuBar.config ? rootMenuBar.config.view_mode === 1 : false
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
				checked: rootMenuBar.config ? rootMenuBar.config.sort === 0 : false
				objectName: "NEWEST"
			}

			MenuItem {
				text: qsTr("Oldest")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: rootMenuBar.config ? rootMenuBar.config.sort === 1 : false
				objectName: "OLDEST"
			}

			Menu {
				title: qsTr("Which date...")
				popupType: Popup.Window

				MenuItem {
					text: qsTr("Modified")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: rootMenuBar.config ? rootMenuBar.config.sort_date_mode === 0 : false
					objectName: "MODIFIED"
				}

				MenuItem {
					text: qsTr("Created")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: rootMenuBar.config ? rootMenuBar.config.sort_date_mode === 1 : false
					objectName: "CREATED"
				}

				MenuItem {
					text: qsTr("Accessed")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: rootMenuBar.config ? rootMenuBar.config.sort_date_mode === 2 : false
					objectName: "ACCESSED"
				}
			}

			MenuSeparator {}

			MenuItem {
				text: qsTr("Alphabetical")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: rootMenuBar.config ? rootMenuBar.config.sort === 2 : false
				objectName: "ALPHABETICAL"
			}

			Menu {
				title: qsTr("Which name...")
				popupType: Popup.Window

				MenuItem {
					text: qsTr("Title")
					checkable: true
					ButtonGroup.group: sortAlphaMode
					checked: rootMenuBar.config ? rootMenuBar.config.sort_alpha_mode === 0 : false
					objectName: "TITLES"
				}

				MenuItem {
					text: qsTr("File Name")
					checkable: true
					ButtonGroup.group: sortAlphaMode
					checked: rootMenuBar.config ? rootMenuBar.config.sort_alpha_mode === 1 : false
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
				checked: rootMenuBar.config ? rootMenuBar.config.stash_shown : false
				onToggled: {
					if (rootMenuBar.config && rootMenuBar.directory)
						rootMenuBar.config.set(rootMenuBar.directory.path, "VIEW", "StashShown", String(checked), rootMenuBar.isLocal);
				}
			}

			MenuItem {
				text: qsTr("Stash Dotfiles")
				checkable: true
				checked: rootMenuBar.config ? rootMenuBar.config.stash_dotfiles : false
				onToggled: {
					if (rootMenuBar.config && rootMenuBar.directory)
						rootMenuBar.config.set(rootMenuBar.directory.path, "VIEW", "StashDotFiles", String(checked), rootMenuBar.isLocal);
				}
			}
		}
	}
}
