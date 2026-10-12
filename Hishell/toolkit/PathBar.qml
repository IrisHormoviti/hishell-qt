pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

RowLayout {
	id: pathBar
	spacing: Kirigami.Units.mediumSpacing
	Layout.fillWidth: true

	// Untyped to avoid the ShellWindow <-> PathBar cyclic dependency; see
	// ActionManager.qml for the explanation.
	property var window
	property Directory directory
	property string currentPath: pathBar.directory ? pathBar.directory.path : ""
	property string homePath: String(window.fileManager.get_home_directory());

	// Location editing: the breadcrumbs give way to a text box with a completer
	// popup listing the entries matching what is being typed.
	property bool editing: false
	property var completions: []
	property int completionIndex: -1
	property string completionBaseText: ""
	property bool applyingCompletion: false
	// Left alone so handing focus to the Go / Cancel buttons is not mistaken for
	// clicking away, which would close the text box.
	property bool editingButtonPressed: false
	property bool refocusPending: false
	// Set when Enter accepted a location that does not exist; the text box turns
	// red until what is typed changes.
	property bool pathInvalid: false
	// Whether the current folder's menu was up when the crumb was last pressed.
	property bool menuWasOpenOnPress: false

	PathUtils {
		id: pathUtils
	}

	property var segments: {
		let p = pathBar.currentPath;
		let home = pathBar.homePath;
		if (p === "" || p === ".")
			return ["/"];
		if (p.endsWith("/") && p.length > 1)
			p = p.substring(0, p.length - 1);
		if (home.endsWith("/") && home.length > 1)
			home = home.substring(0, home.length - 1);

		if (p === home || p.startsWith(home + "/")) {
			let rel = p === home ? "" : p.substring(home.length + 1);
			let homeName = home.split("/").pop();
			let result = [homeName];
			if (rel !== "") {
				const parts = rel.split("/");
				for (let i = 0; i < parts.length; i++) {
					if (parts[i] !== "") {
						result.push(parts[i]);
					}
				}
			}
			return result;
		} else {
			const parts = p.split("/");
			let result = ["/"];
			for (let i = 0; i < parts.length; i++) {
				if (parts[i] !== "") {
					result.push(parts[i]);
				}
			}
			return result;
		}
	}

	function pathForIndex(idx) {
		let p = pathBar.currentPath;
		let home = pathBar.homePath;
		if (p === "" || p === ".")
			return "/";
		if (p.endsWith("/") && p.length > 1)
			p = p.substring(0, p.length - 1);
		if (home.endsWith("/") && home.length > 1)
			home = home.substring(0, home.length - 1);

		if (p === home || p.startsWith(home + "/")) {
			if (idx === 0)
				return home;
			let rel = p === home ? "" : p.substring(home.length + 1);
			const parts = rel.split("/").filter(function (s) {
				return s !== "";
			});
			return home + "/" + parts.slice(0, idx).join("/");
		} else {
			if (idx === 0)
				return "/";
			const parts = p.split("/").filter(function (s) {
				return s !== "";
			});
			return "/" + parts.slice(0, idx).join("/");
		}
	}

	// ── Location editing ──

	function register() {
		if (pathBar.window)
			pathBar.window.pathBar = pathBar;
	}

	function startEditing(initialText) {
		if (pathBar.editing) {
			editField.forceActiveFocus();
			return;
		}
		pathBar.editing = true;
		editField.text = (initialText && initialText.length > 0) ? initialText : pathBar.currentPath;
		editField.forceActiveFocus();
		editField.cursorPosition = editField.text.length;
		pathBar.completionIndex = -1;
		pathBar.updateCompletions();
	}

	function stopEditing() {
		if (!pathBar.editing)
			return;
		pathBar.editing = false;
		pathBar.completions = [];
		pathBar.completionIndex = -1;
		pathBar.completionBaseText = "";
		pathBar.editingButtonPressed = false;
		pathBar.refocusPending = false;
		pathBar.pathInvalid = false;
		scheduleRefocusCancel.stop();
	}

	function cancelEditing() {
		pathBar.stopEditing();
		pathBar.focusFolderView();
	}

	function focusFolderView() {
		scheduleRefocusCancel.stop();
		pathBar.refocusPending = false;
		pathBar.editingButtonPressed = false;
		const win = pathBar.window;
		if (!win)
			return;
		if (win.primaryFolderView)
			win.primaryFolderView.forceActiveFocus();
		else if (win.focusedFolderView)
			win.focusedFolderView.forceActiveFocus();
	}

	function scheduleRefocus() {
		pathBar.refocusPending = true;
		scheduleRefocusCancel.restart();
	}

	function reclaimEditFocus() {
		if (!pathBar.refocusPending)
			return;
		pathBar.refocusPending = false;
		if (pathBar.editing)
			editField.forceActiveFocus();
	}

	Timer {
		id: scheduleRefocusCancel
		interval: 250
		repeat: false
		onTriggered: pathBar.reclaimEditFocus()
	}

	function updateCompletions() {
		const base = pathBar.directory ? String(pathBar.directory.path) : "";
		let list = [];
		try {
			list = JSON.parse(String(pathUtils.complete_path(base, editField.text, 8)));
		} catch (e) {
			list = [];
		}
		pathBar.completions = list;
	}

	// Replace the text without treating it as typing, so the completer list
	// stays put while cycling through it with the arrow keys.
	function setEditText(text) {
		pathBar.applyingCompletion = true;
		editField.text = text;
		pathBar.applyingCompletion = false;
		editField.cursorPosition = editField.text.length;
	}

	// Tab and clicks accept a completion outright: the text becomes the entry and
	// the list moves on to its contents, so completing can be repeated to walk
	// down the tree.
	function applyCompletion(index) {
		const list = pathBar.completions;
		if (index < 0 || index >= list.length)
			return;
		pathBar.setEditText(String(list[index].path));
		pathBar.completionIndex = -1;
		pathBar.updateCompletions();
		editField.forceActiveFocus();
	}

	// Tab accepts the completion that is previewed as ghost text.
	function acceptCompletion() {
		const list = pathBar.completions;
		if (list.length === 0)
			return;
		const index = (pathBar.completionIndex >= 0 && pathBar.completionIndex < list.length) ? pathBar.completionIndex : 0;
		pathBar.applyCompletion(index);
	}

	function cycleCompletion(delta) {
		const list = pathBar.completions;
		if (list.length === 0)
			return;
		let next = pathBar.completionIndex + delta;
		if (pathBar.completionIndex === -1) {
			pathBar.completionBaseText = editField.text;
			next = delta > 0 ? 0 : list.length - 1;
		}
		if (next < 0) {
			pathBar.completionIndex = -1;
			pathBar.setEditText(pathBar.completionBaseText);
			return;
		}
		if (next >= list.length)
			return;
		pathBar.completionIndex = next;
		pathBar.setEditText(String(list[next].path));
	}

	function navigateToText() {
		const base = pathBar.directory ? String(pathBar.directory.path) : "";
		const listed = pathBar.selectedCompletionPath();
		// A location that names nothing yet falls back to the suggestion it is
		// being completed into; without one the text is rejected instead.
		if (!pathBar.pathExists(editField.text)) {
			if (listed !== editField.text && pathBar.pathExists(listed)) {
				pathBar.setEditText(listed);
			} else {
				pathBar.pathInvalid = true;
				editField.forceActiveFocus();
				return;
			}
		}
		const target = String(pathUtils.resolve_path(base, editField.text));
		pathBar.stopEditing();
		if (pathBar.directory)
			pathBar.directory.open_path(target);
		pathBar.focusFolderView();
	}

	// The path of the suggestion that is previewed, if any; unlike `suffix` this
	// does not depend on the caret, so it is safe to read after a text change.
	function selectedCompletionPath() {
		const list = pathBar.completions;
		if (list.length === 0)
			return "";
		const index = (pathBar.completionIndex >= 0 && pathBar.completionIndex < list.length) ? pathBar.completionIndex : 0;
		return String(list[index].path);
	}

	function pathExists(text) {
		const base = pathBar.directory ? String(pathBar.directory.path) : "";
		return text.length > 0 && !!pathUtils.path_exists(base, text);
	}

	// ── Current folder crumb ──

	// The folder menu is built on first use; creating it up front would add a
	// menu to every window that never opens it.
	property var folderMenu: null

	function ensureFolderMenu() {
		if (!pathBar.folderMenu)
			pathBar.folderMenu = folderMenuComponent.createObject(pathBar);
		return pathBar.folderMenu;
	}

	function crumbPressed(slot) {
		pathBar.menuWasOpenOnPress = pathBar.folderMenu ? pathBar.folderMenu.visible : false;
	}

	function crumbClicked(slot) {
		// A click while the menu is up is the second click on the crumb; it
		// switches to editing the location instead of reopening the menu.
		if (pathBar.menuWasOpenOnPress) {
			pathBar.menuWasOpenOnPress = false;
			if (pathBar.folderMenu)
				pathBar.folderMenu.close();
			// Let the menu release the keyboard before the text box takes it.
			Qt.callLater(() => pathBar.startEditing(""));
			return;
		}
		pathBar.openCurrentFolderMenu(slot);
	}

	function openCurrentFolderMenu(slot) {
		if (pathBar.window && pathBar.window.actionManager)
			pathBar.window.actionManager.pasteTargetPath = "";
		const menu = pathBar.ensureFolderMenu();
		if (!menu)
			return;
		const position = slot.mapToItem(menu.parent, 0, slot.height);
		menu.x = position.x;
		menu.y = position.y;
		menu.open();
	}

	Component {
		id: folderMenuComponent

		ShellContextMenu {
			parent: pathBar
			actionManager: pathBar.window ? pathBar.window.actionManager : null
			directory: pathBar.directory
			targetIsBackground: true
		}
	}

	Component.onCompleted: Qt.callLater(() => pathBar.register())
	onWindowChanged: pathBar.register()
	Component.onDestruction: {
		if (pathBar.window && pathBar.window.pathBar === pathBar)
			pathBar.window.pathBar = null;
	}

	// A popup can still hold the keyboard when editing starts (the Edit Path item
	// in a menu); take it back as soon as the popup lets go.
	Connections {
		target: pathBar.window
		function onActiveFocusItemChanged() {
			if (!pathBar.editing)
				return;
			if (pathBar.refocusPending)
				return;
			const item = pathBar.window ? pathBar.window.activeFocusItem : null;
			// While a button holds the keyboard, stepping from the text box to it
			// must not close the text box.
			if (item === goButton || item === cancelButton) {
				pathBar.editingButtonPressed = true;
				if (pathBar.refocusPending)
					scheduleRefocusCancel.stop();
				return;
			}
			if (!editField.activeFocus)
				editField.forceActiveFocus();
		}
	}

	ListView {
		id: breadcrumbList
		visible: !pathBar.editing
		Layout.fillWidth: true
		Layout.preferredHeight: Kirigami.Units.gridUnit * 2

		orientation: ListView.Horizontal
		interactive: true
		spacing: Kirigami.Units.smallSpacing

		model: pathBar.segments

		// Forces the view to snap to the latest sub-directory when deeply nested
		onCountChanged: Qt.callLater(breadcrumbList.positionViewAtEnd)

		delegate: RowLayout {
			id: delegateRoot
			spacing: Kirigami.Units.mediumSpacing
			height: breadcrumbList.height

			required property int index
			required property string modelData

			readonly property bool isCurrent: delegateRoot.index === pathBar.segments.length - 1

			Label {
				visible: delegateRoot.index > 0 && (pathBar.segments[0] !== "/" || delegateRoot.index > 1)
				text: "/"
				font.pointSize: 12
				color: Kirigami.Theme.disabledTextColor
				Layout.alignment: Qt.AlignVCenter
			}

			FileSlot {
				id: crumbSlot
				path: pathBar.pathForIndex(delegateRoot.index)
				title: delegateRoot.modelData === "/" ? "/" : delegateRoot.modelData
				icon: pathBar.window.fileManager ? pathBar.window.fileManager.get_icon(crumbSlot.path) : ""
				showIcon: delegateRoot.isCurrent
				implicitHeight: Kirigami.Units.iconSizes.medium

				dragDropHandler: pathBar.window.dragDropHandler
				fileManager: pathBar.window.fileManager
				actionManager: pathBar.window.actionManager

				is_dir: true
				is_symlink: false
				index: delegateRoot.index
				gridSize: Kirigami.Units.iconSizes.smallMedium
				labelBesideIcon: true
				isActive: delegateRoot.isCurrent
				fixedWidth: false

				pressHandler: delegateRoot.isCurrent ? (mouse => pathBar.crumbPressed(crumbSlot)) : null
				clickHandler: delegateRoot.isCurrent ? (mouse => pathBar.crumbClicked(crumbSlot)) : null

				Layout.preferredWidth: implicitWidth
				Layout.preferredHeight: implicitHeight
				Layout.alignment: Qt.AlignVCenter
			}
		}
	}

	TextField {
		id: editField
		visible: pathBar.editing
		Layout.fillWidth: true
		Layout.preferredHeight: Kirigami.Units.gridUnit * 2
		placeholderText: String(pathBar.directory.path)
		selectByMouse: true
		// The frame turns red while the typed location is rejected.
		background: Rectangle {
			implicitWidth: 200
			implicitHeight: 40
			color: Kirigami.Theme.backgroundColor
			radius: Kirigami.Units.cornerRadius
			border.width: pathBar.pathInvalid ? 2 : 1
			border.color: pathBar.pathInvalid ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.disabledTextColor
		}

		// The part of the best suggestion that is still missing, shown after the
		// caret as faded text and accepted with Tab. A suggestion that has already
		// been filled in leaves nothing to preview.
		readonly property string completionSuffix: {
			const list = pathBar.completions;
			if (!pathBar.editing || list.length === 0)
				return "";
			const index = (pathBar.completionIndex >= 0 && pathBar.completionIndex < list.length) ? pathBar.completionIndex : 0;
			const completion = String(list[index].path);
			if (completion.startsWith(text))
				return completion.substring(text.length);
			// Matching is case-insensitive, so a match can differ in case from what
			// was typed; the precomputed suffix still covers that case.
			return completion.toLowerCase().startsWith(text.toLowerCase()) ? String(list[index].suffix) : "";
		}

		Text {
			visible: editField.completionSuffix.length > 0 && editField.cursorPosition === editField.length
			x: editField.cursorRectangle.x
			y: editField.cursorRectangle.y
			width: Math.max(0, editField.width - x)
			text: editField.completionSuffix
			font: editField.font
			color: editField.color
			opacity: 0.4
			elide: Text.ElideRight
		}

		onTextChanged: {
			if (pathBar.applyingCompletion)
				return;
			pathBar.completionIndex = -1;
			pathBar.pathInvalid = false;
			pathBar.updateCompletions();
		}

		onActiveFocusChanged: {
			if (pathBar.refocusPending || pathBar.editingButtonPressed)
				return;
			if (!activeFocus && pathBar.editing)
				pathBar.stopEditing();
		}

		onAccepted: pathBar.navigateToText()
		Keys.onEscapePressed: pathBar.cancelEditing()
		Keys.onUpPressed: pathBar.cycleCompletion(-1)
		Keys.onDownPressed: pathBar.cycleCompletion(1)
		Keys.onTabPressed: event => {
			if (pathBar.completions.length > 0)
				pathBar.acceptCompletion();
			else
				event.accepted = false;
		}
	}

	ToolButton {
		id: goButton
		visible: pathBar.editing
		icon.name: "go-next-symbolic"
		Layout.preferredHeight: editField.height
		Layout.alignment: Qt.AlignVCenter
		onPressedChanged: if (pressed)
			pathBar.editingButtonPressed = true
		onClicked: pathBar.navigateToText()
	}

	ToolButton {
		id: cancelButton
		visible: pathBar.editing
		icon.name: "dialog-close"
		Layout.preferredHeight: editField.height
		Layout.alignment: Qt.AlignVCenter
		onPressedChanged: if (pressed)
			pathBar.editingButtonPressed = true
		onClicked: pathBar.cancelEditing()
	}

	Popup {
		id: completionPopup
		parent: pathBar
		// x: editField.x
		// y: editField.y + editField.height
		// width: Math.max(editField.width + goButton.width + cancelButton.width + pathBar.spacing * 2, Kirigami.Units.gridUnit * 16)
		// height: Math.min(completionList.contentHeight, Kirigami.Units.gridUnit * 10)
		padding: 0
		focus: false
		closePolicy: Popup.NoAutoClose
		visible: pathBar.editing && pathBar.completions.length > 0

		ListView {
			id: completionList
			anchors.fill: parent
			clip: true
			model: pathBar.completions

			delegate: ItemDelegate {
				id: completionRow
				required property var modelData
				required property int index
				width: completionList.width
				focusPolicy: Qt.NoFocus
				highlighted: pathBar.completionIndex === completionRow.index
				icon.name: completionRow.modelData.is_dir ? "folder" : "text-x-generic"
				text: String(completionRow.modelData.name)
				onClicked: pathBar.applyCompletion(completionRow.index)
			}
		}
	}
}
