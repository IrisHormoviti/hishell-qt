pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: fileSlot

	required property string path

	// Untyped to avoid the ShellWindow <-> FileSlot cyclic dependency; see
	// ActionManager.qml for the explanation.
	property var window: Window.window
	property alias contentLayout: contentLayout

	property DragDropHandler dragDropHandler: window ? window.dragDropHandler : null
	property ActionManager actionManager: window ? window.actionManager : null
	property FileManager fileManager: window ? window.fileManager : null

	required property string icon
	required property string title
	property int gridSize: 64
	property bool labelBesideIcon: gridSize < 32
	property bool showLabels: true
	// With no label the icon takes over the whole slot, so the view reads as a gallery.
	readonly property real iconDisplaySize: fileSlot.showLabels ? fileSlot.gridSize : Math.max(fileSlot.gridSize, Math.min(fileSlot.width, fileSlot.height) - Kirigami.Units.smallSpacing * 2)
	// Whether the label shows the file name instead of the item's title.
	property bool labelShowsFilename: false
	property bool fixedWidth: true
	property bool showIcon: icon !== ""
	required property bool is_symlink
	required property int index
	property bool is_dir: false

	// A `Type=Button` entry is a control, not a thing to open (docs §2 of
	// docs/settings-as-folders.md): it acts where it stands. Drawing it like the
	// files and folders around it made the two read the same, so it is drawn as
	// a button instead — a filled, rounded plate behind the icon and label,
	// which is the shape every other control on the device already has.
	readonly property bool isButton: fileManager ? fileManager.is_button(String(fileSlot.path)) : false

	// The FolderView that owns this slot; used to detect free-placement mode,
	// where the background DropArea owns all drops (including folder targets).
	readonly property var folderView: {
		let p = fileSlot.parent;
		while (p) {
			if (typeof p.isFreeRepositionDrop === 'function')
				return p;
			p = p.parent;
		}
		return null;
	}
	readonly property bool freePlacement: folderView && folderView.config ? (folderView.config.sort === 3 && folderView.config.view_mode === 0) : false

	// Whether a plain click opens the item. When off, the first click only
	// focuses it and a click on the (now focused) item opens it. See ViewActions.
	readonly property bool openOnClick: fileSlot.folderView && fileSlot.folderView.config ? fileSlot.folderView.config.open_on_click : true

	property int animationDuration: 200
	property int animationEase: Easing.OutCubic

	// Selection state passed from FolderView
	property bool selectionActive: false
	property bool isSelected: false

	// Used for when this item is open in another view
	property bool isActive: false

	// Owner hooks for plain left clicks, used by the path bar to open the current
	// folder's menu instead of reopening it: `pressHandler` is called on press
	// and `clickHandler` replaces the default activation on click.
	property var pressHandler: null
	property var clickHandler: null

	// Focus state passed from FolderView (independent of selection)
	property bool focusActive: false
	property bool isFocused: false
	property string focusBorderSource: ""
	property double focusBorderScale: 1
	property double focusBorderMovment: 0.03

	property int currentDragCount: 1

	// Event sounds (ClamOS XDG sound theme). Played through the window's sound
	// object; a null window (or a missing theme) simply stays silent.
	function playSound(name) {
		const w = fileSlot.Window.window;
		if (w && w.sound)
			w.sound.play(name);
	}

	property bool isDraggingThisSlot: localDragTarget.Drag.active
	onIsDraggingThisSlotChanged: {
		if (!isDraggingThisSlot && mouseArea.dragStarted) {
			mouseArea.dragStarted = false;
			mouseArea.dragInitiated = false;
			if (typeof fileSlot.dragDropHandler !== 'undefined' && fileSlot.dragDropHandler) {
				fileSlot.dragDropHandler.active_dragged_paths = [];
				fileSlot.dragDropHandler.tooltip_active = false;
				fileSlot.dragDropHandler.end_drag();
			}
		}
	}

	// Emitted when toggling this item's selection
	signal selectionToggled(string path, int idx)

	// Emitted for range selection
	signal shiftSelected(int idx)

	// Emitted on press and hold
	signal pressHeld(string path, int idx)

	// Emitted before the attached context menu opens.
	signal contextMenuRequested(string path, int idx)

	// The context menu for this item. This used to be an attached object named
	// "ContextMenu", which was never defined; Qt 6.8 rejects it with
	// "Non-existent attached object" and marks FileSlot unavailable, which in
	// turn breaks FolderView and PathBar.
	//
	// Built lazily: a folder can hold hundreds of slots, and each context menu
	// instantiates a ViewMenu plus every action group — thousands of QMenu
	// items whose themed icons Qt would resolve eagerly, which dominated
	// startup and made focusing items feel slow on the device. The menu is only
	// needed when one is actually opened.
	Loader {
		id: contextMenuLoader
		active: false
		sourceComponent: contextMenuComponent
	}

	Component {
		id: contextMenuComponent
		ShellContextMenu {
			actionManager: fileSlot.actionManager
			targetIsDir: fileSlot.is_dir
			targetIsImage: fileSlot.fileManager && fileSlot.fileManager.is_image_file(fileSlot.path)
		}
	}

	readonly property ShellContextMenu contextMenu: contextMenuLoader.item

	function openContextMenu() {
		if (fileSlot.actionManager)
			fileSlot.actionManager.pasteTargetPath = fileSlot.is_dir ? fileSlot.path : "";
		fileSlot.contextMenuRequested(fileSlot.path, fileSlot.index);

		contextMenuLoader.active = true;
		const menu = contextMenuLoader.item;
		if (!menu)
			return null;
		menu.parent = fileSlot;
		const position = fileSlot.mapToItem(menu.parent, 0, fileSlot.height);
		menu.x = position.x;
		menu.y = position.y;
		menu.open();
		return menu;
	}

	implicitWidth: contentLayout.implicitWidth + (fileSlot.labelBesideIcon && fileSlot.showIcon && fileSlot.showLabels ? Kirigami.Units.largeSpacing * 2 : Kirigami.Units.smallSpacing * 2)
	implicitHeight: contentLayout.implicitHeight + Kirigami.Units.smallSpacing * 2
	// The on-disk name, used by the FILENAME label mode and the tooltip.
	readonly property string fileName: {
		const path = fileSlot.path;
		const slash = path.lastIndexOf("/");
		const name = slash >= 0 ? path.substring(slash + 1) : path;
		return name !== "" ? name : path;
	}

	// The text the label shows; the other one is offered as a tooltip.
	readonly property string labelText: fileSlot.labelShowsFilename || fileSlot.title === "" ? fileSlot.fileName : fileSlot.title
	readonly property string tooltipText: {
		const alternate = fileSlot.labelShowsFilename ? fileSlot.title : fileSlot.fileName;
		if (!fileSlot.showLabels)
			return alternate !== "" && alternate !== fileSlot.labelText ? fileSlot.labelText + "\n" + alternate : fileSlot.labelText;
		if (fileSlot.title === "" || fileSlot.title === fileSlot.fileName)
			return "";
		return alternate;
	}

	// Dotfiles (hidden entries) are always dimmed so they read as secondary.
	readonly property bool isDotfile: fileSlot.fileName.startsWith(".")
	opacity: {
		if (fileSlot.dragDropHandler && fileSlot.dragDropHandler.active_dragged_paths && fileSlot.dragDropHandler.active_dragged_paths.indexOf(fileSlot.path) !== -1)
			return 0.2;
		return fileSlot.isDotfile ? 0.5 : 1.0;
	}
	scale: mouseArea.pressed ? 0.9 : (mouseArea.containsMouse ? 1.05 : 1.0)

	Behavior on opacity {
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	Behavior on scale {
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	// Free-placement repositioning animates the slot change; other layout
	// changes (resize, scroll) keep snapping as before.
	Behavior on x {
		enabled: fileSlot.folderView ? fileSlot.folderView.repositionAnimating : false
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	Behavior on y {
		enabled: fileSlot.folderView ? fileSlot.folderView.repositionAnimating : false
		NumberAnimation {
			duration: fileSlot.animationDuration
			easing.type: fileSlot.animationEase
		}
	}

	// ── Button plate ──
	// Only for `Type=Button` entries. One width for all of them — a row of
	// buttons of different sizes reads as broken — with the label elided to
	// fit, and only as tall as the icon, label and padding need.
	Rectangle {
		id: buttonPlate
		visible: fileSlot.isButton
		anchors.horizontalCenter: contentLayout.horizontalCenter
		anchors.verticalCenter: contentLayout.verticalCenter
		width: fileSlot.gridSize + Kirigami.Units.gridUnit
		height: contentLayout.height + Kirigami.Units.smallSpacing
		radius: Kirigami.Units.cornerRadius * 1.5
		color: mouseArea.pressed ? Kirigami.Theme.highlightColor
			: (mouseArea.containsMouse ? Qt.lighter(Kirigami.Theme.backgroundColor, 1.15) : Qt.darker(Kirigami.Theme.backgroundColor, 1.08))
		border.width: 1
		border.color: mouseArea.pressed || mouseArea.containsMouse ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
		opacity: 0.85

		Behavior on color {
			ColorAnimation { duration: fileSlot.animationDuration }
		}
	}

	// ── Layout ──

	GridLayout {
		id: contentLayout
		anchors.verticalCenter: parent.verticalCenter
		x: (fileSlot.labelBesideIcon && fileSlot.showIcon && fileSlot.showLabels) ? Kirigami.Units.largeSpacing : (parent.width - width) / 2
		columns: (fileSlot.labelBesideIcon && fileSlot.showIcon && fileSlot.showLabels) ? 2 : 1

		Item {
			visible: fileSlot.showIcon
			Layout.alignment: (fileSlot.labelBesideIcon && fileSlot.showIcon) ? Qt.AlignVCenter : Qt.AlignHCenter
			Layout.preferredWidth: fileSlot.iconDisplaySize
			Layout.preferredHeight: fileSlot.iconDisplaySize

			Loader {
				anchors.fill: parent
				active: fileSlot.showIcon
				sourceComponent: (fileSlot.icon.startsWith("file://") || fileSlot.icon.startsWith("/")) ? thumbnailComponent : iconComponent
			}

			Component {
				id: thumbnailComponent
				Image {
					source: fileSlot.icon
					asynchronous: true
					cache: false
					fillMode: Image.PreserveAspectFit
					smooth: true
					anchors.fill: parent
					clip: true
					anchors.centerIn: parent
				}
			}

			Component {
				id: iconComponent
				Kirigami.Icon {
					source: fileSlot.icon
					Layout.preferredWidth: fileSlot.gridSize
					Layout.preferredHeight: fileSlot.gridSize
					Layout.fillWidth: false
					Layout.fillHeight: false
				}
			}
		}

		Label {
			id: labelItem
			visible: fileSlot.showLabels
			Layout.alignment: fileSlot.labelBesideIcon ? Qt.AlignVCenter : Qt.AlignHCenter

			text: {
				let t = fileSlot.labelText;

				let styled = t;
				const idx = t.lastIndexOf('.');
				if (idx > 0 && !(t.startsWith('.') && t.indexOf('.', 1) === -1)) {
					const name = t.substring(0, idx);
					const ext = t.substring(idx);
					styled = name + '<font color="' + Kirigami.Theme.disabledTextColor + '">' + ext + '</font>';
				}
				return t;
			}
			textFormat: Text.StyledText
			color: Kirigami.Theme.textColor
			wrapMode: Text.Wrap
			maximumLineCount: 2

			font.italic: fileSlot.is_symlink
			font.bold: fileSlot.isActive

			elide: fileSlot.labelBesideIcon ? Text.ElideMiddle : Text.ElideMiddle
			// A button's label is bounded by its plate; an ordinary item's by
			// the grid cell it lives in.
			Layout.maximumWidth: fileSlot.isButton
				? buttonPlate.width - Kirigami.Units.largeSpacing * 2
				: (fileSlot.labelBesideIcon ? (fileSlot.fixedWidth ? fileSlot.width - fileSlot.gridSize - Kirigami.Units.gridUnit * 2 : 250) : fileSlot.gridSize + Kirigami.Units.gridUnit * 2)
			horizontalAlignment: fileSlot.labelBesideIcon ? Text.AlignLeft : Text.AlignHCenter
		}
	}

	// ── Suspended-app mark ──
	// A small accent dot under an item whose app is currently suspended, with a
	// gentle blink so it reads as "still running". `active_revision` is read only
	// to re-evaluate the binding when the set of suspended apps changes.
	Rectangle {
		id: activeDot
		width: Kirigami.Units.smallSpacing * 2
		height: width
		radius: width / 2
		color: Kirigami.Theme.highlightColor
		anchors.horizontalCenter: contentLayout.horizontalCenter
		anchors.top: contentLayout.bottom
		anchors.topMargin: Kirigami.Units.smallSpacing
		visible: {
			const fm = fileSlot.folderView ? fileSlot.folderView.focusManager : null;
			if (!fm)
				return false;
			fm.active_revision; // dependency: re-check when the set changes
			return fm.is_item_active(fileSlot.path);
		}

		SequentialAnimation on opacity {
			running: activeDot.visible
			loops: Animation.Infinite
			NumberAnimation { to: 0.2; duration: 700; easing.type: Easing.InOutQuad }
			NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
		}
	}

	// ── Selection ──

	Rectangle {
		z: -1
		anchors.fill: parent
		anchors.margins: isSelected ? Kirigami.Units.smallSpacing : 0
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.highlightColor
		opacity: (fileSlot.isSelected ? 0.25 : 0.0) || (fileSlot.isActive ? 0.5 : 0.0)
		Behavior on opacity {
			NumberAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}
	}

	Rectangle {
		anchors.fill: parent
		anchors.margins: Kirigami.Units.smallSpacing
		radius: Kirigami.Units.cornerRadius
		color: "transparent"
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
		opacity: fileSlot.isSelected ? 1.0 : 0.0
		Behavior on opacity {
			NumberAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}
	}

	// ── Focus ──

	Item {
		id: focusIndicator
		anchors.fill: parent
		z: 3
		visible: fileSlot.focusActive && fileSlot.isFocused

		readonly property real cornerSize: Math.max(10, Math.round(Math.min(width, height) * 0.3))
		property real pulse: 0.0

		SequentialAnimation on pulse {
			running: focusIndicator.visible
			loops: Animation.Infinite
			NumberAnimation {
				to: 1.0
				duration: animationDuration * 4
				easing.type: Easing.InOutQuad
			}
			NumberAnimation {
				to: -1.0
				duration: animationDuration * 2
				easing.type: Easing.InOutQuad
			}
		}

		Item {
			id: focusCorners
			anchors.fill: parent
			scale: focusBorderScale + focusIndicator.pulse * focusBorderMovment
			opacity: 0.95 - focusIndicator.pulse * 0.35

			// Each corner is its own 32x32 document holding one bracket, drawn
			// straight at the corner size. The corners used to be clipped out of
			// one raster, which broke whenever sourceSize and sourceClipRect were
			// not in the same coordinate space (anything but a 1:1 pixel ratio).
			Image {
				anchors.left: parent.left
				anchors.top: parent.top
				width: focusIndicator.cornerSize
				height: focusIndicator.cornerSize
				source: fileSlot.focusBorderSource ? fileSlot.focusBorderSource + "-0.svg" : ""
				smooth: true
			}

			Image {
				anchors.right: parent.right
				anchors.top: parent.top
				width: focusIndicator.cornerSize
				height: focusIndicator.cornerSize
				source: fileSlot.focusBorderSource ? fileSlot.focusBorderSource + "-1.svg" : ""
				smooth: true
			}

			Image {
				anchors.right: parent.right
				anchors.bottom: parent.bottom
				width: focusIndicator.cornerSize
				height: focusIndicator.cornerSize
				source: fileSlot.focusBorderSource ? fileSlot.focusBorderSource + "-2.svg" : ""
				smooth: true
			}

			Image {
				anchors.left: parent.left
				anchors.bottom: parent.bottom
				width: focusIndicator.cornerSize
				height: focusIndicator.cornerSize
				source: fileSlot.focusBorderSource ? fileSlot.focusBorderSource + "-3.svg" : ""
				smooth: true
			}
		}
	}

	Rectangle {
		Kirigami.Theme.colorSet: Kirigami.Theme.Selection
		Kirigami.Theme.inherit: false

		anchors.top: parent.top
		anchors.right: parent.right
		anchors.margins: Kirigami.Units.mediumSpacing
		width: Kirigami.Units.iconSizes.small
		height: Kirigami.Units.iconSizes.small
		radius: Kirigami.Units.cornerRadius
		border.width: 2
		border.color: Kirigami.Theme.backgroundColor
		color: fileSlot.isSelected ? Kirigami.Theme.backgroundColor : "transparent"
		opacity: fileSlot.isSelected ? 1.0 : 0.4
		visible: fileSlot.selectionActive
		Behavior on color {
			ColorAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}

		Kirigami.Icon {
			anchors.fill: parent
			anchors.margins: 2
			source: "emblem-ok-symbolic"
			opacity: fileSlot.isSelected ? 1.0 : 0

			Behavior on opacity {
				NumberAnimation {
					duration: fileSlot.animationDuration
					easing.type: fileSlot.animationEase
				}
			}
		}
	}

	// ── Drop Target ───

	Rectangle {
		anchors.fill: parent
		anchors.margins: 2
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.focusColor
		opacity: slotDropArea.isHovered ? 0.35 : 0.0
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
		Behavior on opacity {
			NumberAnimation {
				duration: fileSlot.animationDuration
				easing.type: fileSlot.animationEase
			}
		}
	}

	DropArea {
		id: slotDropArea
		anchors.fill: parent
		enabled: fileSlot.is_dir && !fileSlot.freePlacement
		keys: ["text/uri-list", "text/plain"]

		property bool isHovered: false
		property DragDropHandler dragDropHandler: fileSlot.dragDropHandler ? fileSlot.dragDropHandler : null

		function checkValid(drag) {
			let sourcePaths = [];
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_source_paths && dragDropHandler.drag_source_paths.length > 0) {
				sourcePaths = dragDropHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			let fView = null;
			let p = fileSlot.parent;
			while (p) {
				if (typeof p.isDropValid === 'function') {
					fView = p;
					break;
				}
				p = p.parent;
			}

			if (fView && !fView.isDropValid(fileSlot.path, sourcePaths)) {
				slotDropArea.isHovered = false;
				if (typeof dragDropHandler !== 'undefined')
					dragDropHandler.tooltip_active = false;
				drag.accepted = false;
				hoverNavTimer.stop();
				return false;
			}

			slotDropArea.isHovered = true;
			if (typeof dragDropHandler !== 'undefined') {
				dragDropHandler.tooltip_active = true;
			}
			drag.accept();
			return true;
		}

		onEntered: drag => {
			if (checkValid(drag)) {
				hoverNavTimer.restart();
			}
		}

		onPositionChanged: drag => {
			checkValid(drag);
		}

		onExited: {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
			if (typeof dragDropHandler !== 'undefined')
				dragDropHandler.tooltip_active = false;
		}

		onDropped: drop => {
			slotDropArea.isHovered = false;
			hoverNavTimer.stop();
			if (typeof dragDropHandler !== 'undefined')
				dragDropHandler.tooltip_active = false;

			let uris = "";
			if (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_uris && dragDropHandler.drag_uris.length > 0) {
				uris = dragDropHandler.drag_uris.join("\n");
			} else if (drop.source && drop.source.dragUris) {
				uris = drop.source.dragUris.join("\n");
			} else if (drop.hasUrls) {
				uris = drop.urls.join("\n");
			} else if (drop.hasText) {
				uris = drop.text;
			}

			if (uris.length > 0 && typeof fileManager !== 'undefined' && fileManager) {
				const action = (typeof dragDropHandler !== 'undefined' && dragDropHandler.drag_action) ? dragDropHandler.drag_action : "copy";
				if (fileManager.process_uris_action(fileSlot.path, uris, action)) {
					fileSlot.playSound("drag-accept");
					let p = fileSlot.parent;
					while (p) {
						if (p.directory) {
							p.directory.reload();
							break;
						}
						p = p.parent;
					}
				} else {
					fileSlot.playSound("drag-fail");
				}
				drop.accept();
			}
		}
	}

	Timer {
		id: hoverNavTimer
		interval: 800
		repeat: false
		onTriggered: {
			if (slotDropArea.isHovered && fileSlot.is_dir) {
				const targetPath = fileSlot.path;
				if (typeof fileSlot.dragDropHandler !== 'undefined')
					fileSlot.dragDropHandler.tooltip_active = false;
				Qt.callLater(function () {
					if (fileSlot.actionManager && fileSlot.actionManager.openAction)
						fileSlot.actionManager.openAction.execute(targetPath, fileSlot, false);
				});
			}
		}
	}

	// ── Mouse & Drag Handling ───

	Item {
		id: localDragTarget
		width: fileSlot.width > 0 ? fileSlot.width : fileSlot.implicitWidth
		height: fileSlot.height > 0 ? fileSlot.height : fileSlot.implicitHeight
		Drag.keys: ["text/uri-list", "text/plain"]
		property DragDropHandler dragDropHandler: fileSlot.dragDropHandler ? fileSlot.dragDropHandler : null
		Drag.mimeData: {
			"text/uri-list": dragDropHandler ? dragDropHandler.drag_uris.join("\n") : ""
		}
		Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
		Drag.proposedAction: Qt.MoveAction
		Drag.dragType: Drag.Automatic
		Drag.active: false
		Drag.hotSpot: Qt.point(Math.round(width / 2), Math.round(height / 2))
	}

	// What a plain left click on this item does. With OpenOnClick off, a click
	// on an unfocused item only moves the cursor to it; the next click (while it
	// is focused) opens it.
	function activateOrFocus() {
		if (!fileSlot.actionManager)
			return;
		if (fileSlot.openOnClick || fileSlot.isFocused) {
			fileSlot.actionManager.activatePath(fileSlot.path, fileSlot);
		} else if (fileSlot.folderView && typeof fileSlot.folderView.focusSlot === 'function') {
			fileSlot.folderView.focusSlot(fileSlot.path);
		}
	}

	MouseArea {
		id: mouseArea
		anchors.fill: parent
		hoverEnabled: true
		acceptedButtons: Qt.LeftButton | Qt.MiddleButton
		pressAndHoldInterval: 300
		cursorShape: Qt.PointingHandCursor

		// Touch drags scroll the view; a slot can only be dragged once it has
		// been held (which selects it). A mouse keeps the immediate-drag
		// behaviour, so touch leaves drag.target unset until the hold.
		property bool touchInput: false
		readonly property bool dragAllowed: mouseArea.touchInput ? mouseArea.isPressAndHoldActive : !mouseArea.isPressAndHoldActive
		drag.target: (mouseArea.touchInput && !mouseArea.isPressAndHoldActive) ? null : localDragTarget
		drag.axis: Drag.XAndYAxis

		property DragDropHandler dragDropHandler: fileSlot.dragDropHandler ? fileSlot.dragDropHandler : null
		property bool dragStarted: false
		property bool isPressAndHoldActive: false

		property int startX: 0
		property int startY: 0
		property bool dragInitiated: false
		property bool repositionDrag: false

		Component.onDestruction: {
			if (typeof dragDropHandler !== 'undefined' && mouseArea.repositionDrag) {
				const fView = fileSlot.folderView;
				if (fView)
					fView.cancelRepositionDrag();
				mouseArea.repositionDrag = false;
			}
			if (typeof dragDropHandler !== 'undefined' && mouseArea.dragStarted) {
				localDragTarget.Drag.active = false;
				dragDropHandler.active_dragged_paths = [];
				dragDropHandler.tooltip_active = false;
				dragDropHandler.end_drag();
			}
		}

		function grabAndStartNativeDrag(wx, wy) {
			const targetToGrab = contentLayout;

			targetToGrab.grabToImage(function (result) {
				if (!mouseArea.dragAllowed) {
					if (typeof dragDropHandler !== 'undefined' && dragDropHandler)
						dragDropHandler.active_dragged_paths = [];
					return;
				}

				localDragTarget.Drag.imageSource = result.url;
				localDragTarget.Drag.hotSpot = Qt.point(Math.round(targetToGrab.width / 2), Math.round(targetToGrab.height / 2));

				if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
					dragDropHandler.track_mouse_shake(wx, wy);
					dragDropHandler.begin_drag(result.url.toString(), targetToGrab.width, targetToGrab.height);
				}

				mouseArea.dragStarted = true;
				localDragTarget.Drag.active = true;
			});
		}

		function initiateDragPayload(mouse) {
			if (dragInitiated)
				return;
			dragInitiated = true;
			fileSlot.playSound("drag-start");

			const uris = [];
			const rawPaths = [];
			const mainPath = fileSlot.path;
			const mainUri = mainPath.startsWith("file://") ? mainPath : ("file://" + mainPath);

			let mgr = null;
			let p = fileSlot.parent;
			while (p) {
				if (p.selectionManager) {
					mgr = p.selectionManager;
					break;
				}
				if (p.rootWindow && p.rootWindow.selectionManager) {
					mgr = p.rootWindow.selectionManager;
					break;
				}
				p = p.parent;
			}

			let selectedMap = {};
			try {
				selectedMap = JSON.parse(mgr ? mgr.selected_paths : "{}");
			} catch (e) {}

			if (mgr && mgr.selected_count > 1 && selectedMap[mainPath]) {
				const keys = Object.keys(selectedMap);
				for (let i = 0; i < keys.length; i++) {
					const pathKey = keys[i];
					if (selectedMap[pathKey]) {
						rawPaths.push(pathKey);
						uris.push(pathKey.startsWith("file://") ? pathKey : ("file://" + pathKey));
					}
				}
			} else {
				rawPaths.push(mainPath);
				uris.push(mainUri);
			}

			fileSlot.currentDragCount = rawPaths.length;

			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				dragDropHandler.active_dragged_paths = rawPaths;
				dragDropHandler.set_drag_data(mainPath, uris, rawPaths, uris.length, fileSlot.title, fileSlot.icon);
			}

			const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);

			// A free-placement drag of items that already live in this folder is
			// repositioned directly, without an OS drag, so the whole selection can
			// follow the cursor and the move can be animated.
			const fView = fileSlot.folderView;
			if (fView && typeof fView.beginRepositionDrag === 'function' && fView.beginRepositionDrag(mainPath, rawPaths, pt.x, pt.y, mouse.x, mouse.y)) {
				mouseArea.repositionDrag = true;
				if (typeof dragDropHandler !== 'undefined' && dragDropHandler)
					dragDropHandler.tooltip_active = true;
				return;
			}

			mouseArea.grabAndStartNativeDrag(pt.x, pt.y);
		}

		onPositionChanged: mouse => {
			if (typeof dragDropHandler === 'undefined')
				return;

			if (mouseArea.repositionDrag) {
				const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
				const fView = fileSlot.folderView;
				if (fView) {
					if (fView.repositionCursorOutsideWindow(pt.x, pt.y)) {
						// Hand the gesture over to the OS drag once it leaves the window.
						mouseArea.repositionDrag = false;
						fView.cancelRepositionDrag();
						dragDropHandler.reposition_active = false;
						mouseArea.grabAndStartNativeDrag(pt.x, pt.y);
						return;
					}
					fView.updateRepositionDrag(pt.x, pt.y);
				}
				return;
			}

			if (!mouseArea.dragStarted && mouseArea.dragAllowed && mouseArea.drag.active) {
				const deltaX = mouse.x - mouseArea.startX;
				const deltaY = mouse.y - mouseArea.startY;
				const distance = Math.sqrt(deltaX * deltaX + deltaY * deltaY);

				if (distance > 10) {
					mouseArea.initiateDragPayload(mouse);
				}
			}

			if (mouseArea.dragStarted) {
				const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
				dragDropHandler.track_mouse_shake(pt.x, pt.y);
			}
		}

		onPressed: mouse => {
			mouseArea.touchInput = mouse.source !== Qt.MouseEventNotSynthesized;

			if (mouse.button === Qt.LeftButton && fileSlot.pressHandler)
				fileSlot.pressHandler(mouse);

			if (mouse.button === Qt.LeftButton && typeof dragDropHandler !== 'undefined') {
				mouseArea.isPressAndHoldActive = false;
				mouseArea.dragInitiated = false;
				mouseArea.repositionDrag = false;

				mouseArea.startX = mouse.x;
				mouseArea.startY = mouse.y;
			}
		}

		onReleased: mouse => {
			mouseArea.isPressAndHoldActive = false;
			mouseArea.dragInitiated = false;

			if (mouseArea.repositionDrag) {
				const pt = mouseArea.mapToItem(null, mouse.x, mouse.y);
				const fView = fileSlot.folderView;
				if (fView)
					fView.endRepositionDrag(pt.x, pt.y);
				mouseArea.repositionDrag = false;
				if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
					dragDropHandler.active_dragged_paths = [];
					dragDropHandler.tooltip_active = false;
					dragDropHandler.reposition_active = false;
				}
				localDragTarget.Drag.active = false;
				mouseArea.dragStarted = false;
				return;
			}

			// Letting go of a drag that actually moved the item is the drop; a
			// drop onto another folder reports drag-accept itself, so only the
			// release back in place needs the sound here.
			if (mouseArea.dragStarted)
				fileSlot.playSound("drag-accept");

			if (typeof dragDropHandler !== 'undefined' && dragDropHandler) {
				dragDropHandler.active_dragged_paths = [];
				dragDropHandler.tooltip_active = false;
				dragDropHandler.end_drag();
			}
			localDragTarget.Drag.active = false;
			localDragTarget.Drag.imageSource = "";
			mouseArea.dragStarted = false;
		}

		onPressAndHold: {
			mouseArea.isPressAndHoldActive = true;
			fileSlot.pressHeld(fileSlot.path, fileSlot.index);
		}

		onClicked: mouse => {
			if (mouse.button === Qt.RightButton) {
				return;
			}
			if (mouse.button === Qt.MiddleButton) {
				if (fileSlot.actionManager)
					fileSlot.actionManager.openAction.execute(fileSlot.path, fileSlot, true);
				return;
			}

			if (fileSlot.selectionActive) {
				if (mouse.modifiers & Qt.ShiftModifier) {
					fileSlot.shiftSelected(fileSlot.index);
				} else {
					fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
				}
			} else if (mouse.modifiers & Qt.ControlModifier) {
				fileSlot.selectionToggled(fileSlot.path, fileSlot.index);
			} else if (fileSlot.clickHandler) {
				fileSlot.clickHandler(mouse);
			} else {
				fileSlot.activateOrFocus();
			}
		}
	}

	// Hovering an item reveals the text its label is not showing.
	ToolTip.visible: fileSlot.tooltipText !== "" && mouseArea.containsMouse && !fileSlot.isDraggingThisSlot && !(fileSlot.dragDropHandler && fileSlot.dragDropHandler.tooltip_active)
	ToolTip.text: fileSlot.tooltipText
	ToolTip.delay: 700
}
