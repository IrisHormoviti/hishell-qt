pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Hishell
import Hishell.toolkit

Menu {
	id: contextMenu

	required property ActionManager actionManager
	property bool targetIsDir: false
	property bool targetIsImage: false
	property bool targetIsBackground: false

	Repeater {
		model: contextMenu.targetIsBackground ? contextMenu.actionManager.actionsFor("directory") : []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}

	Instantiator {
		model: contextMenu.targetIsBackground ? [contextMenu.actionManager.group("new")] : []
		delegate: ActionGroupMenu {
			required property var modelData
			actionManager: contextMenu.actionManager
			group: modelData
		}
		onObjectAdded: (index, object) => contextMenu.addMenu(object)
		onObjectRemoved: (index, object) => contextMenu.removeMenu(object)
	}

	Instantiator {
		model: contextMenu.targetIsBackground ? [contextMenu.actionManager.directory] : []
		delegate: ViewMenu {
			required property Directory modelData
			directory: modelData
		}
		onObjectAdded: (index, object) => contextMenu.addMenu(object)
		onObjectRemoved: (index, object) => contextMenu.removeMenu(object)
	}

	Repeater {
		model: contextMenu.targetIsBackground ? [] : contextMenu.actionManager.actionsFor("items")
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
		model: contextMenu.targetIsDir ? contextMenu.actionManager.actionsFor("folders") : []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}

	Repeater {
		model: contextMenu.targetIsImage ? contextMenu.actionManager.actionsFor("files") : []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}

	MenuSeparator {}

	Repeater {
		model: []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
		}
	}
}
