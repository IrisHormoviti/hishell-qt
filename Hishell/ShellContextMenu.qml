pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Hishell
import Hishell.toolkit

Menu {
	id: contextMenu

	// Take the keyboard while open so the controller and the arrow keys drive
	// the menu instead of the view behind it.
	focus: true

	required property ActionManager actionManager
	property bool targetIsDir: false
	property bool targetIsImage: false
	property bool targetIsBackground: false
	// Folder the view settings apply to; defaults to the window's current folder.
	property var directory: contextMenu.actionManager ? contextMenu.actionManager.directory : null

	// Event sounds (ClamOS XDG sound theme).
	function playSound(name) {
		const w = contextMenu.actionManager ? contextMenu.actionManager.window : null;
		if (w && w.sound)
			w.sound.play(name);
	}
	onOpened: playSound("menu-open")
	onClosed: playSound("menu-close")

	Repeater {
		model: contextMenu.targetIsBackground ? contextMenu.actionManager.actionsFor("directory") : []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
			// Only when the menu is on screen; see ActionGroupMenu.qml.
			onTriggered: {
				if (contextMenu.visible)
					contextMenu.playSound("menu-item");
			}
		}
	}

	Instantiator {
		// group() returns null when the group is absent; filter it out so the
		// delegate never receives an undefined modelData.
		model: {
			if (!contextMenu.targetIsBackground || !contextMenu.actionManager)
				return [];
			const newGroup = contextMenu.actionManager.group("new");
			return newGroup ? [newGroup] : [];
		}
		delegate: ActionGroupMenu {
			required property var modelData
			actionManager: contextMenu.actionManager
			group: modelData
		}
		onObjectAdded: (index, object) => contextMenu.addMenu(object)
		onObjectRemoved: (index, object) => contextMenu.removeMenu(object)
	}

	Instantiator {
		model: contextMenu.targetIsBackground && contextMenu.directory ? [contextMenu.directory] : []
		delegate: ViewMenu {
			required property Directory modelData
			directory: modelData
			window: contextMenu.actionManager ? contextMenu.actionManager.window : null
		}
		onObjectAdded: (index, object) => contextMenu.addMenu(object)
		onObjectRemoved: (index, object) => contextMenu.removeMenu(object)
	}

	Repeater {
		model: contextMenu.targetIsBackground ? [] : contextMenu.actionManager.actionsFor("items")
		delegate: MenuItem {
			required property Action modelData
			action: modelData
			onTriggered: {
				if (contextMenu.visible)
					contextMenu.playSound("menu-item");
			}
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
			onTriggered: {
				if (contextMenu.visible)
					contextMenu.playSound("menu-item");
			}
		}
	}

	Repeater {
		model: contextMenu.targetIsImage ? contextMenu.actionManager.actionsFor("files") : []
		delegate: MenuItem {
			required property Action modelData
			action: modelData
			onTriggered: {
				if (contextMenu.visible)
					contextMenu.playSound("menu-item");
			}
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
