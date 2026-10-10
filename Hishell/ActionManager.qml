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

	// The item under the pane cursor stands in for a selection while nothing is
	// selected, so the actions work on the focused item too.
	readonly property string focusedPath: {
		const fm = actionManager.window ? actionManager.window.focusManager : null;
		if (!fm || !fm.focus_active)
			return "";
		return String(fm.focused_path);
	}
	readonly property var targetPathList: actionManager.hasSelection ? actionManager.selectedPathList : (actionManager.focusedPath !== "" ? [actionManager.focusedPath] : [])
	readonly property bool hasTarget: actionManager.targetPathList.length > 0
	readonly property bool isSingleTarget: actionManager.targetPathList.length === 1
	readonly property string firstTargetPath: actionManager.targetPathList.length > 0 ? actionManager.targetPathList[0] : ""
	// The directory the target lives in; a layout can show several folders, so the
	// owning view decides where paths open and what gets reloaded afterwards.
	readonly property var targetFolderView: actionManager.hasSelection
		? (actionManager.window ? actionManager.window.selectionFolderView : null)
		: (actionManager.window ? actionManager.window.focusedFolderView : null)
	readonly property Directory targetDirectory: (actionManager.targetFolderView && actionManager.targetFolderView.directory) ? actionManager.targetFolderView.directory : actionManager.directory

	readonly property bool isFirstTargetDir: (isSingleTarget && fileManager) ? fileManager.is_directory(firstTargetPath) : false

	// Default application of the single target file, used by the Open action
	readonly property string openAppPath: (isSingleTarget && !isFirstTargetDir) ? firstTargetPath : ""
	readonly property var openApp: {
		if (openAppPath === "" || !fileManager)
			return null;
		try {
			const info = JSON.parse(fileManager.get_default_app(openAppPath));
			return info && info.id ? info : null;
		} catch (e) {
			return null;
		}
	}
	readonly property string openAppIcon: openApp ? String(openApp.icon) : ""

	readonly property bool isImageTarget: {
		if (!hasTarget || !fileManager)
			return false;
		if (isSingleTarget)
			return fileManager.is_image_file(firstTargetPath);
		for (let i = 0; i < targetPathList.length; i++) {
			if (!fileManager.is_image_file(targetPathList[i]))
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
			title: qsTr("&Open"),
			actions: openGroup,
			contexts: ["items"],
			submenu: false
		},
		{
			id: "edit",
			title: qsTr("&Edit"),
			actions: editGroup,
			contexts: ["items"],
			submenu: false
		},
		{
			id: "image",
			title: qsTr("&Image"),
			actions: imageGroup,
			contexts: ["files"],
			submenu: false
		},
		{
			id: "new",
			title: qsTr("&New"),
			actions: newActionsGroup,
			contexts: ["directory"],
			submenu: true
		},
		{
			id: "directory",
			title: qsTr("&Folder"),
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
			return hasTarget;
		if (groupData.contexts.indexOf("files") !== -1)
			return isImageTarget;
		return true;
	}

	// Open Group
	readonly property var openGroup: executeAction.available
		? [executeAction, openAction, openWithAction, openWindowAction]
		: [openAction, openWithAction, openWindowAction]

	function activatePath(path: string, sourceItem: Item) {
		if (directory && directory.is_execute_target(path))
			executeAction.execute(path, sourceItem);
		else
			openAction.execute(path, sourceItem, false);
	}

	readonly property bool isTargetLink: actionManager.hasTarget
		&& actionManager.isSingleTarget
		&& actionManager.targetDirectory
		&& actionManager.targetDirectory.is_link(actionManager.firstTargetPath)

	property alias executeAction: executeAction
	Action {
		id: executeAction
		text: actionManager.isTargetLink ? qsTr("Open &Link") : qsTr("&Execute")
		icon.name: actionManager.isTargetLink ? "open-link" : "system-run"
		readonly property bool available: actionManager.hasTarget
			&& actionManager.targetPathList.every(path => actionManager.targetDirectory.is_execute_target(path))
		enabled: available

		function execute(targetPath: string, sourceItem: Item) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.targetPathList;
			for (let i = 0; i < paths.length; i++) {
				const path = paths[i];
				if (!actionManager.targetDirectory.is_execute_target(path))
					continue;
				if (sourceItem) {
					const layout = sourceItem.contentLayout;
					const globalPos = layout.mapToItem(actionManager, 0, 0);
					layout.grabToImage(result => {
						externalOpenAnimation.x = globalPos.x;
						externalOpenAnimation.y = globalPos.y;
						externalOpenAnimation.width = layout.width;
						externalOpenAnimation.height = layout.height;
						externalOpenImage.source = result.url;
						externalOpenAnimation.visible = true;
						externalOpenAnimationEffect.restart();
					});
				}
				actionManager.targetDirectory.execute_action(path);
			}
		}

		onTriggered: execute("", null)
	}

	property alias openAction: openAction
	Action {
		id: openAction
		shortcut: "Ctrl+O"
		text: actionManager.openApp ? qsTr("O&pen with %1").arg(actionManager.openApp.name) : qsTr("O&pen")
		icon.name: actionManager.openAppIcon !== "" && actionManager.openAppIcon.indexOf("/") === -1 ? actionManager.openAppIcon : "open-link"
		icon.source: actionManager.openAppIcon.indexOf("/") !== -1 ? actionManager.openAppIcon : ""
		enabled: actionManager.hasTarget

		function execute(targetPath: string, sourceItem: Item, inNewWindow = false) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.targetPathList;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				// Opening a folder in place resets the view's model and destroys the
				// source item, taking any in-flight grab with it while the render
				// thread is still using it. Only grab when the item survives the open.
				const isDir = actionManager.fileManager && actionManager.fileManager.is_directory(p);
				if (sourceItem && !(isDir && !inNewWindow)) {
					const layout = sourceItem.contentLayout;
					const globalPos = layout.mapToItem(actionManager, 0, 0);
					layout.grabToImage(result => {
						externalOpenAnimation.x = globalPos.x;
						externalOpenAnimation.y = globalPos.y;
						externalOpenAnimation.width = layout.width;
						externalOpenAnimation.height = layout.height;
						externalOpenImage.source = result.url;
						externalOpenAnimation.visible = true;
						externalOpenAnimationEffect.restart();
					});
				}

				if (inNewWindow) {
					actionManager.targetDirectory.open_in_new_window(p);
				} else {
					actionManager.targetDirectory.open_path(p);
				}
			}
		}

		onTriggered: {
			if (!actionManager.hasTarget)
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
		enabled: actionManager.isSingleTarget

		function execute(targetPath: string, sourceItem: Item) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.targetPathList;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				actionManager.targetDirectory.open_path(p);
			}
		}

		onTriggered: {
			if (!actionManager.hasTarget)
				return;
			execute("", null, false);
		}
	}

	property alias openWindowAction: openWindowAction
	Action {
		id: openWindowAction
		text: qsTr("Open in Win&dow")
		icon.name: "window-new-symbolic"
		shortcut: "Ctrl+N"
		enabled: actionManager.hasTarget
		onTriggered: {
			if (!actionManager.hasTarget) {
				actionManager.directory.open_in_new_window(actionManager.directory.path);
			} else {
				const paths = actionManager.targetPathList;
				for (let i = 0; i < paths.length; i++) {
					openAction.execute(paths[i], null, true);
				}
			}
		}
	}

	property alias openWithAction: openWithAction
	Action {
		id: openWithAction
		text: qsTr("Open &With...")
		icon.name: "system-run"
		shortcut: "Ctrl+Alt+O"
		enabled: actionManager.isSingleTarget
		onTriggered: {
			if (actionManager.isSingleTarget)
				actionManager.openWith(actionManager.firstTargetPath);
		}
	}

	// Item Edit Group
	readonly property var editGroup: [copyAction, cutAction, duplicateAction, linkAction, renameAction, trashAction]

	Action {
		id: copyAction
		text: qsTr("&Copy")
		icon.name: "edit-copy"
		shortcut: "Ctrl+C"
		enabled: actionManager.hasTarget
		onTriggered: {
			const paths = actionManager.targetPathList.join("\n");
			if (actionManager.fileManager)
				actionManager.fileManager.copy_paths_to_clipboard(paths);
		}
	}

	Action {
		id: cutAction
		text: qsTr("C&ut")
		icon.name: "edit-cut"
		shortcut: "Ctrl+X"
		enabled: actionManager.hasTarget
		onTriggered: {
			const paths = actionManager.targetPathList.join("\n");
			if (actionManager.fileManager)
				actionManager.fileManager.cut_paths_to_clipboard(paths);
		}
	}

	Action {
		id: duplicateAction
		text: qsTr("&Duplicate")
		icon.name: "edit-copy"
		shortcut: "Ctrl+D"
		enabled: actionManager.hasTarget
		onTriggered: {
			const paths = actionManager.targetPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.duplicate_file(paths[i]))
					anyOk = true;
			}
			if (anyOk && actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
		}
	}

	Action {
		id: linkAction
		text: qsTr("Create &Link")
		icon.name: "edit-link"
		shortcut: "Ctrl+Shift+L"
		enabled: actionManager.hasTarget
		onTriggered: {
			const paths = actionManager.targetPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				const name = p.substring(p.lastIndexOf("/") + 1);
				const parent = p.substring(0, p.lastIndexOf("/"));
				const dest = parent + "/" + name + " (link)";
				if (actionManager.fileManager && actionManager.fileManager.create_link(p, dest))
					anyOk = true;
			}
			if (anyOk && actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
		}
	}

	Action {
		id: renameAction
		text: qsTr("&Rename")
		icon.name: "edit-rename"
		shortcut: "F2"
		enabled: actionManager.isSingleTarget
		onTriggered: {
			if (actionManager.isSingleTarget) {
				actionManager.openRenameDialog(actionManager.firstTargetPath);
			}
		}
	}

	Action {
		id: editPermissionsAction
		text: qsTr("Permissions...")
		icon.name: "edit-rename"
		shortcut: "Ctrl+P"
		enabled: actionManager.hasTarget
		onTriggered: {
			// FIXME
		}
	}

	Action {
		id: trashAction
		text: qsTr("&Trash")
		icon.name: "user-trash"
		shortcut: "Delete"
		enabled: actionManager.hasTarget
		onTriggered: {
			const paths = actionManager.targetPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.trash_file(paths[i]))
					anyOk = true;
			}
			if (actionManager.selectionManager)
				actionManager.selectionManager.clear();
			if (anyOk && actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
		}
	}

	// Folder Group
	readonly property var folderActionsGroup: [goUpAction, refreshAction, pasteAction, copyPathAction]
	property alias goUpAction: goUpAction
	property alias refreshAction: refreshAction
	property string pasteTargetPath: ""

	Action {
		id: goUpAction
		text: qsTr("Go &Up")
		icon.name: "arrow-up-symbolic"
		shortcut: "Alt+Up"
		enabled: actionManager.directory && actionManager.directory.path !== "/"
		onTriggered: {
			if (actionManager.directory)
				actionManager.directory.go_up();
		}
	}

	Action {
		id: goBackAction
		text: qsTr("Go &Back")
		icon.name: "arrow-left-symbolic"
		shortcut: "Alt+Left"
		enabled: actionManager.directory
		onTriggered: {
			// FIXME
		}
	}

	Action {
		id: goForwardAction
		text: qsTr("Go &Forward")
		icon.name: "arrow-right-symbolic"
		shortcut: "Alt+Right"
		enabled: actionManager.directory
		onTriggered: {
			// FIXME
		}
	}

	Action {
		id: refreshAction
		text: qsTr("&Refresh")
		icon.name: "view-refresh"
		shortcut: "F5"
		enabled: actionManager.directory !== null
		onTriggered: {
			// Full reload: re-reads the folder contents and its config.
			if (actionManager.directory)
				actionManager.directory.reload();
		}
	}

	Action {
		id: searchAction
		text: qsTr("Search")
		icon.name: "search"
		shortcut: "Ctrl+F"
		enabled: actionManager.directory !== null
		onTriggered: {
			// TODO: Implement
		}
	}

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
			return name.length > 0 ? qsTr("&Paste into %1").arg(name) : qsTr("&Paste");
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
		text: "&Copy Path"
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


	// New Group
	readonly property var newActionsGroup: [newFolderAction, newTextFileAction]

	Action {
		id: newFolderAction
		text: qsTr("New Fo&lder")
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
		text: qsTr("New &Text File")
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
		text: qsTr("Rotate &Clockwise")
		icon.name: "object-rotate-right"
		shortcut: "Ctrl+R"
		enabled: actionManager.isImageTarget
		onTriggered: {
			const paths = actionManager.targetPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.rotate_image(paths[i], 90))
					anyOk = true;
			}
			if (anyOk && actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
		}
	}

	Action {
		id: rotateCounterClockwiseAction
		text: qsTr("Rotate Counter-Clock&wise")
		icon.name: "object-rotate-left"
		shortcut: "Ctrl+Shift+R"
		enabled: actionManager.isImageTarget
		onTriggered: {
			const paths = actionManager.targetPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.rotate_image(paths[i], 270))
					anyOk = true;
			}
			if (anyOk && actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
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
		property string errorText: ""

		function applyRename() {
			var trimmed = renameDialog.newName.trim();
			if (trimmed.length === 0 || trimmed === renameDialog.originalName) {
				renameDialog.accept();
				return;
			}
			var status = {
				ok: true,
				error: ""
			};
			if (actionManager.fileManager)
				status = JSON.parse(actionManager.fileManager.rename_file(renameDialog.filePath, trimmed));
			if (!status.ok) {
				renameDialog.errorText = status.error;
				renameField.forceActiveFocus();
				return;
			}
			renameDialog.accept();
			if (actionManager.selectionManager)
				actionManager.selectionManager.clear();
			if (actionManager.targetDirectory)
				actionManager.targetDirectory.rename_free_position(renameDialog.originalName, trimmed);
		}

		title: qsTr("Rename")
		modal: true
		anchors.centerIn: parent
		onOpened: {
			renameDialog.errorText = "";
			renameField.text = renameDialog.originalName;
			renameField.forceActiveFocus();
		}

		contentItem: ColumnLayout {
			spacing: Kirigami.Units.smallSpacing

			Label {
				text: qsTr("New name:")
			}

			TextField {
				id: renameField
				Layout.fillWidth: true
				Layout.minimumWidth: 320
				text: renameDialog.newName
				onTextChanged: {
					renameDialog.newName = text;
					renameDialog.errorText = "";
				}
				onAccepted: renameDialog.applyRename()
				Keys.onReturnPressed: renameDialog.applyRename()
				Keys.onEnterPressed: renameDialog.applyRename()
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

			Label {
				id: renameError
				visible: renameDialog.errorText.length > 0
				text: renameDialog.errorText
				color: Kirigami.Theme.negativeTextColor
				wrapMode: Text.WordWrap
				Layout.fillWidth: true
			}

			RowLayout {
				Layout.alignment: Qt.AlignRight
				spacing: Kirigami.Units.smallSpacing

				Button {
					text: qsTr("OK")
					highlighted: true
					onClicked: renameDialog.applyRename()
				}

				Button {
					text: qsTr("Cancel")
					onClicked: renameDialog.reject()
				}
			}
		}
	}

	// Open With: prefer the system chooser through the XDG portal, fall back to the built-in dialog
	function openWith(filePath) {
		if (!actionManager.fileManager)
			return;
		if (!actionManager.fileManager.start_portal_open_with(filePath)) {
			actionManager.openOpenWithDialog(filePath);
			return;
		}
		portalOpenWithWatch.filePath = filePath;
		portalOpenWithWatch.running = true;
	}

	Timer {
		id: portalOpenWithWatch
		property string filePath: ""
		interval: 250
		repeat: true
		onTriggered: {
			const status = actionManager.fileManager.poll_portal_open_with();
			if (status === 2) {
				running = false;
				actionManager.openOpenWithDialog(filePath);
			} else if (status === 0) {
				running = false;
			}
		}
	}

	// Open With Dialog
	function openOpenWithDialog(filePath) {
		openWithDialog.filePath = filePath;
		openWithDialog.open();
	}

	OpenWithDialog {
		id: openWithDialog
		fileManager: actionManager.fileManager
	}
}
