import QtQuick
import QtQuick.Controls
import Hishell

Menu {
	id: contextMenu

	required property ActionManager actionManager
	property bool targetIsDir: false
	property bool targetIsImage: false
	property bool targetIsBackground: false

	// popupType: Popup.Window

	Repeater {
		model: contextMenu.targetIsBackground ? contextMenu.actionManager.backgroundActionsGroup : contextMenu.actionManager.openGroup
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}

	MenuSeparator {
		visible: !contextMenu.targetIsBackground && (contextMenu.targetIsDir || contextMenu.targetIsImage)
		height: visible ? implicitHeight : 0
	}

	Repeater {
		model: contextMenu.targetIsDir ? contextMenu.actionManager.folderActionsGroup : (contextMenu.targetIsImage ? contextMenu.actionManager.imageGroup : [])
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}

	MenuSeparator {}

	Repeater {
		model: contextMenu.targetIsBackground ? [] : contextMenu.actionManager.editGroup
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}
}
