pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

MenuBar {
	id: menuBar

	property var directory
	property var config: directory.config
	property bool isLocal: directory.has_meta
	property var fileManager

	// Shared selection state injected by LayoutEngine
	property var selectionState: null

	readonly property int selectedCount: menuBar.selectionState ? menuBar.selectionState.selectedCount : 0
	readonly property var selectedPaths: menuBar.selectionState ? menuBar.selectionState.selectedPaths : ({})

	// Collect the list of selected path strings
	readonly property var selectedPathList: {
		var sel = menuBar.selectedPaths;
		if (!sel) return [];
		return Object.keys(sel);
	}

	// ── Helper: run an operation on all selected paths ────────────────────

	function forEachSelected(fn) {
		var paths = menuBar.selectedPathList;
		var ok = true;
		for (var i = 0; i < paths.length; i++) {
			if (!fn(paths[i])) ok = false;
		}
		return ok;
	}

	// ── Actions ───────────────────────────────────────────────────────────

	Action {
		id: newFolderAction
		text: qsTr("New Folder")
		shortcut: "Ctrl+Shift+N"
		onTriggered: {
			if (menuBar.fileManager && menuBar.directory) {
				if (menuBar.fileManager.new_folder(menuBar.directory.path)) {
					menuBar.directory.refresh();
				}
			}
		}
	}

	Action {
		id: newTextFileAction
		text: qsTr("New Text File")
		shortcut: "Alt+Shift+N"
		onTriggered: {
			if (menuBar.fileManager && menuBar.directory) {
				if (menuBar.fileManager.new_text_file(menuBar.directory.path)) {
					menuBar.directory.refresh();
				}
			}
		}
	}

	Action {
		id: copyAction
		text: qsTr("Copy")
		shortcut: "Ctrl+C"
		enabled: menuBar.selectedCount > 0
		onTriggered: {
			if (!menuBar.fileManager) return;
			var paths = menuBar.selectedPathList.join("\n");
			menuBar.fileManager.copy_paths_to_clipboard(paths);
		}
	}

	Action {
		id: cutAction
		text: qsTr("Cut")
		shortcut: Qt.CTRL | Qt.Key_X
		enabled: menuBar.selectedCount > 0
		onTriggered: {
			if (!menuBar.fileManager) return;
			var paths = menuBar.selectedPathList.join("\n");
			menuBar.fileManager.cut_paths_to_clipboard(paths);
		}
	}

	Action {
		id: duplicateAction
		text: qsTr("Duplicate")
		shortcut: "Ctrl+D"
		enabled: menuBar.selectedCount > 0
		onTriggered: {
			if (!menuBar.fileManager) return;
			menuBar.forEachSelected(function(p) {
				return menuBar.fileManager.duplicate_file(p);
			});
			menuBar.directory.refresh();
		}
	}

	Action {
		id: linkAction
		text: qsTr("Create Link")
		shortcut: "Ctrl+Shift+L"
		enabled: menuBar.selectedCount > 0
		onTriggered: {
			if (!menuBar.fileManager) return;
			menuBar.forEachSelected(function(p) {
				// Create link next to source with " (link)" suffix
				var name = p.substring(p.lastIndexOf("/") + 1);
				var parent = p.substring(0, p.lastIndexOf("/"));
				var dest = parent + "/" + name + " (link)";
				return menuBar.fileManager.create_link(p, dest);
			});
			menuBar.directory.refresh();
		}
	}

	Action {
		id: renameAction
		text: qsTr("Rename")
		shortcut: "F2"
		// Rename only when exactly one item is selected
		enabled: menuBar.selectedCount === 1
		onTriggered: {
			if (menuBar.selectedCount !== 1) return;
			renameDialog.filePath = menuBar.selectedPathList[0];
			var name = renameDialog.filePath.substring(renameDialog.filePath.lastIndexOf("/") + 1);
			renameDialog.originalName = name;
			renameDialog.newName = name;
			renameDialog.open();
		}
	}

	Action {
		id: trashAction
		text: qsTr("Move to Trash")
		shortcut: "Delete"
		enabled: menuBar.selectedCount > 0
		onTriggered: {
			if (!menuBar.fileManager) return;
			menuBar.forEachSelected(function(p) {
				return menuBar.fileManager.trash_file(p);
			});
			// Clear selection and refresh
			if (menuBar.selectionState) {
				menuBar.selectionState.selectionActive = false;
				menuBar.selectionState.selectedPaths = ({});
				menuBar.selectionState.selectedCount = 0;
			}
			menuBar.directory.refresh();
		}
	}

	Action {
		id: pasteAction
		text: qsTr("Paste")
		shortcut: "Ctrl+V"
		// Paste is always active — works without selection mode
		enabled: true
		onTriggered: {
			if (menuBar.fileManager && menuBar.directory) {
				if (menuBar.fileManager.paste_from_clipboard(menuBar.directory.path)) {
					menuBar.directory.refresh();
				}
			}
		}
	}

	Action {
		id: increaseSizeAction
		text: qsTr("Increase Size")
		shortcut: "Ctrl+="
		onTriggered: {
			gridSizeSlider.value = Math.min(gridSizeSlider.value + 4, gridSizeSlider.to)
		}
	}

	Action {
		id: decreaseSizeAction
		text: qsTr("Decrease Size")
		shortcut: "Ctrl+-"
		onTriggered: {
			gridSizeSlider.value = Math.max(gridSizeSlider.value - 4, 0)
		}
	}

	ButtonGroup {
		id: viewModeGroup
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "ViewMode", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortGroup
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "Sort", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortDateMode
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "SortDateMode", button.objectName, menuBar.isLocal);
		}
	}

	ButtonGroup {
		id: sortAlphaMode
		onClicked: button => {
			menuBar.directory.set_config("VIEW", "SortAlphaMode", button.objectName, menuBar.isLocal);
		}
	}

	// ── Rename dialog ─────────────────────────────────────────────────────

	Dialog {
		id: renameDialog
		title: qsTr("Rename")
		standardButtons: Dialog.Ok | Dialog.Cancel
		modal: true
		anchors.centerIn: parent

		property string filePath: ""
		property string originalName: ""
		property string newName: ""

		onAccepted: {
			var trimmed = renameDialog.newName.trim();
			if (trimmed.length > 0 && trimmed !== renameDialog.originalName) {
				if (menuBar.fileManager) {
					menuBar.fileManager.rename_file(renameDialog.filePath, trimmed);
					menuBar.directory.refresh();
				}
			}
		}

		ColumnLayout {
			spacing: Kirigami.Units.smallSpacing
			width: 320

			Label {
				text: qsTr("New name:")
			}

			TextField {
				id: renameField
				Layout.fillWidth: true
				text: renameDialog.newName
				onTextChanged: renameDialog.newName = text
				Keys.onReturnPressed: renameDialog.accept()
				Keys.onEnterPressed:  renameDialog.accept()
				Keys.onEscapePressed: renameDialog.reject()

				Component.onCompleted: {
					// Select the filename stem, not the extension
					var dot = text.lastIndexOf(".");
					if (dot > 0) {
						Qt.callLater(function() { renameField.select(0, dot); });
					} else {
						Qt.callLater(function() { renameField.selectAll(); });
					}
				}
			}
		}

		onOpened: {
			renameField.text = renameDialog.originalName;
			renameField.forceActiveFocus();
		}
	}

	// ── Menu declarations ─────────────────────────────────────────────────

	Menu {
		title: qsTr("New")
		popupType: Popup.Window

		MenuItem {
			text: qsTr("Folder")
			icon.name: "folder-add"
			action: newFolderAction
		}
		MenuItem {
			text: qsTr("Text File")
			icon.name: "text-plain"
			action: newTextFileAction
		}
	}

	// Edit menu: always visible since Paste works without selection.
	// Other actions are individually enabled/disabled based on selection count.
	Menu {
		id: editMenu
		title: qsTr("Edit")
		popupType: Popup.Window

		MenuItem {
			text: qsTr("Paste")
			icon.name: "edit-paste"
			action: pasteAction
		}
		MenuSeparator {}
		MenuItem {
			text: qsTr("Copy")
			icon.name: "edit-copy"
			action: copyAction
		}
		MenuItem {
			text: qsTr("Cut")
			icon.name: "edit-cut"
			action: cutAction
		}
		MenuSeparator {}
		MenuItem {
			text: qsTr("Duplicate")
			icon.name: "edit-copy"
			action: duplicateAction
		}
		MenuItem {
			text: qsTr("Create Link")
			icon.name: "edit-link"
			action: linkAction
		}
		MenuSeparator {}
		// Rename: only enabled for single selection
		MenuItem {
			text: qsTr("Rename")
			icon.name: "edit-rename"
			action: renameAction
		}
		MenuSeparator {}
		MenuItem {
			text: qsTr("Move to Trash")
			icon.name: "user-trash"
			action: trashAction
		}
	}

	Menu {
		title: qsTr("View")
		popupType: Popup.Window

		onClosed: {
			menuBar.directory.refresh();
		}

		TabBar {
			id: viewTabBar
			Layout.fillWidth: true
			currentIndex: menuBar.isLocal ? 1 : 0

			TabButton {
				text: qsTr("General")
				onClicked: menuBar.isLocal = false
			}
			TabButton {
				text: qsTr("Here")
				onClicked: menuBar.isLocal = true
			}
		}

		MenuSeparator {}

		MenuItem {
			contentItem: RowLayout {
				Label {
					text: "Icon Size"
				}

				Slider {
					id: gridSizeSlider
					value: menuBar.config.grid_size
					from: 0
					to: 128
					stepSize: 4
					onMoved: {
						menuBar.directory.set_config("VIEW", "GridSize", value.toString(), menuBar.isLocal);
						menuBar.directory.refresh()
					}
				}

				TextMetrics {
					id: charMetrics
					text: "000"
				}

				Label {
					text: gridSizeSlider.value
					Layout.preferredWidth: charMetrics.width
					horizontalAlignment: Text.AlignHCenter
				}
			}
		}

		MenuSeparator {}

		MenuItem {
			contentItem: RowLayout {
				spacing: 4

				Label {
					text: qsTr("View Mode")
				}

				ToolButton {
					icon.name: "view-grid"
					checkable: true
					checked: menuBar.config.view_mode === 0
					display: AbstractButton.IconOnly
					ToolTip.text: qsTr("Grid View")
					ToolTip.visible: hovered
					ButtonGroup.group: viewModeGroup
					objectName: "GRID"
				}

				ToolButton {
					icon.name: "view-list-details"
					checkable: true
					checked: menuBar.config.view_mode === 1
					display: AbstractButton.IconOnly
					ToolTip.text: qsTr("List View")
					ButtonGroup.group: viewModeGroup
					ToolTip.visible: hovered
					objectName: "LIST"
				}
			}
		}

		MenuSeparator {}

		Menu {
			title: qsTr("Sort By...")
			icon.name: "view-sort"
			popupType: Popup.Window

			MenuItem {
				text: qsTr("Newest")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: menuBar.config.sort === 0
				objectName: "NEWEST"
			}
			MenuItem {
				text: qsTr("Oldest")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: menuBar.config.sort === 1
				objectName: "OLDEST"
			}
			Menu {
				title: qsTr("Which date...")
				popupType: Popup.Window

				MenuItem {
					text: qsTr("Modified")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: menuBar.config.sort_date_mode === 0
					objectName: "MODIFIED"
				}
				MenuItem {
					text: qsTr("Created")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: menuBar.config.sort_date_mode === 1
					objectName: "CREATED"
				}
				MenuItem {
					text: qsTr("Accessed")
					checkable: true
					ButtonGroup.group: sortDateMode
					checked: menuBar.config.sort_date_mode === 2
					objectName: "ACCESSED"
				}
			}

			MenuSeparator { }

			MenuItem {
				text: qsTr("Alphabetical")
				checkable: true
				ButtonGroup.group: sortGroup
				checked: menuBar.config.sort === 2
				objectName: "ALPHABETICAL"
			}

			Menu {
				title: qsTr("Which name...")
				popupType: Popup.Window

				MenuItem {
					text: qsTr("Title")
					checkable: true
					ButtonGroup.group: sortAlphaMode
					checked: menuBar.config.sort_alpha_mode === 0
					objectName: "TITLES"
				}
				MenuItem {
					text: qsTr("File Name")
					checkable: true
					ButtonGroup.group: sortAlphaMode
					checked: menuBar.config.sort_alpha_mode === 1
					objectName: "FILENAMES"
				}
			}
		}

		MenuSeparator {}

		Menu {
			title: qsTr("Stash")
			icon.name: "pane-hide"
			popupType: Popup.Window

			MenuItem {
				text: qsTr("Show Stash")
				checkable: true
				checked: menuBar.config.stash_shown
				onToggled: {
					menuBar.config.set(menuBar.directory.path, "VIEW", "StashShown", String(checked), menuBar.isLocal);
				}
			}
			MenuItem {
				text: qsTr("Stash Dotfiles")
				checkable: true
				checked: menuBar.config.stash_dotfiles
				onToggled: {
					menuBar.config.set(menuBar.directory.path, "VIEW", "StashDotFiles", String(checked), menuBar.isLocal);
				}
			}
		}
	}
}
