import QtQuick
import QtQuick.Controls
import Hishell

Menu {
	id: groupMenu

	required property ActionManager actionManager
	required property var group
	readonly property bool groupVisible: actionManager.isMenuGroupVisible(group.id)
	readonly property bool submenu: group.submenu === true

	popupType: Popup.Native

	objectName: group.id
	title: group.title

	Repeater {
		model: groupMenu.group.actions
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}
}
