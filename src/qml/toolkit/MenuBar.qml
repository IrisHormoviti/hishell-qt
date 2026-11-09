import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MenuBar {
	id: rootMenuBar

	property var window
	readonly property var directory: rootMenuBar.window
		? rootMenuBar.window.currentDirectory : null
	readonly property var config: rootMenuBar.directory ? rootMenuBar.directory.config : null
	readonly property bool showShortcuts: rootMenuBar.config
		? rootMenuBar.config.show_shortcuts : true
	readonly property bool hasTarget: rootMenuBar.directory
		? (rootMenuBar.directory.selectedCount > 0
			|| rootMenuBar.directory.focused_path.length > 0) : false
	readonly property bool imageTarget: rootMenuBar.directory
		? rootMenuBar.directory.focusIsImage : false
	readonly property bool folderTarget: rootMenuBar.directory
		? rootMenuBar.directory.focusIsDirectory : false
	readonly property var openActions: rootMenuBar.menuActions(["open", "open-with", "navigate"])
	readonly property var imageActions: rootMenuBar.menuActions(["rotate-image"])
	readonly property var folderActions: rootMenuBar.menuActions(["navigate", "open"])
	property bool hasOpenMenu: false

	function menuActions(ids) {
		if (!rootMenuBar.directory)
			return []
		// Establish dependencies on the same state actions_json reads.
		rootMenuBar.directory.selectionRevision
		rootMenuBar.directory.revision
		rootMenuBar.directory.focused_path
		let actions = []
		try {
			actions = JSON.parse(rootMenuBar.directory.actions_json("context", "auto"))
		} catch (error) {
			actions = []
		}
		return actions.filter(action => ids.indexOf(action.id) !== -1)
	}

	Layout.alignment: Qt.AlignRight
	spacing: Kirigami.Units.mediumSpacing

	delegate: MenuBarItem {
		id: menuBarItem
		hoverEnabled: true
		visible: !menuBarItem.menu || menuBarItem.menu.groupVisible !== false
		implicitWidth: visible ? implicitContentWidth + leftPadding + rightPadding : 0
		implicitHeight: visible ? implicitContentHeight + topPadding + bottomPadding : 0
		onHoveredChanged: {
			if (hovered && rootMenuBar.hasOpenMenu && menuBarItem.menu && !menuBarItem.menu.opened) {
				rootMenuBar.closeAllMenus()
				menuBarItem.menu.popup(menuBarItem, 0, menuBarItem.height)
			}
		}
	}

	function isAnyMenuOpen() {
		for (let i = 0; i < rootMenuBar.count; i++) {
			const menu = rootMenuBar.menuAt(i)
			if (menu && menu.opened)
				return true
		}
		return false
	}

	function closeAllMenus() {
		for (let i = 0; i < rootMenuBar.count; i++) {
			const menu = rootMenuBar.menuAt(i)
			if (menu && menu.opened)
				menu.close()
		}
	}

	Action {
		id: copyAction
		text: "Copy"
		icon.name: "edit-copy"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+C" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.copy_selection()
	}

	Action {
		id: cutAction
		text: "Cut"
		icon.name: "edit-cut"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+X" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.cut_selection()
	}

	Action {
		id: pasteAction
		text: "Paste"
		icon.name: "edit-paste"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+V" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.paste()
	}

	Action {
		id: duplicateAction
		text: "Duplicate"
		icon.name: "edit-duplicate"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+D" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("duplicate")
	}

	Action {
		id: linkAction
		text: "Create Link"
		icon.name: "edit-link"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+Shift+L" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("create-link")
	}

	Action {
		id: renameAction
		text: "Rename…"
		icon.name: "edit-rename"
		shortcut: rootMenuBar.showShortcuts ? "F2" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("rename")
	}

	Action {
		id: trashAction
		text: "Move to Trash…"
		icon.name: "user-trash"
		shortcut: rootMenuBar.showShortcuts ? "Delete" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("trash")
	}


	Action {
		id: selectAllAction
		text: "Select All"
		icon.name: "edit-select-all"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+A" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.select_all()
	}

	Action {
		id: closeAction
		text: "Close"
		icon.name: "window-close"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+W" : ""
		onTriggered: if (rootMenuBar.window) rootMenuBar.window.close()
	}

	Action {
		id: newFolderAction
		text: "New Folder"
		icon.name: "folder-new"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+Shift+N" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("new-folder")
	}

	Action {
		id: newTextAction
		text: "New Text File"
		icon.name: "document-new"
		shortcut: rootMenuBar.showShortcuts ? "Alt+Shift+N" : ""
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("new-text-file")
	}

	Menu {
		title: "&Open"
		icon.name: "document-open"
		property bool groupVisible: rootMenuBar.hasTarget
			&& rootMenuBar.openActions.length > 0
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		Repeater {
			model: rootMenuBar.openActions

			ShellMenuItem {
				required property var modelData
				text: rootMenuBar.window.actionLabel(modelData.id)
				iconName: modelData.icon || ""
				shortcutText: rootMenuBar.showShortcuts ? (modelData.shortcut || "") : ""
				enabled: modelData.enabled
				onTriggered: rootMenuBar.directory.invoke(modelData.id)
			}
		}
	}

	Menu {
		title: "&Image"
		icon.name: "image-x-generic"
		property bool groupVisible: rootMenuBar.imageTarget
			&& rootMenuBar.imageActions.length > 0
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		Repeater {
			model: rootMenuBar.imageActions

			ShellMenuItem {
				required property var modelData
				text: rootMenuBar.window.actionLabel(modelData.id)
				iconName: modelData.icon || ""
				enabled: modelData.enabled
				onTriggered: rootMenuBar.directory.invoke(modelData.id)
			}
		}
	}

	Menu {
		title: "&Edit"
		icon.name: "edit"
		property bool groupVisible: rootMenuBar.hasTarget
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		ShellMenuItem { action: copyAction }
		ShellMenuItem { action: cutAction }
		ShellMenuItem { action: pasteAction }
		MenuSeparator {}
		ShellMenuItem { action: duplicateAction }
		ShellMenuItem { action: linkAction }
		MenuSeparator {}
		ShellMenuItem { action: renameAction }
		ShellMenuItem { action: trashAction }
		MenuSeparator {}
		ShellMenuItem { action: selectAllAction }
		MenuSeparator {}
		ShellMenuItem { action: closeAction }
	}

	Menu {
		title: "&New"
		icon.name: "document-new"
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		ShellMenuItem { action: newFolderAction }
		ShellMenuItem { action: newTextAction }
	}

	Menu {
		title: "&Folder"
		icon.name: "folder"
		property bool groupVisible: rootMenuBar.folderTarget
			&& rootMenuBar.folderActions.length > 0
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		Repeater {
			model: rootMenuBar.folderActions

			ShellMenuItem {
				required property var modelData
				text: rootMenuBar.window.actionLabel(modelData.id)
				iconName: modelData.icon || ""
				shortcutText: rootMenuBar.showShortcuts ? (modelData.shortcut || "") : ""
				enabled: modelData.enabled
				onTriggered: rootMenuBar.directory.invoke(modelData.id)
			}
		}
	}

	ViewMenu {
		id: viewMenu
		directory: rootMenuBar.directory
		window: rootMenuBar.window
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()
	}
}
