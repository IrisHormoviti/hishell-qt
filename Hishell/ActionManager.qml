import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: actionManager

	required property ShellWindow window
	required property Directory directory
	property SelectionManager selectionManager: window ? window.selectionManager : null
	property FileManager fileManager: window ? window.fileManager : null

	readonly property int selectedCount: selectionManager ? selectionManager.selected_count : 0
	readonly property var selectedPathList: (selectedCount > 0 && selectionManager && selectionManager.selection_status) ? selectionManager.get_selected_path_list() : []
	readonly property string firstSelectedPath: selectedPathList.length > 0 ? selectedPathList[0] : ""
	readonly property bool hasSelection: selectedCount > 0
	readonly property bool isSingleSelection: selectedCount === 1

	readonly property bool isFirstSelectedDir: (isSingleSelection && fileManager) ? fileManager.is_directory(firstSelectedPath) : false

	readonly property bool isImageSelected: {
		if (!hasSelection || !fileManager)
			return false;
		if (isSingleSelection)
			return fileManager.is_image_file(firstSelectedPath);
		for (let i = 0; i < selectedPathList.length; i++) {
			if (!fileManager.is_image_file(selectedPathList[i]))
				return false;
		}
		return true;
	}

	// Open Animation

	Item {
		id: externalOpenAnimation
		z: 100
		visible: false
		transformOrigin: Item.Center

		Image {
			id: externalOpenImage
			anchors.fill: parent
			fillMode: Image.PreserveAspectFit
			smooth: true
		}

		ParallelAnimation {
			id: externalOpenAnimationEffect
			NumberAnimation {
				target: externalOpenAnimation
				property: "scale"
				from: 1.0
				to: 1.5
				duration: 220
				easing.type: Easing.OutCubic
			}
			NumberAnimation {
				target: externalOpenAnimation
				property: "opacity"
				from: 1.0
				to: 0.0
				duration: 220
				easing.type: Easing.InCubic
			}
			onFinished: {
				externalOpenAnimation.visible = false;
				externalOpenAnimation.scale = 1.0;
				externalOpenAnimation.opacity = 1.0;
			}
		}
	}

	// Group Contexts
	readonly property var menuGroups: [
		{
			id: "open",
			title: qsTr("Open"),
			actions: openGroup,
			contexts: ["items"],
			submenu: false
		},
		{
			id: "edit",
			title: qsTr("Edit"),
			actions: editGroup,
			contexts: ["items"],
			submenu: false
		},
		{
			id: "image",
			title: qsTr("Image"),
			actions: imageGroup,
			contexts: ["files"],
			submenu: false
		},
		{
			id: "new",
			title: qsTr("New"),
			actions: newActionsGroup,
			contexts: ["directory"],
			submenu: true
		},
		{
			id: "directory",
			title: qsTr("Folder"),
			actions: folderActionsGroup,
			contexts: ["directory", "folders"],
			submenu: false
		},
		{
			id: "view",
			title: qsTr("View"),
			actions: [],
			contexts: ["directory"],
			submenu: true,
			customMenu: "ViewMenu"
		}
	]

	function group(id) {
		for (let i = 0; i < menuGroups.length; i++) {
			if (menuGroups[i].id === id)
				return menuGroups[i];
		}
		return null;
	}

	function groupsFor(context) {
		return menuGroups.filter(groupData => groupData.contexts.indexOf(context) !== -1);
	}

	function actionsFor(context) {
		let actions = [];
		const groups = groupsFor(context);
		for (let i = 0; i < groups.length; i++) {
			if (groups[i].submenu !== true)
				actions = actions.concat(groups[i].actions);
		}
		return actions;
	}

	function isMenuGroupVisible(groupId) {
		const groupData = actionManager.group(groupId);
		if (!groupData)
			return false;
		if (groupData.contexts.indexOf("items") !== -1)
			return hasSelection;
		if (groupData.contexts.indexOf("files") !== -1)
			return isImageSelected;
		return true;
	}

	// Open Group
	readonly property var openGroup: [openAction, openWithAction, openWindowAction]

	property alias openAction: openAction
	Action {
		id: openAction
		text: qsTr("Open")
		icon.name: "open-link"
		shortcut: "Return"
		enabled: actionManager.hasSelection

		function execute(targetPath: string, sourceItem: Item, inNewWindow = false) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.selectedPathList;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				if (sourceItem) {
					const globalPos = sourceItem.mapToItem(actionManager, 0, 0);
					sourceItem.grabToImage(result => {
						externalOpenAnimation.x = globalPos.x;
						externalOpenAnimation.y = globalPos.y;
						externalOpenAnimation.width = sourceItem.width;
						externalOpenAnimation.height = sourceItem.height;
						externalOpenImage.source = result.url;
						externalOpenAnimation.visible = true;
						externalOpenAnimationEffect.restart();
					});
				}

				if (inNewWindow) {
					actionManager.directory.open_in_new_window(p);
				} else {
					actionManager.directory.open_path(p);
				}
			}
		}

		onTriggered: {
			if (!actionManager.hasSelection)
				return;
			execute("", null, false);
		}
	}

	property alias navigateAction: navigateAction
	Action {
		id: navigateAction
		text: qsTr("Navigate")
		icon.name: "folder-open-symbolic"
		shortcut: "Shift+Return"
		enabled: actionManager.hasSelection && actionManager.selectedCount == 1

		function execute(targetPath: string, sourceItem: Item) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.selectedPathList;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				actionManager.directory.open_path(p);
			}
		}

		onTriggered: {
			if (!actionManager.hasSelection)
				return;
			execute("", null, false);
		}
	}

	property alias openWindowAction: openWindowAction
	Action {
		id: openWindowAction
		text: qsTr("Open in Window")
		icon.name: "window-new-symbolic"
		shortcut: "Ctrl+N"
		enabled: actionManager.hasSelection
		onTriggered: {
			if (!actionManager.hasSelection) {
				actionManager.directory.open_in_new_window(actionManager.directory.path);
			} else {
				const paths = actionManager.selectedPathList;
				for (let i = 0; i < paths.length; i++) {
					openAction.execute(paths[i], null, true);
				}
			}
		}
	}

	property alias openWithAction: openWithAction
	Action {
		id: openWithAction
		text: qsTr("Open With...")
		icon.name: "system-run"
		shortcut: "Ctrl+Alt+O"
		enabled: actionManager.isSingleSelection
		onTriggered: {
			if (actionManager.isSingleSelection && actionManager.fileManager) {
				actionManager.fileManager.open_file_with_dialog(actionManager.firstSelectedPath);
			}
		}
	}

	// Item Edit Group
	readonly property var editGroup: [copyAction, cutAction, duplicateAction, linkAction, renameAction, trashAction]

	Action {
		id: copyAction
		text: qsTr("Copy")
		icon.name: "edit-copy"
		shortcut: "Ctrl+C"
		enabled: actionManager.hasSelection
		onTriggered: {
			const paths = actionManager.selectedPathList.join("\n");
			if (actionManager.fileManager)
				actionManager.fileManager.copy_paths_to_clipboard(paths);
		}
	}

	Action {
		id: cutAction
		text: qsTr("Cut")
		icon.name: "edit-cut"
		shortcut: "Ctrl+X"
		enabled: actionManager.hasSelection
		onTriggered: {
			const paths = actionManager.selectedPathList.join("\n");
			if (actionManager.fileManager)
				actionManager.fileManager.cut_paths_to_clipboard(paths);
		}
	}

	Action {
		id: duplicateAction
		text: qsTr("Duplicate")
		icon.name: "edit-copy"
		shortcut: "Ctrl+D"
		enabled: actionManager.hasSelection
		onTriggered: {
			const paths = actionManager.selectedPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.duplicate_file(paths[i]))
					anyOk = true;
			}
			if (anyOk && actionManager.directory)
				actionManager.directory.reload();
		}
	}

	Action {
		id: linkAction
		text: qsTr("Create Link")
		icon.name: "edit-link"
		shortcut: "Ctrl+Shift+L"
		enabled: actionManager.hasSelection
		onTriggered: {
			const paths = actionManager.selectedPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				const name = p.substring(p.lastIndexOf("/") + 1);
				const parent = p.substring(0, p.lastIndexOf("/"));
				const dest = parent + "/" + name + " (link)";
				if (actionManager.fileManager && actionManager.fileManager.create_link(p, dest))
					anyOk = true;
			}
			if (anyOk && actionManager.directory)
				actionManager.directory.reload();
		}
	}

	Action {
		id: renameAction
		text: qsTr("Rename")
		icon.name: "edit-rename"
		shortcut: "F2"
		enabled: actionManager.isSingleSelection
		onTriggered: {
			if (actionManager.isSingleSelection) {
				actionManager.openRenameDialog(actionManager.firstSelectedPath);
			}
		}
	}

	Action {
		id: trashAction
		text: qsTr("Trash")
		icon.name: "user-trash"
		shortcut: "Delete"
		enabled: actionManager.hasSelection
		onTriggered: {
			const paths = actionManager.selectedPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.trash_file(paths[i]))
					anyOk = true;
			}
			if (actionManager.selectionManager)
				actionManager.selectionManager.clear();
			if (anyOk && actionManager.directory)
				actionManager.directory.reload();
		}
	}

	// Folder Group
	readonly property var folderActionsGroup: [pasteAction, copyPathAction]
	property string pasteTargetPath: ""

	function pasteInto(destPath) {
		const dest = destPath || (actionManager.directory ? actionManager.directory.path : "");
		if (dest && actionManager.fileManager) {
			if (actionManager.fileManager.paste_from_clipboard(dest)) {
				if (actionManager.directory)
					actionManager.directory.reload();
			}
		}
	}

	Action {
		id: pasteAction
		text: {
			const name = actionManager.pasteTargetPath.substring(actionManager.pasteTargetPath.lastIndexOf("/") + 1);
			return name.length > 0 ? qsTr("Paste into %1").arg(name) : qsTr("Paste");
		}
		icon.name: "edit-paste"
		shortcut: "Ctrl+V"
		enabled: true
		onTriggered: {
			actionManager.pasteInto(actionManager.pasteTargetPath);
		}
	}

	Action {
		id: copyPathAction
		text: "Copy Path"
		icon.name: "edit-copy-path-symbolic"
		shortcut: "Ctrl+Alt+C"
		enabled: true
		onTriggered: {
			// FIXME
		}
	}

	// Current Directory Group
	Action {
		id: editPathAction
		text: "Edit Path"
		icon.name: "text-field-framed-symbolic"
		shortcut: "Ctrl+L"
		enabled: !actionManager.hasSelection
		onTriggered: {
			// FIXME
		}
	}

	Action {
		id: searchAction
		text: "Search..."
		icon.name: "file-search-symbolic"
		shortcut: "Ctrl+L"
		enabled: !actionManager.hasSelection
		onTriggered: {
			// FIXME
		}
	}


	// New Group
	readonly property var newActionsGroup: [newFolderAction, newTextFileAction]

	Action {
		id: newFolderAction
		text: qsTr("New Folder")
		icon.name: "folder-add"
		shortcut: "Ctrl+Shift+N"
		onTriggered: {
			if (actionManager.fileManager && actionManager.directory) {
				if (actionManager.fileManager.new_folder(actionManager.directory.path))
					actionManager.directory.reload();
			}
		}
	}

	Action {
		id: newTextFileAction
		text: qsTr("New Text File")
		icon.name: "text-plain"
		shortcut: "Alt+Shift+N"
		onTriggered: {
			if (actionManager.fileManager && actionManager.directory) {
				if (actionManager.fileManager.new_text_file(actionManager.directory.path))
					actionManager.directory.reload();
			}
		}
	}

	// Image Group
	readonly property var imageGroup: [rotateClockwiseAction, rotateCounterClockwiseAction]
	
	Action {
		id: rotateClockwiseAction
		text: qsTr("Rotate Clockwise")
		icon.name: "object-rotate-right"
		shortcut: "Ctrl+R"
		enabled: actionManager.isImageSelected
		onTriggered: {
			const paths = actionManager.selectedPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.rotate_image(paths[i], 90))
					anyOk = true;
			}
			if (anyOk && actionManager.directory)
				actionManager.directory.reload();
		}
	}

	Action {
		id: rotateCounterClockwiseAction
		text: qsTr("Rotate Counter-Clockwise")
		icon.name: "object-rotate-left"
		shortcut: "Ctrl+Shift+R"
		enabled: actionManager.isImageSelected
		onTriggered: {
			const paths = actionManager.selectedPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.rotate_image(paths[i], 270))
					anyOk = true;
			}
			if (anyOk && actionManager.directory)
				actionManager.directory.reload();
		}
	}

	// Rename Dialog
	function openRenameDialog(filePath) {
		renameDialog.filePath = filePath;
		const name = filePath.substring(filePath.lastIndexOf("/") + 1);
		renameDialog.originalName = name;
		renameDialog.newName = name;
		renameDialog.open();
	}

	Dialog {
		id: renameDialog
		property string filePath: ""
		property string originalName: ""
		property string newName: ""

		title: qsTr("Rename")
		standardButtons: Dialog.Ok | Dialog.Cancel
		modal: true
		anchors.centerIn: parent
		onAccepted: {
			var trimmed = renameDialog.newName.trim();
			if (trimmed.length > 0 && trimmed !== renameDialog.originalName) {
				if (actionManager.fileManager)
					actionManager.fileManager.rename_file(renameDialog.filePath, trimmed);
				if (actionManager.selectionManager)
					actionManager.selectionManager.clear();
				if (actionManager.directory)
					actionManager.directory.reload();
			}
		}
		onOpened: {
			renameField.text = renameDialog.originalName;
			renameField.forceActiveFocus();
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
				Keys.onEnterPressed: renameDialog.accept()
				Keys.onEscapePressed: renameDialog.reject()
				Component.onCompleted: {
					var dot = text.lastIndexOf(".");
					if (dot > 0)
						Qt.callLater(function () {
							renameField.select(0, dot);
						});
					else
						Qt.callLater(function () {
							renameField.selectAll();
						});
				}
			}
		}
	}
}