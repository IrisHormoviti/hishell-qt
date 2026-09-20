pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

MenuBar {
	id: rootMenuBar

	readonly property ActionManager actionManager: window ? window.actionManager : null
	
	property ShellWindow window
	property Directory directory
	property Config config: directory ? directory.config : null
	property bool isLocal: directory ? directory.has_meta : false
	property bool hasOpenMenu: false

	Layout.alignment: Qt.AlignRight
	spacing: Kirigami.Units.mediumSpacing

	delegate: MenuBarItem {
		id: menuBarItem
		hoverEnabled: true
		visible: !menuBarItem.menu || menuBarItem.menu.objectName === "" || !rootMenuBar.actionManager || rootMenuBar.actionManager.isMenuGroupVisible(menuBarItem.menu.objectName)
		implicitWidth: visible ? implicitContentWidth + leftPadding + rightPadding : 0
		implicitHeight: visible ? implicitContentHeight + topPadding + bottomPadding : 0
		onHoveredChanged: {
			if (hovered && rootMenuBar.hasOpenMenu && menuBarItem.menu && !menuBarItem.menu.opened) {
				rootMenuBar.closeAllMenus();
				menuBarItem.menu.popup(menuBarItem, 0, menuBarItem.height);
			}
		}
	}

	Instantiator {
		model: rootMenuBar.actionManager ? rootMenuBar.actionManager.menuGroups.filter(groupData => !groupData.customMenu) : []
		delegate: ActionGroupMenu {
			required property var modelData
			actionManager: rootMenuBar.actionManager
			group: modelData
			popupType: Popup.Item
			onOpened: rootMenuBar.hasOpenMenu = true
			onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()
		}
		onObjectAdded: (index, object) => rootMenuBar.insertMenu(Math.min(index, rootMenuBar.count), object)
		onObjectRemoved: (index, object) => rootMenuBar.removeMenu(object)
	}

	ViewMenu {
		id: viewMenu
		directory: rootMenuBar.directory
		isLocal: rootMenuBar.isLocal
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()
	}

	function isAnyMenuOpen() {
		for (let i = 0; i < rootMenuBar.count; i++) {
			const menu = rootMenuBar.menuAt(i);
			if (menu && menu.opened)
				return true;
		}
		return false;
	}

	function closeAllMenus() {
		for (let i = 0; i < rootMenuBar.count; i++) {
			const menu = rootMenuBar.menuAt(i);
			if (menu && menu.opened)
				menu.close();
		}
	}
}
