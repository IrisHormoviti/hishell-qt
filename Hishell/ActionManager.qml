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

	// A short message in the window's notice banner. Used for failures that
	// happen after the keyboard has already closed, where a dialog would only
	// be another thing to dismiss.
	function showNotice(text) {
		if (actionManager.window && typeof actionManager.window.showNotice === "function")
			actionManager.window.showNotice(text);
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
	// The count is what the menu's `enabled` bindings watch. Moving the cursor
	// between two items keeps it at 1, so those bindings do not all re-run on
	// every step; only the path-dependent state (refreshed lazily) does.
	readonly property int targetCount: actionManager.hasSelection ? actionManager.selectedCount : (actionManager.focusedPath !== "" ? 1 : 0)
	readonly property bool hasTarget: actionManager.targetCount > 0
	readonly property bool isSingleTarget: actionManager.targetCount === 1
	readonly property string firstTargetPath: actionManager.hasSelection ? actionManager.firstSelectedPath : actionManager.focusedPath
	// Whether one of the targets has an app that is running/suspended behind
	// the shell. The Quit action is only offered for such an item.
	readonly property bool isTargetActive: {
		const fm = actionManager.window ? actionManager.window.focusManager : null;
		if (!fm || !actionManager.hasTarget)
			return false;
		fm.active_revision; // dependency: re-check when the suspended set changes
		const paths = actionManager.targetPaths();
		for (let i = 0; i < paths.length; i++) {
			if (fm.is_item_active(paths[i]))
				return true;
		}
		return false;
	}

	// Built only when an action actually runs; a per-focus array would change
	// identity on every cursor step and wake every binding that reads it.
	function targetPaths() {
		return actionManager.hasSelection ? actionManager.selectedPathList : (actionManager.focusedPath !== "" ? [actionManager.focusedPath] : []);
	}
	// The directory the target lives in; a layout can show several folders, so the
	// owning view decides where paths open and what gets reloaded afterwards.
	readonly property var targetFolderView: actionManager.hasSelection
		? (actionManager.window ? actionManager.window.selectionFolderView : null)
		: (actionManager.window ? actionManager.window.focusedFolderView : null)
	readonly property Directory targetDirectory: (actionManager.targetFolderView && actionManager.targetFolderView.directory) ? actionManager.targetFolderView.directory : actionManager.directory

	// A generated entry (a provider's network or control row) may be destroyed
	// only when the provider says how: Trash then runs the entry's `Destroy=`
	// command instead of moving the file. Cut-then-Paste means the same thing
	// for such an entry (`FileManager::cut_into`), because moving the file alone
	// would leave the profile behind and the daemon would write it straight
	// back. A source that is not destroyable is never copied or moved: drag
	// Copy/Move degrade to a link, and Trash opens the warning instead (§5).

	// Action-target state.
	//
	// These values depend on the focused or selected item, but resolving them
	// is not free: `can_rename` canonicalises the path and consults the
	// descriptor cache, `get_default_app` goes through the MIME database and
	// the KService trader, and every predicate is a separate Rust call. Doing
	// that for each cursor step made a held direction stutter. They are plain
	// properties refreshed when a menu is built (or shortly after the cursor
	// settles), so walking a folder only re-reads the cheap path/count.
	property bool isTargetLink: false
	property bool isTargetRadio: false
	property bool isFolderTarget: false
	property bool isImageTarget: false
	property bool targetRenameable: false
	property bool executeAvailable: false
	property var openApp: null
	readonly property string openAppIcon: openApp ? String(openApp.icon) : ""
	property bool targetStateValid: false

	function invalidateTargetState() {
		actionManager.targetStateValid = false;
		targetRefreshTimer.restart();
	}

	function ensureTargetState() {
		if (!actionManager.targetStateValid)
			actionManager.refreshTargetState();
	}

	function refreshTargetState() {
		actionManager.targetStateValid = true;
		const paths = actionManager.targetPaths();
		const count = paths.length;
		const fm = actionManager.fileManager;
		const directory = actionManager.targetDirectory;
		const first = count > 0 ? String(paths[0]) : "";
		const single = count === 1;

		let folders = count > 0 && fm !== null;
		let images = folders;
		let execute = folders;
		let radio = false;
		let link = false;

		if (count > 0 && fm) {
			for (let i = 0; i < count; i++) {
				const path = String(paths[i]);
				if (folders && !fm.is_directory(path))
					folders = false;
				if (images && !fm.is_image_file(path))
					images = false;
				if (execute) {
					const isRadio = directory ? directory.is_radio_member(path) : false;
					if (!isRadio && !(directory && directory.is_execute_target(path)))
						execute = false;
				}
			}
			if (single && directory) {
				radio = directory.is_radio_member(first);
				link = directory.is_link(first);
			}
		}

		actionManager.isTargetLink = link;
		actionManager.isTargetRadio = radio;
		actionManager.isFolderTarget = folders;
		actionManager.isImageTarget = images;
		actionManager.executeAvailable = execute;
		actionManager.targetRenameable = single && fm !== null && fm.can_rename(first);

		actionManager.openApp = null;
		if (single && !folders && fm) {
			try {
				const info = JSON.parse(fm.get_default_app(first));
				if (info && info.id)
					actionManager.openApp = info;
			} catch (e) {
				// No handler: the action falls back to the plain Open label.
			}
		}
	}

	onFocusedPathChanged: actionManager.invalidateTargetState()
	onHasSelectionChanged: actionManager.invalidateTargetState()

	Timer {
		id: targetRefreshTimer
		interval: 140
		repeat: false
		onTriggered: actionManager.refreshTargetState()
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
	// action icon) on each focus move. Actions are read through
	// `groupActions()` instead of being embedded here.
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
			id: "folders",
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
		actionManager.ensureTargetState();
		switch (id) {
		case "open":
			return actionManager.openActions();
		case "edit":
			return actionManager.editGroup;
		case "image":
			return actionManager.imageGroup;
		case "new":
			return actionManager.newActionsGroup;
		case "folders":
			return actionManager.folderTargetActionsGroup;
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
		actionManager.ensureTargetState();
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
			actions = actions.concat(actionManager.directoryActionsGroup);
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

	// Open Group. ClamOS has a single kiosk shell, so a second window is not a
	// concept the user can act on; keep the action for desktop Hishell only.
	readonly property bool isClamOS: CoreTheme.themeId !== ""

	function openActions() {
		const actions = [];
		if (actionManager.isTargetActive)
			actions.push(quitAction);
		if (actionManager.executeAvailable)
			actions.push(executeAction);
		actions.push(openAction, openWithAction);
		if (!actionManager.isClamOS)
			actions.push(openWindowAction);
		return actions;
	}

	property alias quitAction: quitAction
	Action {
		id: quitAction
		text: qsTr("&Quit")
		icon.name: "process-stop"
		enabled: actionManager.isTargetActive
		onTriggered: {
			const fm = actionManager.window ? actionManager.window.focusManager : null;
			if (!fm || !actionManager.fileManager)
				return;
			const paths = actionManager.targetPaths();
			for (let i = 0; i < paths.length; i++) {
				if (fm.is_item_active(paths[i])) {
					if (actionManager.fileManager.quit_active(paths[i])) {
						fm.refresh_active_items();
						actionManager.playSound("window-close");
					}
					return;
				}
			}
		}
	}

	// A Toggle or Number is a control the shell owns: a toggle flips in place,
	// a number opens the dialog with its labelled values.  Returns true when
	// the path was one of them, so the caller stops before treating it as a
	// file or a launch.
	function activateControl(path: string, sourceItem: Item): bool {
		const fm = actionManager.fileManager;
		if (!fm || !fm.is_control(path))
			return false;
		if (fm.is_toggle(path)) {
			// A switch has its own two sounds (the same pair the View dialog's
			// switches use), so flipping it does not sound like opening a menu
			// item.
			const turningOn = !fm.toggle_on(path);
			actionManager.playSound(turningOn ? "button-toggle-on" : "button-toggle-off");
			fm.run_toggle(path);
			// The provider rewrites the entry when the command returns. Polling
			// would catch it a moment later; this keeps the switch immediate.
			controlReload.restart();
			return true;
		}
		if (fm.is_number(path)) {
			actionManager.playSound("dialog-open");
			if (actionManager.window && typeof actionManager.window.requestNumberDialog === 'function')
				actionManager.window.requestNumberDialog(path);
			return true;
		}
		return false;
	}

	function activatePath(path: string, sourceItem: Item) {
		// The profile's user-name row is a generated button with a Rename=
		// command and no command of its own. Activating it begins the rename,
		// which is how it reaches the system keyboard.
		if (actionManager.activateControl(path, sourceItem))
			return;
		if (actionManager.fileManager && actionManager.fileManager.is_rename_only(path))
			actionManager.beginRename(path);
		else if (directory && directory.is_execute_target(path))
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

	Timer {
		id: controlReload
		interval: 350
		repeat: false
		onTriggered: {
			if (actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
		}
	}

	// A launch is about to start: let the window drop the previous return frame
	// at once, so it cannot show through the launch wash.
	function prepareLaunch() {
		if (actionManager.window && typeof actionManager.window.clearReturnFrame === 'function')
			actionManager.window.clearReturnFrame();
	}

	property alias executeAction: executeAction
	Action {
		id: executeAction
		text: actionManager.isTargetRadio ? qsTr("&Select") : (actionManager.isTargetLink ? qsTr("Open &Link") : qsTr("&Execute"))
		icon.name: actionManager.isTargetRadio ? "checkbox" : (actionManager.isTargetLink ? "open-link" : "system-run")
		enabled: actionManager.executeAvailable

		function execute(targetPath: string, sourceItem: Item) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.targetPaths();
			for (let i = 0; i < paths.length; i++) {
				const path = paths[i];
				// Toggles and numbers have their own editor; Execute means the
				// same as activating the control.
				if (actionManager.activateControl(path, sourceItem))
					continue;
				// A label-only control has no command: Execute means the same
				// as activating it, which begins the rename.
				if (actionManager.fileManager && actionManager.fileManager.is_rename_only(path)) {
					actionManager.beginRename(path);
					continue;
				}
				const isRadio = actionManager.targetDirectory.is_radio_member(path);
				if (!isRadio && !actionManager.targetDirectory.is_execute_target(path))
					continue;
				// A radio child selects in place: the parent writes the
				// selection and runs its own Exec, with no launch transition.
				if (isRadio) {
					actionManager.playSound("menu-item");
					actionManager.targetDirectory.select_radio(path);
					continue;
				}
				// A `Type=Button` entry is a control, not an app: its Exec is
				// spawned directly (no wrapper, no guest window), so it gets the
				// menu-item sound and none of the app-launch transition.
				const isButton = actionManager.fileManager && actionManager.fileManager.is_control(path);
				// The launch sound is the compositor's now: the shell is
				// stopped for the guest and its playback thread would be cut
				// off. Only controls keep their in-shell sound.
				if (isButton)
					actionManager.playSound("menu-item");
				if (!isButton) {
					actionManager.prepareLaunch();
					const layout = sourceItem ? (sourceItem.contentBody ? sourceItem.contentBody : sourceItem.contentLayout) : null;
					if (layout) {
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
		text: actionManager.isTargetRadio ? qsTr("&Select") : (actionManager.openApp ? qsTr("O&pen with %1").arg(actionManager.openApp.name) : qsTr("O&pen"))
		icon.name: actionManager.isTargetRadio ? "checkbox" : (actionManager.openAppIcon !== "" && actionManager.openAppIcon.indexOf("/") === -1 ? actionManager.openAppIcon : "open-link")
		icon.source: actionManager.openAppIcon.indexOf("/") !== -1 ? actionManager.openAppIcon : ""
		enabled: actionManager.hasTarget

		function execute(targetPath: string, sourceItem: Item, inNewWindow = false) {
			const paths = targetPath !== "" ? [targetPath] : actionManager.targetPaths();
			for (let i = 0; i < paths.length; i++) {
				const p = paths[i];
				// A settings control acts in place; it is not a file to hand to
				// another application.
				if (actionManager.activateControl(p, sourceItem))
					continue;
				// Opening a folder in place resets the view's model and destroys the
				// source item, taking any in-flight grab with it while the render
				// thread is still using it. Only grab when the item survives the open.
				const isDir = actionManager.fileManager && actionManager.fileManager.is_directory(p);
				// A `Type=Button` entry is a control, not an app: it runs its Exec
				// directly (no wrapper, no guest window), so it gets the menu-item
				// sound and none of the app-launch transition.
				const isButton = actionManager.fileManager && actionManager.fileManager.is_control(p);
				// A child of a folder-owned radio group is selected in place: the
				// parent writes the selection and runs its own Exec. Opening it in a
				// new window still navigates, since that is an explicit request to
				// leave the group.
				const isRadio = actionManager.targetDirectory && actionManager.targetDirectory.is_radio_member(p);
				const selectsRadio = isRadio && !inNewWindow;
				// A folder opens in place (a navigation); a file leaves the app for
				// its handler. The 3DS makes the same distinction, and so does the
				// theme: window-new for going into a folder, the launch sound for
				// handing a file to another program.
				if (isButton || selectsRadio)
					actionManager.playSound("menu-item");
				else if (isDir)
					actionManager.playSound("window-new");
				// Files and apps: the compositor plays app-launch, so it
				// survives the shell being stopped for the guest.
				if (!isDir && !isButton && !selectsRadio)
					actionManager.prepareLaunch();
				const layout = sourceItem ? (sourceItem.contentBody ? sourceItem.contentBody : sourceItem.contentLayout) : null;
				if (layout && !isButton && !selectsRadio && !(isDir && !inNewWindow)) {
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

				if (selectsRadio) {
					actionManager.targetDirectory.select_radio(p);
					continue;
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
			const paths = targetPath !== "" ? [targetPath] : actionManager.targetPaths();
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
		shortcut: actionManager.showShortcuts && !actionManager.isClamOS ? "Ctrl+N" : ""
		enabled: actionManager.hasTarget && !actionManager.isClamOS
		onTriggered: {
			if (!actionManager.hasTarget) {
				actionManager.directory.open_in_new_window(actionManager.directory.path);
			} else {
				const paths = actionManager.targetPaths();
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
			const paths = actionManager.targetPaths().join("\n");
			if (actionManager.fileManager)
				actionManager.fileManager.copy_paths_to_clipboard(paths);
		}
	}

	Action {
		id: cutAction
		text: qsTr("C&ut")
		icon.name: "edit-cut"
		shortcut: actionManager.showShortcuts ? "Ctrl+X" : ""
		enabled: actionManager.hasTarget
		onTriggered: {
			const paths = actionManager.targetPaths().join("\n");
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
			const paths = actionManager.targetPaths();
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
			const paths = actionManager.targetPaths();
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
		enabled: actionManager.targetRenameable
		onTriggered: {
			if (actionManager.isSingleTarget) {
				actionManager.beginRename(actionManager.firstTargetPath);
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
		enabled: actionManager.hasTarget
		onTriggered: {
			if (actionManager.window && actionManager.window.requestDestroy) {
				actionManager.window.requestDestroy(actionManager.targetPaths(), actionManager.targetDirectory);
			} else {
				// A host without the warning adapter keeps the old direct path.
				const paths = actionManager.targetPaths();
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
	}

	// Current-directory actions. These belong to the background/current
	// folder menu only; a folder *item's* context menu must not show them.
	readonly property var directoryActionsGroup: [editPathAction, refreshAction, pasteAction]
	// Actions that apply to a folder item. Open/Edit are already in the item
	// groups; keep this separate so the folder target never inherits the
	// current directory's navigation actions.
	readonly property var folderTargetActionsGroup: []
	property alias goBackAction: goBackAction
	property alias goForwardAction: goForwardAction
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

	readonly property var navigationView: actionManager.window ? actionManager.window.focusedFolderView : null

	Action {
		id: goBackAction
		text: qsTr("Go &Back")
		icon.name: "arrow-left-symbolic"
		shortcut: actionManager.showShortcuts ? "Alt+Left" : ""
		enabled: actionManager.navigationView ? actionManager.navigationView.canGoBack : false
		onTriggered: {
			if (actionManager.navigationView)
				actionManager.navigationView.goBack();
		}
	}

	Action {
		id: goForwardAction
		text: qsTr("Go &Forward")
		icon.name: "arrow-right-symbolic"
		shortcut: actionManager.showShortcuts ? "Alt+Right" : ""
		enabled: actionManager.navigationView ? actionManager.navigationView.canGoForward : false
		onTriggered: {
			if (actionManager.navigationView)
				actionManager.navigationView.goForward();
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
			const paths = actionManager.targetPaths();
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
			const paths = actionManager.targetPaths();
			let anyOk = false;
			for (let i = 0; i < paths.length; i++) {
				if (actionManager.fileManager && actionManager.fileManager.rotate_image(paths[i], 270))
					anyOk = true;
			}
			if (anyOk && actionManager.targetDirectory)
				actionManager.targetDirectory.reload();
		}
	}

	// Rename: ask the system keyboard when it is running. The keyboard already
	// draws the text with an OK/Cancel bar, and it covers the touch panel, so a
	// dialog with a second text field would only be hidden underneath it. The
	// dialog stays as the fallback for systems without ClamOS's keyboard, and
	// for a keyboard that dies while a request is pending.
	property string renamePath: ""
	property string renameOriginal: ""
	property string renameRequest: ""

	function beginRename(filePath) {
		if (!actionManager.fileManager || !actionManager.fileManager.can_rename(filePath))
			return;
		if (actionManager.renameRequest !== "")
			return;
		const name = String(actionManager.fileManager.rename_display_name(filePath));
		const id = String(actionManager.fileManager.request_text_entry(qsTr("Rename"), name, "stem"));
		if (id !== "") {
			actionManager.renamePath = filePath;
			actionManager.renameOriginal = name;
			actionManager.renameRequest = id;
			renameTimer.missing = 0;
			renameTimer.restart();
			return;
		}
		actionManager.showRenameDialog(filePath, name);
	}

	function showRenameDialog(filePath, name) {
		renameDialog.filePath = filePath;
		renameDialog.originalName = name;
		renameDialog.newName = name;
		renameDialog.open();
	}

	/// Apply a rename for either input path. Returns "" on success (including
	/// a no-op), or the message to show.
	function renameTo(filePath, originalName, newName) {
		const trimmed = String(newName).trim();
		if (trimmed.length === 0 || trimmed === originalName)
			return "";
		const fm = actionManager.fileManager;
		if (!fm)
			return qsTr("Rename is not available.");
		const movesPath = fm.rename_moves_path(filePath);
		let status;
		try {
			status = JSON.parse(fm.rename_file(filePath, trimmed));
		} catch (e) {
			return qsTr("Rename is not available.");
		}
		if (!status.ok)
			return status.error || qsTr("Rename failed.");
		actionManager.playSound("dialog-ok");
		if (actionManager.selectionManager)
			actionManager.selectionManager.clear();
		if (actionManager.targetDirectory) {
			// A label rename leaves the file name alone, so there is no
			// free-placement entry to move; just refresh the view.  Waiting
			// for the provider's own revision is the same poll that already
			// updates live entries.
			if (movesPath)
				actionManager.targetDirectory.rename_free_position(originalName, trimmed);
			else
				actionManager.targetDirectory.reload();
		}
		return "";
	}

	function finishKeyboardRename(status, text) {
		const filePath = actionManager.renamePath;
		const originalName = actionManager.renameOriginal;
		actionManager.renamePath = "";
		actionManager.renameOriginal = "";
		actionManager.renameRequest = "";
		if (filePath === "")
			return;
		if (status === "cancel") {
			actionManager.playSound("dialog-cancel");
			return;
		}
		if (status !== "ok")
			return;
		const error = actionManager.renameTo(filePath, originalName, String(text || ""));
		if (error !== "") {
			actionManager.playSound("dialog-error");
			actionManager.showNotice(error);
		}
	}

	// Poll the keyboard's response. A request is only abandoned when the
	// keyboard stops answering its liveness marker; there is no timeout while
	// someone is typing.
	Timer {
		id: renameTimer
		interval: 120
		repeat: true
		running: false
		property int missing: 0

		function fallBackToDialog() {
			const filePath = actionManager.renamePath;
			const originalName = actionManager.renameOriginal;
			const id = actionManager.renameRequest;
			actionManager.renamePath = "";
			actionManager.renameOriginal = "";
			actionManager.renameRequest = "";
			stop();
			if (id !== "" && actionManager.fileManager)
				actionManager.fileManager.cancel_text_entry(id);
			if (filePath !== "")
				actionManager.showRenameDialog(filePath, originalName);
		}

		onTriggered: {
			const fm = actionManager.fileManager;
			if (actionManager.renameRequest === "" || !fm) {
				stop();
				return;
			}
			if (!fm.keyboard_available()) {
				if (++missing < 10)
					return;
				fallBackToDialog();
				return;
			}
			missing = 0;
			let result = {
				status: "pending"
			};
			try {
				result = JSON.parse(fm.poll_text_entry(actionManager.renameRequest));
			} catch (e) {
				return;
			}
			if (result.status === "pending")
				return;
			stop();
			actionManager.finishKeyboardRename(result.status, result.text || "");
		}
	}

	Dialog {
		id: renameDialog
		property string filePath: ""
		property string originalName: ""
		property string newName: ""
		property string errorText: ""

		function applyRename() {
			const trimmed = renameDialog.newName.trim();
			if (trimmed.length === 0 || trimmed === renameDialog.originalName) {
				renameDialog.accept();
				return;
			}
			const error = actionManager.renameTo(renameDialog.filePath, renameDialog.originalName, trimmed);
			if (error !== "") {
				renameDialog.errorText = error;
				actionManager.playSound("dialog-error");
				renameField.forceActiveFocus();
				return;
			}
			renameDialog.accept();
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
		// Dialogs belong on the window's overlay layer, which draws above the
		// content whatever z the panes use (a focused FileSlot is z: 3). See
		// ViewButton.openViewDialog.
		const parentItem = (w && w.overlay) ? w.overlay
			: ((w && w.contentItem) ? w.contentItem : actionManager);
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
