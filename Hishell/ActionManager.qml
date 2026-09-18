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

	// ── Open Group (Fileslots) ──
	property alias openAction: openAction
	property alias openWithAction: openWithAction
	readonly property var openGroup: [openAction, openWithAction]

	Action {
		id: openAction
		text: qsTr("Open")
		icon.name: "document-open"
		shortcut: "Return"
		enabled: actionManager.hasSelection
		onTriggered: {
			if (!actionManager.hasSelection)
				return;
			const paths = actionManager.selectedPathList;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				if (actionManager.fileManager && actionManager.fileManager.is_directory(p)) {
					actionManager.directory.open_path(p);
				} else if (actionManager.fileManager) {
					actionManager.fileManager.open_file(p);
				}
			}
		}
	}

	Action {
		id: openWithAction
		text: qsTr("Open With...")
		icon.name: "system-run"
		shortcut: "Ctrl+Alt+O"
		enabled: actionManager.isSingleSelection && !actionManager.isFirstSelectedDir
		onTriggered: {
			if (actionManager.isSingleSelection && actionManager.fileManager) {
				actionManager.fileManager.open_file_with_dialog(actionManager.firstSelectedPath);
			}
		}
	}

	// ── Item Edit Group (Fileslots) ──
	property alias copyAction: copyAction
	property alias cutAction: cutAction
	property alias duplicateAction: duplicateAction
	property alias linkAction: linkAction
	property alias renameAction: renameAction
	property alias trashAction: trashAction
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
		text: qsTr("Move to Trash")
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

	// ── Folder Edit Group (Folders in General) ──
	property alias pasteAction: pasteAction
	property alias pasteIntoAction: pasteIntoAction
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
		text: qsTr("Paste")
		icon.name: "edit-paste"
		shortcut: "Ctrl+V"
		enabled: true
		onTriggered: {
			actionManager.pasteInto(actionManager.directory ? actionManager.directory.path : "");
		}
	}

	Action {
		id: pasteIntoAction
		text: {
			const name = actionManager.pasteTargetPath.substring(actionManager.pasteTargetPath.lastIndexOf("/") + 1);
			return name.length > 0 ? qsTr("Paste into %1").arg(name) : qsTr("Paste");
		}
		icon.name: "edit-paste"
		enabled: true
		onTriggered: actionManager.pasteInto(actionManager.pasteTargetPath)
	}

	// ── Inside Folder Group (New) ──
	property alias newFolderAction: newFolderAction
	property alias newTextFileAction: newTextFileAction
	readonly property var folderActionsGroup: [pasteIntoAction]
	readonly property var newActionsGroup: [newFolderAction, newTextFileAction]
	readonly property var backgroundActionsGroup: [pasteAction, newFolderAction, newTextFileAction]

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

	// ── MIME Specific Group (Image) ──
	property alias rotateClockwiseAction: rotateClockwiseAction
	property alias rotateCounterClockwiseAction: rotateCounterClockwiseAction
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

	// ── Rename Dialog ──
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
