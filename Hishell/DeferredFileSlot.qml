// A grid/list delegate that reserves its cell immediately and builds the real
// FileSlot only when the view's fill timer reaches it.
//
// A folder now exposes its whole listing at once so the scroll geometry is
// final while the cursor is placed on entry. Building a full FileSlot for every
// visible item in that reset still stalls the frame (the root carries several
// bindings and decoration loaders even before its content exists). This host
// is just an Item with the model roles, so the reset creates cheap empty slots;
// the grid then fills them in under a per-frame budget.

import QtQuick
import Hishell

Item {
	id: host

	required property string path
	required property string icon
	required property string title
	required property string comment
	required property real size_bytes
	required property real modified_time
	required property real created_time
	required property real accessed_time
	required property bool is_symlink
	required property int index
	required property bool is_directory
	required property bool icon_ready
	required property int control_kind
	required property bool toggle_on
	required property string number_value

	// FileSlot-compatible name: FolderView's free-placement drop target test
	// asks the live delegate whether it is a folder.
	readonly property bool is_dir: is_directory

	property bool populateReady: false
	// The view owns this host's x/y, so animating those writes is what turns a
	// pane resize, a GridSize/Lines change or a refresh reflow into icons
	// moving to their new cells instead of snapping. Enabled by the owning
	// grid (SmoothScrolling); see FolderGrid.layoutAnimating.
	property bool layoutAnimating: false
	property int gridSize: 72
	property bool listMode: false
	property var listColumns: []
	property int listIconSize: 24
	property bool labelBesideIcon: false
	property bool labelShowsFilename: false
	property bool showLabels: true
	property bool selectionActive: false
	property bool isSelected: false
	property bool isActive: false
	property bool radioMember: true
	// Copied from the view's config; see FileSlot's radioGroupEnabled.
	property bool radioGroupEnabled: false
	property int radioGroupOnly: 0
	property string radioGroupSelected: ""
	property bool freePlacementEnabled: false
	property bool openOnClickEnabled: true
	property var selectionManager: null
	property var actionManager: null
	property var fileManager: null
	property var dragDropHandler: null

	signal selectionToggled(string path, int idx)
	signal shiftSelected(int idx)
	signal pressHeld(string path, int idx)
	signal contextMenuRequested(string path, int idx)

	// The icon the slot actually paints, including the theme recolour and any
	// thumbnail. The folder transition uses it to grow a folder out of its
	// icon; before the slot is built it falls back to the model's icon role.
	readonly property string displayIcon: slotLoader.item ? String(slotLoader.item.displayIcon) : icon
	// The same surface a FileSlot offers to FolderView/ActionManager. They use
	// it for launch grabs, suspended marks and the free-placement hand-off.
	readonly property var contentLayout: slotLoader.item ? slotLoader.item.contentLayout : null
	readonly property var contentBody: slotLoader.item ? slotLoader.item.contentBody : null
	readonly property var dragGrabItem: slotLoader.item ? slotLoader.item.dragGrabItem : null

	function openContextMenu() {
		return slotLoader.item ? slotLoader.item.openContextMenu() : null;
	}

	function handOffRepositionDrag(x, y, onStarted) {
		if (slotLoader.item && typeof slotLoader.item.handOffRepositionDrag === "function")
			slotLoader.item.handOffRepositionDrag(x, y, onStarted);
		else if (onStarted)
			onStarted();
	}

	// The first placement is not a move: the view creates the host, then writes
	// its cell position. Animating that write would make every lazily built
	// slot fly in from the top-left, so the behavior stays off until one event
	// loop turn has passed and the initial position has settled.
	property bool positionSettled: false

	Component.onCompleted: {
		Qt.callLater(() => host.positionSettled = true);
		if (host.fileManager && host.fileManager.perf_mode() > 0)
			host.fileManager.perf_log("host+ " + Date.now());
	}

	Behavior on x {
		enabled: host.layoutAnimating && host.positionSettled
		NumberAnimation {
			duration: 200
			easing.type: Easing.OutCubic
		}
	}

	Behavior on y {
		enabled: host.layoutAnimating && host.positionSettled
		NumberAnimation {
			duration: 200
			easing.type: Easing.OutCubic
		}
	}

	Loader {
		id: slotLoader
		anchors.fill: parent
		active: host.populateReady
		sourceComponent: slotComponent
	}

	Component {
		id: slotComponent
		FileSlot {
			path: host.path
			icon: host.icon
			title: host.title
			comment: host.comment
			size_bytes: host.size_bytes
			modified_time: host.modified_time
			created_time: host.created_time
			accessed_time: host.accessed_time
			is_symlink: host.is_symlink
			index: host.index
			is_directory: host.is_directory
			iconReady: host.icon_ready
			control_kind: host.control_kind
			toggle_on: host.toggle_on
			number_value: host.number_value
			gridSize: host.gridSize
			listMode: host.listMode
			listColumns: host.listColumns
			listIconSize: host.listIconSize
			labelBesideIcon: host.labelBesideIcon
			labelShowsFilename: host.labelShowsFilename
			showLabels: host.showLabels
			selectionActive: host.selectionActive
			isSelected: host.isSelected
			isActive: host.isActive
			radioMember: host.radioMember
			radioGroupEnabled: host.radioGroupEnabled
			radioGroupOnly: host.radioGroupOnly
			radioGroupSelected: host.radioGroupSelected
			freePlacementEnabled: host.freePlacementEnabled
			openOnClickEnabled: host.openOnClickEnabled
			actionManager: host.actionManager
			fileManager: host.fileManager
			dragDropHandler: host.dragDropHandler

			onSelectionToggled: (p, idx) => host.selectionToggled(p, idx)
			onShiftSelected: idx => host.shiftSelected(idx)
			onPressHeld: (p, idx) => host.pressHeld(p, idx)
			onContextMenuRequested: (p, idx) => host.contextMenuRequested(p, idx)
		}
	}
}
