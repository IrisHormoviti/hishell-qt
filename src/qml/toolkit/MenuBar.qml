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
	property bool hasOpenMenu: false

	Layout.alignment: Qt.AlignRight
	spacing: Kirigami.Units.mediumSpacing

	delegate: MenuBarItem {
		id: menuBarItem
		hoverEnabled: true
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
		id: openAction
		text: "Open"
		icon.name: "document-open"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+O" : ""
		enabled: rootMenuBar.directory && rootMenuBar.directory.selectedCount > 0
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("open")
	}

	Action {
		id: openWithAction
		text: "Open With…"
		icon.name: "document-open-recent"
		shortcut: rootMenuBar.showShortcuts ? "Ctrl+Alt+O" : ""
		enabled: rootMenuBar.directory && rootMenuBar.directory.selectedCount > 0
		onTriggered: if (rootMenuBar.directory) rootMenuBar.directory.invoke("open-with")
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
		enabled: rootMenuBar.directory && rootMenuBar.directory.selectedCount > 0
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

		ShellMenuItem { action: openAction }
		ShellMenuItem { action: openWithAction }
	}

	Menu {
		title: "&Edit"
		icon.name: "edit"
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()

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

	ViewMenu {
		id: viewMenu
		directory: rootMenuBar.directory
		window: rootMenuBar.window
		onOpened: rootMenuBar.hasOpenMenu = true
		onClosed: rootMenuBar.hasOpenMenu = rootMenuBar.isAnyMenuOpen()
	}
}
