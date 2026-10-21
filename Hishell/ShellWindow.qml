import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell
import Hishell.toolkit
import ClamOS.Theme

Kirigami.ApplicationWindow {
	id: root
	width: 800
	height: 600
	visible: false

	flags: directory.config.native_titlebar ? Qt.Window : Qt.Window | Qt.FramelessWindowHint

	// Selection state lives in the folder views; this points at the manager of
	// the view that last took focus so the window actions operate on it.
	property SelectionManager selectionManager: null
	// The pane that follows the window's own folder; it owns the keyboard
	// whenever nothing else does, so typing filters the window's folder.
	property Item primaryFolderView: null
	// The location bar shown in the window's layout, if any; the edit location
	// action swaps it for a text box.
	property Item pathBar: null
	// The view owning the pane cursor and the view owning the selection; the
	// item actions fall back to the cursor so a focused item can be trashed,
	// copied and so on like a selected one.
	property Item focusedFolderView: null
	property Item selectionFolderView: null
	property alias focusManager: focusManager
	property alias dragDropHandler: dragDropHandler
	property alias dropValidator: dropValidator
	property alias fileManager: fileManager
	property alias directory: directory
	property alias actionManager: actionManager
	property alias sound: sound

	// A native (Wayland) drag runs QDrag::exec() in a nested event loop on this
	// thread, and Qt makes the QDrag a child of the dragged item's Drag object.
	// Reloading a view from inside the drop handler would delete that item (and
	// its QDrag) while the platform still owns them, crashing in
	// QWaylandDrag::finishDrag. So a drop only records the directories that
	// changed; they are reloaded once the drag has fully finished.
	property var pendingDirectoryReloads: []
	property bool internalDragInProcess: false

	// The dragged item's picture, drawn under the cursor. Wayland drag icons do
	// not render on this device (the grabbed pixmap never reaches
	// QWaylandDrag), so the shell draws the ghost itself.
	property string nativeDragImageUri: ""
	property real nativeDragImageWidth: 0
	property real nativeDragImageHeight: 0

	function requestDirectoryReload(dir) {
		if (!dir)
			return;
		if (pendingDirectoryReloads.indexOf(dir) === -1)
			pendingDirectoryReloads.push(dir);
		// An in-process drag finishes with Drag.dragFinished, which flushes the
		// queue. An external drop has no such loop, so reload on the next turn.
		if (!internalDragInProcess)
			Qt.callLater(flushDirectoryReloads);
	}

	function flushDirectoryReloads() {
		const dirs = pendingDirectoryReloads;
		pendingDirectoryReloads = [];
		for (let i = 0; i < dirs.length; ++i)
			if (dirs[i])
				dirs[i].reload();
	}

	// Follow the active theme's icon theme (e.g. breeze-dark for a dark
	// theme) at runtime, without restarting the shell.
	Connections {
		target: ClamTheme
		function onIconThemeChanged() {
			if (ClamTheme.iconTheme !== "" && root.fileManager)
				root.fileManager.set_icon_theme(ClamTheme.iconTheme);
		}
	}

	WindowOverlay {
		enabled: !directory.config.native_titlebar
	}

	Directory {
		id: directory
	}

	Connections {
		target: directory

		// Navigation (and the initial path) re-points the window icon at the
		// folder being viewed.
		function onPathChanged() {
			Qt.callLater(() => root.refreshWindowIcon());
		}
	}

	// A config change can set (or clear) the folder's custom icon, so the window
	// icon follows it.
	Connections {
		target: directory.config
		function onConfig_changed() {
			Qt.callLater(() => root.refreshWindowIcon());
			root.applyConfiguredScreen();
		}
	}

	// ClamOS guest handover: the app manager suspends the shell with a marker
	// file, this window washes to white and holds it while the app boots
	// underneath, then — once the manager has revealed the app — switches to
	// black and finally unmaps so the app takes the panel. The white marks "the
	// app is starting"; the black marks "the panel is about to be handed over",
	// so an app that only uses one screen does not snap from white to nothing.
	// Without the manager none of the markers ever exist and this stays inert.
	Connections {
		target: focusManager
		function onSuspendedChanged() {
			root.visible = !focusManager.hidden;
			if (focusManager.suspended) {
				// A new launch is starting: drop any lingering return frame at
				// once, so the wash fades from the shell rather than the last
				// app's own frame showing through it.
				returnFade.stop();
				returnFrame.opacity = 0;
			} else if (!focusManager.hidden && String(focusManager.return_frame_url) !== "") {
				// Coming back from an app: start from the app's last bottom
				// frame (identical pixels) and fade its UI in, so the panel
				// never jumps.
				returnFrame.opacity = 1;
				returnFade.restart();
			}
		}
	}

	// The guest's last bottom frame, shown for the first frames of a return.
	Image {
		id: returnFrame
		anchors.fill: parent
		z: 999
		visible: opacity > 0
		source: focusManager.return_frame_url
		fillMode: Image.PreserveAspectCrop
		asynchronous: false
		opacity: 0

		NumberAnimation {
			id: returnFade
			target: returnFrame
			property: "opacity"
			to: 0
			duration: 350
			easing.type: Easing.OutQuad
		}
	}

	// The launch transition: white while the app boots (and holds it), then a
	// fade out to black once the app is on screen, and finally unmap. White says
	// "starting"; the black starts over the app (which is already painted
	// underneath), so an app that only uses one screen leaves this panel fading
	// to nothing rather than snapping. `holdUp` keeps the window mapped until
	// the fade has played.
	Rectangle {
		id: launchWash
		anchors.fill: parent
		z: 1000
		visible: opacity > 0
		property bool holdUp: false
		opacity: (focusManager.suspended || holdUp) ? 1 : 0
		color: holdUp ? "#000000" : "#ffffff"
		Behavior on color {
			ColorAnimation { duration: 500; easing.type: Easing.InOutQuad }
		}
		Behavior on opacity {
			NumberAnimation { duration: 400; easing.type: Easing.InQuad }
		}
		// The wash also eats input: nothing under it should react while the
		// app is taking over.
		MouseArea {
			anchors.fill: parent
		}
	}

	// Unmaps the window once the launch fade has played, so the black is seen.
	Timer {
		id: unmapTimer
		interval: 700
		onTriggered: {
			launchWash.holdUp = false
			root.visible = !focusManager.hidden;
		}
	}

	// Open on a named screen/output when the config asks for one. The RG DS Plus
	// wants its bottom touch panel, which weston exposes as the second output
	// ("DSI-2"); the default would be the first output (the top panel).
	//
	// This resolves the *name* of the wanted screen and nothing else, because
	// the order in which it is applied matters (see `onCompleted`): the window
	// must be visible before the screen can be chosen, or the platform places
	// it and re-resolves `screen` back to the compositor's default.
	function applyConfiguredScreen() {
		// `String(...)` because a property coming from the host's type registry
		// may arrive as a wrapped value rather than a JS string.
		return String(directory.config.screen_name);
	}

	// Move the window onto the named screen, if it exists.
	function setScreen(name) {
		if (!name || name.length === 0)
			return;
		const screens = Qt.application.screens;
		for (let i = 0; i < screens.length; ++i) {
			if (String(screens[i].name) === name) {
				root.screen = screens[i];
				return;
			}
		}
	}

	FileManager {
		id: fileManager
	}

	DragDropHandler {
		id: dragDropHandler
	}

	DropValidator {
		id: dropValidator
	}

	FocusManager {
		id: focusManager
		window: root
	}

	// Event sounds. ClamOS ships an XDG sound theme; this object is the only
	// path the UI uses to play one, so volumes and the enabled setting live in
	// one place. See ClamOS tools/make-sound-theme.sh for the theme.
	Sound {
		id: sound
		window: root
		enabled: true
	}

	Timer {
		interval: 90
		running: true
		repeat: true
		onTriggered: focusManager.poll_gamepad()
	}

	// A folder may resolve to a thumbnail (an image-backed directory) rather than
	// a themed icon; poll so the window icon catches up once it is generated.
	Timer {
		id: windowIconTimer
		interval: 1000
		running: true
		repeat: true
		onTriggered: root.refreshWindowIcon()
	}

	// The window (top level) icon mirrors the directory being viewed.
	function refreshWindowIcon() {
		if (!directory || directory.path === "")
			return;
		directory.apply_window_icon();
	}

	ActionManager {
		id: actionManager
		window: root
		directory: directory
		fileManager: fileManager
	}

	// A launch the execution wrapper held back for confirmation (e.g. it would
	// close a suspended app) is shown here, naming the apps involved.
	LaunchConfirmDialog {
		id: launchConfirm
		fileManager: root.fileManager
		window: root
	}

	function requestLaunchConfirm(blockedItem, launchItem) {
		launchConfirm.ask(blockedItem, launchItem);
	}

	// Drop the return frame from a previous app immediately, so a launch that
	// starts right after a quit does not show that app's frame through the white
	// wash. Called by the launch sites as the launch begins.
	function clearReturnFrame() {
		returnFade.stop();
		returnFrame.opacity = 0;
	}

	DragTooltip {
		active: dragDropHandler.tooltip_active
		action: dragDropHandler.drag_action
		reposition: dragDropHandler.reposition_active
		cursorX: dragDropHandler.drag_cursor_x
		cursorY: dragDropHandler.drag_cursor_y
	}

	DragPreview {
		previewActive: dragDropHandler.reposition_active && !!dragDropHandler.reposition_preview
		cursorX: dragDropHandler.drag_cursor_x
		cursorY: dragDropHandler.drag_cursor_y
		previewData: dragDropHandler.reposition_preview
		fileManager: root.fileManager
	}

	// Ghost of the dragged item, following the finger for the whole OS drag.
	Image {
		id: nativeDragGhost
		source: root.nativeDragImageUri
		width: root.nativeDragImageWidth
		height: root.nativeDragImageHeight
		x: dragDropHandler ? dragDropHandler.drag_cursor_x - width / 2 : 0
		y: dragDropHandler ? dragDropHandler.drag_cursor_y - height / 2 : 0
		// The shell's ghost stands in for the compositor's drag icon, so it is
		// shown unless the folder asks for the native one.
		visible: root.internalDragInProcess && source != "" && root.nativeDragImageWidth > 0
			&& (!root.directory || !root.directory.config || !root.directory.config.native_drag)
		opacity: 0.9
		z: 9997
		enabled: false
		fillMode: Image.PreserveAspectFit
	}

	// The source object of a native (Wayland) drag. It is deliberately a
	// long-lived item rather than the dragged slot: Qt parents the QDrag (and
	// its Drag object) to the drag source item, so if that item lives in a
	// folder view, navigating the view mid-drag — spring loading, or a drop
	// that refreshes the folder — frees the QDrag the platform still owns and
	// crashes in QWaylandDrag::finishDrag. Keeping the source here lets the
	// views reload freely while a drag is in flight.
	Item {
		id: nativeDragSource
		x: dragDropHandler ? dragDropHandler.drag_cursor_x : 0
		y: dragDropHandler ? dragDropHandler.drag_cursor_y : 0
		width: 1
		height: 1

		Drag.dragType: Drag.Automatic
		Drag.active: false
		Drag.keys: ["text/uri-list", "text/plain"]
		Drag.supportedActions: Qt.CopyAction | Qt.MoveAction
		Drag.proposedAction: Qt.MoveAction

		// Emitted only after QDrag::exec() has returned, so any reload a drop
		// handler queued can now remove items safely.
		Drag.onDragFinished: {
			root.internalDragInProcess = false;
			root.nativeDragImageUri = "";
			// The dragged slot never sees the release (the platform owns the
			// drag), so clear the drag state that dims it and drives the tooltip.
			if (dragDropHandler)
				dragDropHandler.end_drag();
			Qt.callLater(root.flushDirectoryReloads);
		}
	}

	// Start a native drag from the persistent source, using the payload the
	// dragged slot filled in through the DragDropHandler.
	function startNativeDrag(imageUrl, width, height) {
		nativeDragSource.Drag.mimeData = {
			"text/uri-list": dragDropHandler ? dragDropHandler.drag_uris.join("\n") : ""
		};
		nativeDragSource.Drag.imageSource = imageUrl;
		nativeDragSource.Drag.hotSpot = Qt.point(Math.round(width / 2), Math.round(height / 2));
		root.nativeDragImageUri = imageUrl;
		root.nativeDragImageWidth = width;
		root.nativeDragImageHeight = height;
		nativeDragSource.Drag.active = true;
	}

	// Load the drag image while the finger is held, so the pixmap is ready when
	// the OS drag starts (otherwise the drag has no icon: QDrag::exec() reads the
	// pixmap in the same turn the image URL is set).
	function preloadDragImage(imageUrl) {
		nativeDragSource.Drag.imageSource = imageUrl;
	}

	Component.onCompleted: {
		directory.config.load(initialPath);
		directory.path = initialPath;
		root.refreshWindowIcon();

		// Pick up the active theme's icon theme on first start; later changes
		// arrive through the ClamTheme Connections above.
		if (ClamTheme.iconTheme !== "" && root.fileManager)
			root.fileManager.set_icon_theme(ClamTheme.iconTheme);

		// Show first, then choose the output, then go fullscreen.
		//
		// This order is load-bearing. Showing a window makes the platform place
		// it and *re-resolve* `screen` to whatever the compositor chose, so a
		// screen set before the window is visible is thrown away. And weston
		// pins a surface to its output at fullscreen time, ignoring later
		// moves — so the output must already be chosen when fullscreen is set.
		const wantScreen = root.applyConfiguredScreen();
		root.visible = true;
		root.setScreen(wantScreen);
		if (directory.config.maximized)
			root.visibility = Window.FullScreen;
	}

	// Which output the file manager actually landed on (DSI-2 expected).
	onScreenChanged: console.log("file manager: output", String(root.screen.name))

	// Whenever the keyboard is left unclaimed, hand it back to the window's own
	// pane. Deferred so Qt has settled focus after (de)activation.
	onActiveChanged: Qt.callLater(() => root.ensureFolderViewFocus())
	onActiveFocusItemChanged: Qt.callLater(() => root.ensureFolderViewFocus())

	function ensureFolderViewFocus() {
		if (!root.active || !root.primaryFolderView)
			return;
		// The page itself holds focus when nothing else does; a file view or
		// anything the user focused deliberately is left alone.
		const item = root.activeFocusItem;
		if (item && item !== root.pageStack.currentItem)
			return;
		root.primaryFolderView.forceActiveFocus();
	}

	menuBar: MenuBar {
		// The bar sits outside the content item, so the launch wash cannot
		// paint over it; hide it while the wash covers the window.
		visible: directory.config.native_menubar && !focusManager.suspended

		window: root
		directory: root.directory
	}

	pageStack.initialPage: Kirigami.Page {
		padding: 0
		topPadding: 0
		leftPadding: 0
		rightPadding: 0
		bottomPadding: 0

		globalToolBarStyle: Kirigami.ApplicationHeaderStyle.Breadcrumb

		ColumnLayout {
			anchors.fill: parent
			spacing: 0

			// Header bar
			Kirigami.AbstractApplicationHeader {
				Layout.fillWidth: true
				Kirigami.Theme.colorSet: Kirigami.Theme.Header

				// The bar height is a Clam theme metric; the header content
				// (breadcrumb, view button, window control) keeps its own size
				// and stays vertically centred inside the taller strip.
				minimumHeight: ClamTheme.headerHeight
				preferredHeight: ClamTheme.headerHeight
				maximumHeight: ClamTheme.headerHeight

				z: 1

				Rectangle {
					anchors.fill: parent
					z: -1
					color: Kirigami.Theme.backgroundColor
				}

				RowLayout {
					anchors.fill: parent

					Layout.fillWidth: true
					Layout.preferredHeight: 44
					Layout.margins: 0
					spacing: Kirigami.Units.smallSpacing

					// Make it draggable
					DragHandler {
						target: null
						onActiveChanged: if (active)
							root.startSystemMove()
					}

					LayoutEngine {
						id: headerLayoutEngine
						directory: directory
						window: root
						layoutString: String(directory.config.header_layout || "[]")
						Layout.fillWidth: true
					}
				}
			}

			// Folder config load error banner
			Rectangle {
				id: configErrorBanner
				property string dismissedError: ""

				visible: directory.config.error.length > 0 && directory.config.error !== configErrorBanner.dismissedError
				Layout.fillWidth: true
				Layout.preferredHeight: configErrorRow.implicitHeight + Kirigami.Units.largeSpacing * 2
				color: Kirigami.Theme.negativeBackgroundColor

				RowLayout {
					id: configErrorRow
					anchors.horizontalCenter: parent.horizontalCenter
					anchors.verticalCenter: parent.verticalCenter
					width: parent.width - Kirigami.Units.largeSpacing * 2
					spacing: Kirigami.Units.largeSpacing

					Label {
						Layout.fillWidth: true
						text: directory.config.error
						color: Kirigami.Theme.negativeTextColor
						wrapMode: Text.WordWrap
					}

					Button {
						visible: directory.config.error_file.length > 0
						text: "Open Config"
						onClicked: {
							const warning = String(fileManager.open_file(directory.config.error_file));
							if (warning !== "")
								root.requestLaunchConfirm(warning, directory.config.error_file);
						}
					}

					ToolButton {
						icon.name: "dialog-close"
						onClicked: configErrorBanner.dismissedError = directory.config.error
					}
				}
			}

			// Top Layout area
			LayoutEngine {
				id: topLayoutEngine
				directory: directory
				window: root
				layoutString: String(directory.config.top_layout || "[]")
				Layout.fillWidth: true
			}

			// Main content area
			RowLayout {
				Layout.fillWidth: true
				Layout.fillHeight: true
				spacing: 0

				LayoutEngine {
					id: middleLayoutEngine
					directory: directory
					window: root
					layoutString: String(directory.config.middle_layout || "[]")
					Layout.fillHeight: true
					Layout.fillWidth: true
				}
			}

			// Bottom Layout area
			LayoutEngine {
				id: bottomLayoutEngine
				directory: directory
				window: root
				layoutString: String(directory.config.bottom_layout || "[]")
				Layout.fillWidth: true
			}
		}
	}
}
