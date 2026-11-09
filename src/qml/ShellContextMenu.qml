import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami
import "toolkit"

// The old ShellContextMenu, sourced from the same directory/action queries as
// the original: background menus carry the Here actions, New and View; item
// menus carry the item actions plus the target-specific groups.
Menu {
	id: contextMenu

	// Take the keyboard while open so the controller and the arrow keys drive
	// the menu instead of the view behind it.
	focus: true

	property var directory: null
	property var window: null
	property bool targetIsDir: false
	property bool targetIsImage: false
	property bool targetIsBackground: false

	property var actions: []
	property var newMenu: null
	property var viewMenu: null

	function reload() {
		if (!contextMenu.directory) {
			contextMenu.actions = []
			return
		}
		const target = contextMenu.targetIsBackground ? "location" : "focus"
		let list = []
		try {
			list = JSON.parse(contextMenu.directory.actions_json("context", target))
		} catch (error) {
			list = []
		}
		if (contextMenu.targetIsBackground) {
			list = list.filter(action => action.here
				&& action.id !== "new-folder" && action.id !== "new-text-file")
		} else {
			list = list.filter(action => action.items)
		}
		contextMenu.actions = list
	}

	onAboutToShow: {
		contextMenu.reload()

		if (contextMenu.targetIsBackground) {
			if (!contextMenu.newMenu) {
				contextMenu.newMenu = newMenuComponent.createObject(contextMenu)
				contextMenu.addMenu(contextMenu.newMenu)
			}
			if (!contextMenu.viewMenu) {
				contextMenu.viewMenu = viewMenuComponent.createObject(contextMenu, {
					"directory": contextMenu.directory,
					"window": contextMenu.window
				})
				contextMenu.addMenu(contextMenu.viewMenu)
			}
		} else {
			if (contextMenu.newMenu) {
				contextMenu.removeMenu(contextMenu.newMenu)
				contextMenu.newMenu.destroy()
				contextMenu.newMenu = null
			}
			if (contextMenu.viewMenu) {
				contextMenu.removeMenu(contextMenu.viewMenu)
				contextMenu.viewMenu.destroy()
				contextMenu.viewMenu = null
			}
		}
	}

	Repeater {
		model: contextMenu.actions

		ShellMenuItem {
			required property var modelData
			text: contextMenu.window
				? contextMenu.window.actionLabel(modelData.id) : modelData.id
			iconName: modelData.icon || ""
			shortcutText: modelData.shortcut || ""
			enabled: modelData.enabled
			onTriggered: contextMenu.directory.invoke(modelData.id)
		}
	}

	MenuSeparator {}

	ShellMenuItem {
		text: "Open in New Window"
		iconName: "window-new"
		onTriggered: {
			const path = contextMenu.targetIsBackground
				? contextMenu.directory.path : contextMenu.directory.focused_path
			if (path.length > 0)
				contextMenu.directory.open_in_new_window(path)
		}
	}

	Component {
		id: newMenuComponent

		Menu {
			title: "New"
			icon.name: "document-new"

			ShellMenuItem {
				text: "New Folder"
				iconName: "folder-new"
				onTriggered: if (contextMenu.directory)
					contextMenu.directory.invoke("new-folder")
			}
			ShellMenuItem {
				text: "New Text File"
				iconName: "document-new"
				onTriggered: if (contextMenu.directory)
					contextMenu.directory.invoke("new-text-file")
			}
		}
	}

	Component {
		id: viewMenuComponent

		ViewMenu {}
	}
}
