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

	Repeater {
		model: groupMenu.actionManager ? groupMenu.actionManager.groupActions(groupMenu.group.id) : []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}
}
