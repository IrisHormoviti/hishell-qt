import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: actionManager

	// Kept untyped on purpose: a typed ShellWindow property makes ShellWindow.qml
	// and this file mutually dependent, which Qt 6.8 rejects as a cyclic
	// dependency ("Type ShellWindow unavailable") and then never shows a window.
	required property var window
	required property Directory directory
	// Whether menu items show and register their keyboard shortcuts. The RG DS
	// Plus has no keyboard; the controller buttons even surface as key events, so
	// their absence cannot be detected from the input devices.
	readonly property bool showShortcuts: (actionManager.directory && actionManager.directory.config) ? actionManager.directory.config.show_shortcuts : false
	property SelectionManager selectionManager: window ? window.selectionManager : null
	property FileManager fileManager: window ? window.fileManager : null

	// Event sounds (ClamOS XDG sound theme). Played through the window's sound
	// object; a null window (or a missing theme) simply stays silent.
	function playSound(name) {
		if (actionManager.window && actionManager.window.sound)
			actionManager.window.sound.play(name);
	}

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

	// A generated entry (a provider's network or control row) may be destroyed
	// only when the provider says how: Trash then runs the entry's `Destroy=`
	// command instead of moving the file. Cut is offered on the same terms and
	// then means the same thing — pasting a cut generated entry runs its
	// `Destroy=` command (FileManager::cut_into), because moving the file alone
	// would leave the profile behind and the daemon would write it straight
	// back. Both actions are withheld for a generated entry with no `Destroy=`;
	// an ordinary file is always destroyable.
	readonly property bool allTargetsDestroyable: actionManager.hasTarget
		&& actionManager.targetPathList.every(path => actionManager.fileManager !== null && actionManager.fileManager.can_destroy(path))

	// True when every target is a folder. The menubar's Folder menu corresponds
	// to a selected folder, so it is shown only for such a target; the folder
	// view's own menu carries the directory-level actions separately.
	readonly property bool isFolderTarget: actionManager.hasTarget
		&& actionManager.targetPathList.every(path => actionManager.fileManager !== null && actionManager.fileManager.is_directory(path))

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
	//
	// The descriptor array is deliberately kept identity-stable across focus
	// changes: QML models that rebuild when the array identity changes would
	// otherwise destroy and recreate every menu item (and re-resolve every
	// action icon) on each focus move — and, because `openGroup` depends on
	// `executeAction.available`, that happened continuously. Actions are read
	// through `groupActions()` instead of being embedded here.
	readonly property var menuGroups: [
		{
			id: "open",
			title: qsTr("&Open"),
			contexts: ["items"],
			submenu: false
		},
		{
			id: "edit",
			title: qsTr("&Edit"),
			contexts: ["items"],
			submenu: false
		},
		{
			id: "image",
			title: qsTr("&Image"),
			contexts: ["files"],
			submenu: false
		},
		{
			id: "new",
			title: qsTr("&New"),
			contexts: ["directory"],
			submenu: true
		},
		{
			id: "directory",
			title: qsTr("&Folder"),
			contexts: ["folders"],
			submenu: false
		},
		{
			id: "view",
			title: qsTr("View"),
			contexts: ["directory"],
			submenu: true,
			customMenu: "ViewMenu"
		}
	]

	// The actions for a group, resolved on demand so the descriptor array above
	// stays constant even when the available actions change.
	function groupActions(id) {
		switch (id) {
		case "open":
			return actionManager.openGroup;
		case "edit":
			return actionManager.editGroup;
		case "image":
			return actionManager.imageGroup;
		case "new":
			return actionManager.newActionsGroup;
		case "directory":
			return actionManager.folderActionsGroup;
		default:
			return [];
		}
	}


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
				actions = actions.concat(actionManager.groupActions(groups[i].id));
		}
		// The folder view's own menu also carries the actions that operate
		// inside the current directory (refresh, paste, new, open terminal,
		// ...). Those live in the folder-actions group, which is otherwise only
		// reached through a selected folder, so the view menu would miss them.
		if (context === "directory")
			actions = actions.concat(actionManager.folderActionsGroup);
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
		// A folder menu only concerns a selected (or focused) folder.
		if (groupData.contexts.indexOf("folders") !== -1)
			return actionManager.isFolderTarget;
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

	// A launch the execution wrapper held back for confirmation: show the
	// window's touch- and controller-friendly confirm dialog. `warning` is the
	// blocked item's path; `launchItem` is the item being launched.
	function showLaunchConfirm(warning: string, launchItem: string) {
		if (actionManager.window && typeof actionManager.window.requestLaunchConfirm === 'function')
			actionManager.window.requestLaunchConfirm(warning, launchItem);
	}

	function confirmLaunch() {
		if (actionManager.fileManager)
			actionManager.fileManager.confirm_launch();
	}

	function cancelLaunch() {
		if (actionManager.fileManager)
			actionManager.fileManager.cancel_launch();
	}

	// A launch is about to start: let the window drop the previous return frame
	// at once, so it cannot show through the launch wash.
	function prepareLaunch() {
		if (actionManager.window && typeof actionManager.window.clearReturnFrame === 'function')
			actionManager.window.clearReturnFrame();
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
				// A `Type=Button` entry is a control, not an app: its Exec is
				// spawned directly (no wrapper, no guest window), so it gets the
				// button sound and none of the app-launch transition.
				const isButton = actionManager.fileManager && actionManager.fileManager.is_button(path);
				actionManager.playSound(isButton ? "button-pressed" : "app-launch");
				if (!isButton) {
					actionManager.prepareLaunch();
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
				}
				const warning = String(actionManager.targetDirectory.execute_action(path));
				if (warning !== "")
					actionManager.showLaunchConfirm(warning, path);
			}
		}

		onTriggered: execute("", null)
	}

	property alias openAction: openAction
	Action {
		id: openAction
		shortcut: actionManager.showShortcuts ? "Ctrl+O" : ""
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
				// A `Type=Button` entry is a control, not an app: it runs its Exec
				// directly (no wrapper, no guest window), so it gets the button
				// sound and none of the app-launch transition.
				const isButton = actionManager.fileManager && actionManager.fileManager.is_button(p);
				// A folder opens in place (a navigation); a file leaves the app for
				// its handler. The 3DS makes the same distinction, and so does the
				// theme: window-new for going into a folder, the launch sound for
				// handing a file to another program.
				actionManager.playSound(isButton ? "button-pressed" : (isDir ? "window-new" : "app-launch"));
				if (!isDir && !isButton)
					actionManager.prepareLaunch();
				if (sourceItem && !isButton && !(isDir && !inNewWindow)) {
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
					const warning = String(actionManager.targetDirectory.open_path(p));
					if (warning !== "")
						actionManager.showLaunchConfirm(warning, p);
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
		shortcut: actionManager.showShortcuts ? "Shift+Return" : ""
		enabled: actionManager.isSingleTarget

		function execute(targetPath: string, sourceItem: Item) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.targetPathList;
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				const warning = String(actionManager.targetDirectory.open_path(p));
				if (warning !== "")
					actionManager.showLaunchConfirm(warning, p);
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
		shortcut: actionManager.showShortcuts ? "Ctrl+N" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+Alt+O" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+C" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+X" : ""
		enabled: actionManager.allTargetsDestroyable
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
		shortcut: actionManager.showShortcuts ? "Ctrl+D" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+Shift+L" : ""
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
		shortcut: actionManager.showShortcuts ? "F2" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+P" : ""
		enabled: actionManager.hasTarget
		onTriggered: {
			// FIXME
		}
	}

	Action {
		id: trashAction
		text: qsTr("&Trash")
		icon.name: "user-trash"
		shortcut: actionManager.showShortcuts ? "Delete" : ""
		enabled: actionManager.allTargetsDestroyable
		onTriggered: {
			const paths = actionManager.targetPathList;
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.trash_file(paths[i]))
					anyOk = true;
			}
			if (anyOk)
				actionManager.playSound("item-deleted");
			if (actionManager.selectionManager)
				actionManager.selectionManager.clear();
			if (anyOk && actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
		}
	}

	// Folder Group
	readonly property var folderActionsGroup: [editPathAction, goUpAction, refreshAction, pasteAction, copyPathAction]
	property alias goUpAction: goUpAction
	property alias refreshAction: refreshAction
	property alias editPathAction: editPathAction
	property string pasteTargetPath: ""

	Action {
		id: goUpAction
		text: qsTr("Go &Up")
		icon.name: "arrow-up-symbolic"
		shortcut: actionManager.showShortcuts ? "Alt+Up" : ""
		enabled: actionManager.directory && actionManager.directory.path !== "/"
		onTriggered: {
			// The back sound belongs to the back gesture, not to the action:
			// the menu item that triggers this already plays the menu sound,
			// and playing both made one press sound like two.
			if (actionManager.directory)
				actionManager.directory.go_up();
		}
	}

	Action {
		id: goBackAction
		text: qsTr("Go &Back")
		icon.name: "arrow-left-symbolic"
		shortcut: actionManager.showShortcuts ? "Alt+Left" : ""
		enabled: actionManager.directory
		onTriggered: {
			// FIXME
		}
	}

	Action {
		id: goForwardAction
		text: qsTr("Go &Forward")
		icon.name: "arrow-right-symbolic"
		shortcut: actionManager.showShortcuts ? "Alt+Right" : ""
		enabled: actionManager.directory
		onTriggered: {
			// FIXME
		}
	}

	Action {
		id: refreshAction
		text: qsTr("&Refresh")
		icon.name: "view-refresh"
		shortcut: actionManager.showShortcuts ? "F5" : ""
		enabled: actionManager.directory !== null
		onTriggered: {
			// A folder may carry its own `Refresh=` command (a ClamOS
			// extension): it is how the folder asks its provider for fresh
			// contents. Run it, then reload, so the view is never left
			// showing what the provider has already replaced.
			if (actionManager.directory) {
				actionManager.directory.run_refresh_command();
				actionManager.directory.reload();
			}
		}
	}

	Action {
		id: searchAction
		text: qsTr("Search")
		icon.name: "search"
		shortcut: actionManager.showShortcuts ? "Ctrl+F" : ""
		enabled: actionManager.directory !== null
		onTriggered: {
			// TODO: Implement
		}
	}

	Action {
		id: openTerminalAction
		text: qsTr("Open Terminal Here")
		icon.name: "utilities-terminal-symbolic"
		shortcut: actionManager.showShortcuts ? "Ctrl+`" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+V" : ""
		enabled: true
		onTriggered: {
			actionManager.pasteInto(actionManager.pasteTargetPath);
		}
	}

	Action {
		id: copyPathAction
		text: "&Copy Path"
		icon.name: "edit-copy-path-symbolic"
		shortcut: actionManager.showShortcuts ? "Ctrl+Alt+C" : ""
		enabled: true
		onTriggered: {
			// FIXME
		}
	}

	// Current Directory Group
	function editLocation(initialText) {
		const bar = actionManager.window ? actionManager.window.pathBar : null;
		if (bar)
			bar.startEditing(initialText);
	}

	Action {
		id: editPathAction
		text: "Edit Path"
		icon.name: "text-field-framed-symbolic"
		shortcut: actionManager.showShortcuts ? "Ctrl+L" : ""
		onTriggered: actionManager.editLocation("")
	}

	Action {
		id: editPathRootAction
		text: "Edit Path from Root"
		shortcut: actionManager.showShortcuts ? "/" : ""
		onTriggered: actionManager.editLocation("/")
	}

	Action {
		id: editPathHomeAction
		text: "Edit Path from Home"
		shortcut: actionManager.showShortcuts ? "~" : ""
		onTriggered: actionManager.editLocation("~/")
	}


	// New Group
	readonly property var newActionsGroup: [newFolderAction, newTextFileAction]

	Action {
		id: newFolderAction
		text: qsTr("New Fo&lder")
		icon.name: "folder-add"
		shortcut: actionManager.showShortcuts ? "Ctrl+Shift+N" : ""
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
		shortcut: actionManager.showShortcuts ? "Alt+Shift+N" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+R" : ""
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
		shortcut: actionManager.showShortcuts ? "Ctrl+Shift+R" : ""
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
				actionManager.playSound("dialog-error");
				renameField.forceActiveFocus();
				return;
			}
			renameDialog.accept();
			actionManager.playSound("dialog-ok");
			if (actionManager.selectionManager)
				actionManager.selectionManager.clear();
			if (actionManager.targetDirectory)
				actionManager.targetDirectory.rename_free_position(renameDialog.originalName, trimmed);
		}

		title: qsTr("Rename")
		modal: true
		anchors.centerIn: parent
		onOpened: {
			actionManager.playSound("dialog-open");
			renameDialog.errorText = "";
			renameField.text = renameDialog.originalName;
			renameField.forceActiveFocus();
		}
		onClosed: actionManager.playSound("dialog-open")

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
					onPressed: actionManager.playSound("button-pressed")
					onReleased: actionManager.playSound("button-released")
					onClicked: renameDialog.applyRename()
				}

				Button {
					text: qsTr("Cancel")
					onPressed: actionManager.playSound("button-pressed")
					onReleased: actionManager.playSound("button-released")
					onClicked: {
						actionManager.playSound("dialog-cancel");
						renameDialog.reject();
					}
				}
			}
		}
	}

	// Open With: prefer the system chooser through the XDG portal, fall back to the built-in sheet
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

	// Open With sheet. Like the view sheet it is created on first use under the
	// window's content item: an OverlaySheet sizes itself to its parent, and this
	// item has no size of its own. Created lazily so it never exists until asked
	// for.
	property var openWithSheet: null

	function openOpenWithDialog(filePath) {
		const w = actionManager.window;
		const parentItem = (w && w.contentItem) ? w.contentItem : actionManager;
		if (!actionManager.openWithSheet) {
			actionManager.openWithSheet = openWithSheetComponent.createObject(parentItem, {
				fileManager: actionManager.fileManager,
				window: w
			});
		}
		if (actionManager.openWithSheet) {
			actionManager.openWithSheet.filePath = filePath;
			actionManager.openWithSheet.open();
		}
	}

	Component {
		id: openWithSheetComponent
		OpenWithDialog {}
	}
}
