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
	required property real size_bytes
	required property real modified_time
	required property real created_time
	required property real accessed_time
	required property bool is_symlink
	required property int index
	required property bool is_directory
	required property int control_kind
	required property bool toggle_on
	required property string number_value

	// FileSlot-compatible name: FolderView's free-placement drop target test
	// asks the live delegate whether it is a folder.
	readonly property bool is_dir: is_directory

	property bool populateReady: false
	property int gridSize: 64
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
	property var selectionManager: null
	property var actionManager: null
	property var fileManager: null
	property var dragDropHandler: null

	signal selectionToggled(string path, int idx)
	signal shiftSelected(int idx)
	signal pressHeld(string path, int idx)
	signal contextMenuRequested(string path, int idx)

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
			size_bytes: host.size_bytes
			modified_time: host.modified_time
			created_time: host.created_time
			accessed_time: host.accessed_time
			is_symlink: host.is_symlink
			index: host.index
			is_directory: host.is_directory
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
