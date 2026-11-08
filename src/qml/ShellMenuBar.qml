import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MenuBar {
	id: menuBar

	property var window: null
	readonly property var directory: menuBar.window ? menuBar.window.currentDirectory : null

	spacing: Kirigami.Units.smallSpacing
	Layout.preferredWidth: implicitWidth
	delegate: MenuBarItem {
		id: menuBarItem
		hoverEnabled: true
		visible: menuBarItem.menu ? menuBarItem.menu.count > 0 : false
		implicitWidth: visible ? implicitContentWidth + leftPadding + rightPadding : 0
		implicitHeight: visible ? implicitContentHeight + topPadding + bottomPadding : 0
	}



	Action {
		id: newFolderAction
		text: "New Folder"
		shortcut: "Ctrl+Shift+N"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("new-folder")
	}

	Action {
		id: newTextAction
		text: "New Text File"
		shortcut: "Alt+Shift+N"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("new-text-file")
	}

	Action {
		id: duplicateAction
		text: "Duplicate"
		shortcut: "Ctrl+D"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("duplicate")
	}

	Action {
		id: linkAction
		text: "Create Link"
		shortcut: "Ctrl+Shift+L"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("create-link")
	}

	Action {
		id: renameAction
		text: "Rename…"
		shortcut: "F2"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("rename")
	}

	Action {
		id: trashAction
		text: "Move to Trash…"
		shortcut: "Delete"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("trash")
	}

	Action {
		id: destroyAction
		text: "Delete Permanently…"
		shortcut: "Shift+Delete"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("destroy")
	}

	Action {
		id: selectAllAction
		text: "Select All"
		shortcut: "Ctrl+A"
		onTriggered: if (menuBar.directory) menuBar.directory.select_all()
	}

	Action {
		id: rotateAction
		text: "Rotate Clockwise"
		onTriggered: if (menuBar.directory) menuBar.directory.invoke("rotate-image")
	}

	Action {
		id: gridAction
		text: "Grid"
		checkable: true
		checked: menuBar.directory ? menuBar.directory.config.view_mode === "GRID" : true
		onTriggered: if (menuBar.directory) menuBar.directory.set_config("view_mode", "GRID")
	}

	Action {
		id: listAction
		text: "List"
		checkable: true
		checked: menuBar.directory ? menuBar.directory.config.view_mode === "LIST" : false
		onTriggered: if (menuBar.directory) menuBar.directory.set_config("view_mode", "LIST")
	}

	Action {
		id: labelsAction
		text: "Show Labels"
		checkable: true
		checked: menuBar.directory ? menuBar.directory.config.show_labels : true
		onTriggered: if (menuBar.directory)
			menuBar.directory.set_config("show_labels", checked ? "true" : "false")
	}

	Action {
		id: refreshAction
		text: "Refresh"
		shortcut: "F5"
		onTriggered: if (menuBar.directory) menuBar.directory.refresh_async()
	}

	Action {
		id: goUpAction
		text: "Go Up"
		shortcut: "Alt+Up"
		onTriggered: if (menuBar.directory) menuBar.directory.go_up()
	}

	Action {
		id: closeAction
		text: "Close"
		shortcut: "Ctrl+W"
		onTriggered: if (menuBar.window) menuBar.window.close()
	}


	Menu {
		title: "Edit"
		MenuItem { action: duplicateAction }
		MenuItem { action: linkAction }
		MenuSeparator {}
		MenuItem { action: renameAction }
		MenuItem { action: trashAction }
		MenuItem { action: destroyAction }
		MenuSeparator {}
		MenuItem { action: selectAllAction }
		MenuSeparator {}
		MenuItem { action: closeAction }
	}

	Menu {
		title: "New"
		MenuItem { action: newFolderAction }
		MenuItem { action: newTextAction }
	}

	Menu {
		title: "View"
		MenuItem { action: gridAction }
		MenuItem { action: listAction }
		MenuSeparator {}
		Menu {
			title: "Lines"
			Repeater {
				model: [1, 2, 3, 4, 5, 6, 7, 8]
				MenuItem {
					required property int modelData
					text: String(modelData)
					checkable: true
					checked: menuBar.directory
						&& menuBar.directory.config.grid_lines === modelData
					onTriggered: if (menuBar.directory)
						menuBar.directory.set_config("grid_lines", String(modelData))
				}
			}
		}
		MenuItem { action: labelsAction }
		MenuSeparator {}
		MenuItem { action: rotateAction }
		MenuSeparator {}
		MenuItem { action: refreshAction }
		MenuItem { action: goUpAction }
	}
}
