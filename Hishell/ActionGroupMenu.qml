pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Hishell

Menu {
	id: groupMenu

	required property ActionManager actionManager
	required property var group
	readonly property bool groupVisible: actionManager.isMenuGroupVisible(group.id)
	readonly property bool submenu: group.submenu === true

	readonly property var config: actionManager && actionManager.directory ? actionManager.directory.config : null
	// See ViewMenu.qml: native popups are separate windows and are opt-in.
	popupType: (groupMenu.config && groupMenu.config.native_menus) ? Popup.Native : Popup.Item

	objectName: group.id
	title: group.title

	// Event sounds: opening a menu, and picking an item from it.
	function playSound(name) {
		const w = groupMenu.actionManager ? groupMenu.actionManager.window : null;
		if (w && w.sound)
			w.sound.play(name);
	}
	onOpened: playSound("menu-open")
	onClosed: playSound("menu-close")

	Repeater {
		model: groupMenu.actionManager ? groupMenu.actionManager.groupActions(groupMenu.group.id) : []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
			// Only a sound when the menu is actually on screen: the same Action
			// is triggered programmatically (the gamepad's B runs Go Up), and a
			// shared Action fires every item bound to it, which made B sound
			// like a menu choice.
			onTriggered: {
				if (groupMenu.visible)
					groupMenu.playSound("menu-item");
			}
		}
	}
}
