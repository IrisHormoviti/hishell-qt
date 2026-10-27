pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: folderView
	// Untyped to avoid the ShellWindow <-> FolderView cyclic dependency; see
	// ActionManager.qml for the explanation.
	property var window
	readonly property var rootWindow: folderView.window

	// Event sounds (ClamOS XDG sound theme). Played through the window's sound
	// object; a null window (or a missing theme) simply stays silent.
	function playSound(name) {
		if (folderView.rootWindow && folderView.rootWindow.sound)
			folderView.rootWindow.sound.play(name);
	}

	// The path the focus sound last played for, so moving the cursor within one
	// item does not retrigger it.
	property string lastFocusSoundPath: ""
	property double lastFocusSoundTime: 0
	// Set while a selection gesture moves the cursor. The gesture owns its
	// item-selected sound; the focus sound underneath it would make one tap
	// sound twice.
	property bool suppressFocusSound: false
	// Set while a folder is being entered. The viewport is placed directly at
	// its target instead of being animated there, and the programmatic move
	// stays silent. Cleared on the first real input or shortly afterwards.
	property bool entryScrollReset: false
	property bool entryScanPending: false

	function endEntry() {
		folderView.entryScrollReset = false;
		folderView.suppressFocusScroll = false;
		folderView.suppressFocusSound = false;
		entrySettleTimer.stop();
	}

	function resetEntryViewport() {
		folderView.entryScrollReset = true;
		folderView.suppressFocusScroll = true;
		folderView.suppressFocusSound = true;
		const flick = folderView.flickable;
		if (flick) {
			if (flick.cancelFlick)
				flick.cancelFlick();
			flick.contentY = 0;
			flick.contentX = 0;
			folderView.lastViewMoveTime = Date.now();
			grid.lastScrollX = flick.contentX;
			grid.lastScrollY = flick.contentY;
			grid.scrollRemainderX = 0;
			grid.scrollRemainderY = 0;
			grid.updateScrollEdges(false);
		}
		entrySettleTimer.restart();
	}

	Timer {
		id: entrySettleTimer
		interval: 400
		repeat: false
		onTriggered: folderView.endEntry()
	}

	property Directory directory
	property Config config: directory ? directory.config : null
	readonly property bool horizontalScroll: folderView.config ? folderView.config.scroll_horizontal : false
	readonly property bool filterActive: folderView.directory ? String(folderView.directory.filter).length > 0 : false
	// Free placement can leave empty cells, and FocusEmptySlots lets the cursor
	// rest on one. Empty cells exist nowhere else.
	readonly property bool focusEmptySlots: folderView.config
		? (folderView.config.focus_empty_slots && folderView.config.sort === 3 && folderView.config.view_mode === 0)
		: false
	// Set while the cursor is moved to follow a manual scroll, so the
	// focus-driven scroll does not fight the gesture.
	property bool suppressFocusScroll: false
	// Path a pointer click moved the cursor to. While the cursor stays there,
	// a focus change must not reveal it: the item is already under the finger,
	// and scrolling would move the grid out from under a quick second tap.
	property string suppressRevealPath: ""
	readonly property bool viewMoving: flickable.moving
	readonly property real viewContentY: flickable.contentY
	// When the viewport last moved (touch, fling or a focus animation). Idle
	// work such as rendering themed icons must not land in the middle of it.
	property double lastViewMoveTime: 0
	// True while the focus-driven scroll animation runs, so the scroll-follow
	// logic can ignore the motion it causes.
	property bool focusScrollAnimating: false
	property FocusManager focusManager: folderView.rootWindow ? folderView.rootWindow.focusManager : null
	readonly property string focusBorderSource: folderView.focusManager ? folderView.focusManager.border_source(Kirigami.Theme.highlightColor.toString()) : ""
	property bool focusOwned: false
	// True for the pane that follows the window's own folder; that pane owns
	// the keyboard whenever nothing else does.
	property bool followsWindow: false
	property var openMenu: null
	property string returnFocusPath: ""
	property string lastPath: ""
	// Per-pane navigation history. Opening a folder appends; Back/Forward move
	// the index and suppress recording for the path they restore.
	property var historyPaths: []
	property int historyIndex: -1
	property bool historyNavigating: false
	readonly property bool canGoBack: historyIndex > 0
	readonly property bool canGoForward: historyIndex >= 0 && historyIndex < historyPaths.length - 1
	property int paneId: -1
	property int paneCount: 1
	property SelectionManager selectionManager: selectionManagerImpl

	// Free-placement drop target (empty slot under the cursor during a
	// reposition drag). -1 means "no active target".
	property int freeDropCol: -1
	property int freeDropRow: -1

	// Directory under the cursor during a free-placement drag. After a short
	// hover the drop switches from repositioning to dropping into the folder.
	property bool folderDropActive: false
	property string folderDropPath: ""

	// Folder a spring-load navigation is armed for (free placement, where the
	// background owns drops). Hovering it long enough opens it.
	property string folderNavPath: ""

	// Custom in-window reposition drag: the selection is previewed and moved
	// directly instead of starting an OS drag-and-drop sequence.
	property bool repositionDragActive: false
	property bool repositionAnimating: false

	// Selection state is owned per view so selection mode and the selection
	// toolbar stay inside the pane instead of the whole window.
	SelectionManager {
		id: selectionManagerImpl
	}

	// The grid itself — layout maths, the view, scroll feedback, the focus border
	// and the visible-area thumbnails — lives in FolderGrid. These forward to it
	// so the rest of the view can keep reading them by name.
	readonly property bool labelsBesideIcons: grid.labelsBesideIcons
	readonly property size gridItemSize: grid.gridItemSize
	readonly property var gridMetrics: grid.gridMetrics
	readonly property int gridStride: grid.gridStride
	readonly property bool freeDropActive: grid.freeDropActive
	readonly property real freeDropX: grid.freeDropX
	readonly property real freeDropY: grid.freeDropY
	readonly property var flickable: grid.flickable
	readonly property var gridContent: grid.gridContent

	function gridSlotX(index) {
		return grid.gridSlotX(index);
	}

	function gridSlotY(index) {
		return grid.gridSlotY(index);
	}

	function scheduleThumbnails() {
		grid.scheduleThumbnails();
	}

	function slotAt(index) {
		return grid.slotAt(index);
	}

	// Width the pane needs for its fixed grid block: the block, its scrollbar inset
	// and the view margins; -1 lets the pane take a fill share of the layout instead.
	readonly property real preferredGridWidth: {
		const cfg = folderView.config;
		if (!cfg || folderView.paneCount <= 1 || cfg.scroll_horizontal || cfg.view_mode === 1 || cfg.grid_lines <= 0 || cfg.grid_horizontal_align === 0)
			return -1;

		const size = folderView.gridItemSize;
		const gap = Kirigami.Units.mediumSpacing;
		const naturalWidth = cfg.grid_lines * size.width + (cfg.grid_lines - 1) * gap;
		const rows = Math.max(1, Math.ceil(grid.count / cfg.grid_lines));
		const naturalHeight = rows * size.height + (rows - 1) * gap;
		const scrollBar = naturalHeight > grid.flickable.height ? grid.verticalBarWidth + gap : 0;
		return naturalWidth + scrollBar + 2 * gap;
	}

	Layout.fillWidth: folderView.preferredGridWidth <= 0
	Layout.fillHeight: true
	Layout.preferredWidth: folderView.preferredGridWidth

	focus: true
	activeFocusOnTab: true

	Connections {
		target: folderView.Window.window
		function onActiveChanged() {
			const window = folderView.rootWindow;
			// The window hands the keyboard to its own pane when it comes back;
			// other panes only claim a keyboard nothing else took.
			if (window && window.active && !window.activeFocusItem && (folderView.followsWindow || !window.primaryFolderView))
				folderView.forceActiveFocus();
			folderView.updateViewFocus();
		}
		// A dialog or popup taking the focus (and giving it back) changes who
		// the controller drives; re-evaluate whenever it moves.
		function onActiveFocusItemChanged() {
			folderView.updateViewFocus();
		}
	}

	function updateViewFocus() {
		const fm = folderView.focusManager;
		const window = folderView.Window.window;
		if (!fm || folderView.paneId <= 0)
			return;
		// The controller drives the file views when this pane holds the focus,
		// or when the window is inactive (the compositor gives the app no focus
		// at all, but the controller still drives the views). When the window is
		// active and a sibling holds the focus — a popup, a dialog, the
		// launch-confirmation sheet — the keyboard goes to Qt so the controller
		// drives that popup instead.
		const inputToQt = window && window.active && !folderView.activeFocus;
		fm.set_pane_keyboard(folderView.paneId, !inputToQt);
	}

	// Panes are compared spatially so the focus can be moved between them.
	function updateGeometry() {
		const fm = folderView.focusManager;
		const window = folderView.Window.window;
		if (!fm || folderView.paneId <= 0 || !window || !window.contentItem)
			return;
		const position = folderView.mapToItem(window.contentItem, 0, 0);
		fm.set_pane_geometry(folderView.paneId, position.x, position.y, folderView.width, folderView.height);
	}

	onXChanged: folderView.updateGeometry()
	onYChanged: folderView.updateGeometry()
	onWidthChanged: folderView.updateGeometry()
	onHeightChanged: folderView.updateGeometry()

	function selectAll() {
		const mgr = folderView.selectionManager;
		if (!mgr || !folderView.directory)
			return;
		mgr.select_all(folderView.directory.get_all_paths());
	}



	function recordHistory(path) {
		if (path === "")
			return;
		if (folderView.historyIndex >= 0 && folderView.historyPaths[folderView.historyIndex] === path)
			return;
		const next = folderView.historyPaths.slice(0, folderView.historyIndex + 1);
		next.push(path);
		folderView.historyPaths = next;
		folderView.historyIndex = next.length - 1;
	}

	function goBack() {
		if (!folderView.canGoBack)
			return false;
		const target = folderView.historyPaths[folderView.historyIndex - 1];
		if (!target)
			return false;
		folderView.historyIndex -= 1;
		folderView.historyNavigating = true;
		folderView.directory.path = target;
		return true;
	}

	function goForward() {
		if (!folderView.canGoForward)
			return false;
		const target = folderView.historyPaths[folderView.historyIndex + 1];
		if (!target)
			return false;
		folderView.historyIndex += 1;
		folderView.historyNavigating = true;
		folderView.directory.path = target;
		return true;
	}

	function updateFocusItems() {
		const fm = folderView.focusManager;
		if (!fm || !folderView.directory || folderView.paneId <= 0)
			return;
		const paths = folderView.directory.get_all_paths();
		if (paths.length === 0) {
			fm.clear_pane(folderView.paneId);
			return;
		}
		fm.set_pane_horizontal(folderView.paneId, folderView.horizontalScroll);
		fm.set_pane_items(folderView.paneId, paths, folderView.gridStride);
		const metrics = folderView.gridMetrics;
		fm.set_pane_positions(folderView.paneId, (metrics.free || metrics.grouped) ? JSON.stringify(metrics.slots) : "");
		fm.set_pane_grid(folderView.paneId, metrics.columns, metrics.rows);
		fm.set_pane_empty_slots(folderView.paneId, folderView.focusEmptySlots);
		folderView.focusOwned = true;

		if (folderView.returnFocusPath !== "") {
			const target = folderView.returnFocusPath;
			folderView.returnFocusPath = "";
			if (fm.set_pane_focus_path(folderView.paneId, target))
				Qt.callLater(() => folderView.ensureFocusVisible());
		}
	}

	function ensureFocusVisible() {
		const fm = folderView.focusManager;
		if (!fm || !fm.focus_active || fm.current_pane !== folderView.paneId)
			return;

		const cfg = folderView.config;
		const metrics = folderView.gridMetrics;
		// The focused item, or the empty cell the cursor is resting on. The
		// geometry comes from the layout, not the delegate: with a lazy grid the
		// focused item may not be instantiated yet.
		let focusX, focusY, focusWidth, focusHeight;
		if (fm.focus_on_empty) {
			focusX = metrics.offsetX + fm.focused_column * (metrics.itemWidth + metrics.gap);
			focusY = metrics.offsetY + fm.focused_row * (metrics.itemHeight + metrics.gap);
			focusWidth = metrics.itemWidth;
			focusHeight = metrics.itemHeight;
		} else if (fm.focused_index >= 0) {
			focusX = grid.gridSlotX(fm.focused_index);
			focusY = grid.gridSlotY(fm.focused_index);
			focusWidth = metrics.itemWidth;
			focusHeight = metrics.itemHeight;
		} else {
			return;
		}

		const viewWidth = flickable.width - metrics.insetX;
		const viewHeight = flickable.height - metrics.insetY;
		// Before the view has been laid out there is nothing to scroll to, and a
		// centring computation against a zero viewport lands anywhere. Wait for a
		// real viewport; a later focus change (or the gridMetrics handler) will
		// bring the item into view.
		if (viewWidth <= 0 || viewHeight <= 0)
			return;
		let targetY = flickable.contentY;
		let targetX = flickable.contentX;

		// Centring is what the user asked for: the cursor stays in the middle of
		// the view instead of hugging an edge.
		const top = focusY;
		const bottom = focusY + focusHeight;
		const left = focusX;
		const right = focusX + focusWidth;
		const offTop = top < flickable.contentY;
		const offBottom = bottom > flickable.contentY + viewHeight;
		const offLeft = left < flickable.contentX;
		const offRight = right > flickable.contentX + viewWidth;

		if (cfg && cfg.center_focus) {
			// Keep the focused item in the middle of the view, always: that is
			// what this setting means here, and re-centring even a small step is
			// the behaviour the device expects.
			targetY = focusY + focusHeight / 2 - viewHeight / 2;
			targetX = focusX + focusWidth / 2 - viewWidth / 2;
		} else {
			if (offTop)
				targetY = top;
			else if (offBottom)
				targetY = bottom - viewHeight;

			if (offLeft)
				targetX = left;
			else if (offRight)
				targetX = right - viewWidth;
		}

		targetY = Math.max(0, Math.min(targetY, flickable.contentHeight - flickable.height));
		targetX = Math.max(0, Math.min(targetX, flickable.contentWidth - flickable.width));

		if (Math.abs(targetY - flickable.contentY) < 1 && Math.abs(targetX - flickable.contentX) < 1)
			return;

		if (folderView.entryScrollReset) {
			// The folder was just entered. Put the viewport at the target in one
			// step: animating it while the delegates fill in is what made the
			// screen chase the cursor during the open.
			focusScrollY.stop();
			focusScrollX.stop();
			flickable.contentY = targetY;
			flickable.contentX = targetX;
			folderView.lastViewMoveTime = Date.now();
			grid.lastScrollX = flickable.contentX;
			grid.lastScrollY = flickable.contentY;
			grid.scrollRemainderX = 0;
			grid.scrollRemainderY = 0;
			return;
		}

		if (cfg && cfg.smooth_scrolling) {
			// Mark the motion as focus-driven so the scroll-follow logic leaves
			// it alone while it runs.
			folderView.focusScrollAnimating = true;
			focusScrollY.to = targetY;
			focusScrollX.to = targetX;
			focusScrollY.restart();
			focusScrollX.restart();
		} else {
			focusScrollY.stop();
			focusScrollX.stop();
			flickable.contentY = targetY;
			flickable.contentX = targetX;
		}
	}

	function openFocused() {
		const fm = folderView.focusManager;
		if (!fm || !fm.focus_active || String(fm.focused_path) === "")
			return;
		if (folderView.rootWindow && folderView.rootWindow.actionManager)
			folderView.rootWindow.actionManager.activatePath(String(fm.focused_path), grid.slotAt(fm.focused_index));
	}

	// Called on every scroll position change. Restarted on each one, so the
	// cursor settles once the motion stops. Letting it fire every 60 ms during
	// a continuous flick moved the cursor (and wrote the focus file) in the
	// middle of the gesture, which was visible as a stutter.
	function scheduleFocusFollow() {
		focusFollowTimer.restart();
	}

	// Keeps the cursor on a fully visible item while the user scrolls, without
	// scrolling back: when the focused item is clipped by an edge, the cursor
	// moves to the visible item nearest the one it is leaving. The viewport is
	// the user's; the cursor follows it rather than fighting the gesture.
	function keepFocusInView() {
		const fm = folderView.focusManager;
		if (!fm || !fm.focus_active || fm.current_pane !== folderView.paneId || !folderView.focusOwned)
			return;
		// The viewport is being placed for a folder entry; that is not a user
		// scroll and must not move the cursor.
		if (folderView.entryScrollReset)
			return;
		// Ignore the motion a focus-driven scroll is itself producing.
		if (folderView.focusScrollAnimating)
			return;

		const metrics = folderView.gridMetrics;
		const flick = flickable;
		// The visible area, not the whole Flickable: the scrollbar hides a strip
		// of it, and an item under the bar is not usable.
		const viewWidth = flick.width - metrics.insetX;
		const viewHeight = flick.height - metrics.insetY;
		if (viewWidth <= 0 || viewHeight <= 0)
			return;

		// Geometry from the layout, not the delegate: with a lazy grid the
		// focused item may not be instantiated.
		let focusX, focusY, focusWidth, focusHeight;
		if (fm.focus_on_empty) {
			focusX = metrics.offsetX + fm.focused_column * (metrics.itemWidth + metrics.gap);
			focusY = metrics.offsetY + fm.focused_row * (metrics.itemHeight + metrics.gap);
			focusWidth = metrics.itemWidth;
			focusHeight = metrics.itemHeight;
		} else if (fm.focused_index >= 0) {
			focusX = grid.gridSlotX(fm.focused_index);
			focusY = grid.gridSlotY(fm.focused_index);
			focusWidth = metrics.itemWidth;
			focusHeight = metrics.itemHeight;
		} else {
			return;
		}

		const left = flick.contentX;
		const top = flick.contentY;
		const right = left + viewWidth;
		const bottom = top + viewHeight;

		// A partly clipped item is as unusable as one entirely out of view, so
		// crossing an edge is what moves the cursor.
		if (focusX >= left && focusX + focusWidth <= right
			&& focusY >= top && focusY + focusHeight <= bottom)
			return;

		const focusCentreX = focusX + focusWidth / 2;
		const focusCentreY = focusY + focusHeight / 2;

		// The nearest fully visible item, by centre distance. Laid out items only:
		// an index is an item, and only the visible ones have delegates.
		let best = -1;
		let bestDistance = Infinity;
		const count = grid.count;
		for (let i = 0; i < count; i++) {
			const x = grid.gridSlotX(i);
			const y = grid.gridSlotY(i);
			if (x < left || x + metrics.itemWidth > right)
				continue;
			if (y < top || y + metrics.itemHeight > bottom)
				continue;
			const dx = x + metrics.itemWidth / 2 - focusCentreX;
			const dy = y + metrics.itemHeight / 2 - focusCentreY;
			const distance = dx * dx + dy * dy;
			if (distance < bestDistance) {
				bestDistance = distance;
				best = i;
			}
		}

		if (best < 0 || best === fm.focused_index)
			return;
		const item = grid.slotAt(best);
		if (!item || !item.path)
			return;

		// The new item is fully visible already, so the focus-driven reveal must
		// not scroll the viewport back.
		folderView.suppressFocusScroll = true;
		fm.set_pane_focus_path(folderView.paneId, item.path);
		folderView.suppressFocusScroll = false;
	}

	Timer {
		id: focusFollowTimer
		interval: 60
		repeat: false
		onTriggered: folderView.keepFocusInView()
	}

	// Publish the focused item for the top screen after the cursor settles.
	// The title/icon lookup and the tiny-file write are not needed on every
	// step of a held direction; the top screen polls at 200 ms regardless.
	Timer {
		id: topScreenFocusTimer
		interval: 60
		repeat: false
		onTriggered: {
			const fm = folderView.focusManager;
			if (fm)
				fm.publish_focus_now();
		}
	}

	// Persist the cursor after it settles. Saving on every step wrote the
	// session file from the GUI thread on every key press.
	Timer {
		id: saveFocusTimer
		interval: 250
		repeat: false
		onTriggered: if (folderView.focusManager)
			folderView.focusManager.persist_focus()
	}

	// Enter / gamepad accept: toggle the focused item in selection mode, otherwise open it
	function activateFocused() {
		const fm = folderView.focusManager;
		const mgr = folderView.selectionManager;
		if (!fm || !fm.focus_active || String(fm.focused_path) === "")
			return;
		if (mgr && mgr.selection_active) {
			folderView.playSound("item-selected");
			mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
			return;
		}
		folderView.openFocused();
	}

	// OpenOnClick off: a click moves the cursor to the item instead of opening
	// it. The view has to own the keyboard first (which registers/activates the
	// pane), then the pane's focus can be pointed at the clicked item.
	function focusSlot(path, reveal) {
		folderView.endEntry();
		const fm = folderView.focusManager;
		if (!fm || !folderView.directory)
			return;
		// A click puts the cursor on an item the user can already see. Scrolling
		// to it would move the grid before a quick second tap lands, so only
		// keyboard and startup focus ask for a reveal.
		const show = reveal !== false;
		if (!show)
			folderView.suppressRevealPath = path;
		folderView.forceActiveFocus();
		if (folderView.paneId <= 0) {
			folderView.suppressRevealPath = "";
			return;
		}
		folderView.updateFocusItems();
		const found = fm.set_pane_focus_path(folderView.paneId, path);
		if (!found)
			folderView.suppressRevealPath = "";
		if (found && show)
			Qt.callLater(() => folderView.ensureFocusVisible());
	}

	// Move the cursor as part of a selection gesture. The gesture plays its own
	// item-selected sound, so the focus change it causes must not add the focus
	// sound on top.
	function focusSlotForSelection(path) {
		folderView.suppressFocusSound = true;
		folderView.focusSlot(path, false);
		folderView.suppressFocusSound = false;
	}

	// Context menu for the focused item, shared by the gamepad menu button and
	// the Menu key.
	function openFocusedMenu() {
		const fm = folderView.focusManager;
		if (!folderView.focusOwned || !fm || !fm.focus_active || fm.current_pane !== folderView.paneId)
			return;
		// An empty slot is part of the folder's background, so its menu is the
		// folder view's own menu.
		if (fm.focus_on_empty) {
			folderView.openDirectoryMenu();
			return;
		}
		const item = grid.slotAt(fm.focused_index);
		if (item)
			folderView.openMenu = item.openContextMenu();
	}

	// Context menu for the folder being viewed, opened by the gamepad start
	// button.
	function openDirectoryMenu() {
		if (folderView.rootWindow)
			folderView.rootWindow.actionManager.pasteTargetPath = "";
		directoryMenuLoader.active = true;
		const menu = directoryMenuLoader.item;
		if (!menu)
			return;
		menu.parent = folderView;
		const position = folderView.mapToItem(menu.parent, 0, 0);
		menu.x = position.x;
		menu.y = position.y;
		menu.open();
		folderView.openMenu = menu;
	}

	Component.onCompleted: {
		Qt.callLater(() => {
			const window = folderView.Window.window;
			if (folderView.focusManager)
				folderView.paneId = folderView.focusManager.register_pane();
			if (folderView.followsWindow && folderView.rootWindow)
				folderView.rootWindow.primaryFolderView = folderView;
			// The layout creates one view after another; the view that follows
			// the window's folder takes the keyboard, the rest leave it alone
			// unless nothing claimed it. Activating the pane first keeps a
			// sibling that still counts as current from taking it back.
			const claim = folderView.followsWindow || !window || !window.activeFocusItem;
			if (claim && folderView.focusManager && folderView.paneId > 0)
				folderView.focusManager.activate_pane(folderView.paneId);
			if (claim)
				folderView.forceActiveFocus();
			folderView.updateViewFocus();
			folderView.updateGeometry();
			if (folderView.config && folderView.directory) {
				// The directory has already scanned its folder when the path was
				// set; only the initial view state is set up here.
				folderView.lastPath = String(folderView.directory.path);
				folderView.recordHistory(folderView.lastPath);
				folderView.updateFocusItems();
			} else {
				console.error("FolderView: missing directory or config.");
			}
		});
	}

	Component.onDestruction: {
		if (folderView.rootWindow && folderView.rootWindow.selectionManager === folderView.selectionManager)
			folderView.rootWindow.selectionManager = null;
		if (folderView.rootWindow && folderView.rootWindow.primaryFolderView === folderView)
			folderView.rootWindow.primaryFolderView = null;
		if (folderView.rootWindow && folderView.rootWindow.focusedFolderView === folderView)
			folderView.rootWindow.focusedFolderView = null;
		if (folderView.rootWindow && folderView.rootWindow.selectionFolderView === folderView)
			folderView.rootWindow.selectionFolderView = null;
		if (folderView.focusManager && folderView.paneId > 0)
			folderView.focusManager.release_pane(folderView.paneId);
	}

	onActiveFocusChanged: {
		folderView.updateViewFocus();
		if (folderView.activeFocus) {
			folderView.focusOwned = true;
			// Adopt this view's selection when it is focused, but never let an
			// empty pane take the actions over: opening a popup can bounce the
			// focus to a sibling pane and would otherwise clear them.
			if (folderView.rootWindow && folderView.selectionManager.selection_active) {
				folderView.rootWindow.selectionManager = folderView.selectionManager;
				folderView.rootWindow.selectionFolderView = folderView;
			}
			if (folderView.focusManager && folderView.paneId > 0)
				folderView.focusManager.activate_pane(folderView.paneId);
			folderView.updateFocusItems();
		}
	}

	// A selection is only ever made in the view the input went to, so point the
	// window at this view's manager whenever its selection changes.
	Connections {
		target: folderView.selectionManager
		function onSelection_changed() {
			if (folderView.rootWindow) {
				folderView.rootWindow.selectionManager = folderView.selectionManager;
				folderView.rootWindow.selectionFolderView = folderView;
			}
		}
	}

	Connections {
		target: grid
		function onCountChanged() {
			folderView.updateFocusItems();
			folderView.scheduleThumbnails();
		}
	}







	onGridStrideChanged: {
		if (folderView.focusOwned && folderView.focusManager && folderView.paneId > 0)
			folderView.focusManager.set_pane_columns(folderView.paneId, folderView.gridStride);
	}

	// Free placement re-flows with the view, so the pane's copy of the visual
	// positions is refreshed whenever the grid is recomputed.
	onGridMetricsChanged: {
		const metrics = folderView.gridMetrics;
		const fm = folderView.focusManager;
		if (!fm || folderView.paneId <= 0)
			return;
		if (metrics.free || metrics.grouped)
			fm.set_pane_positions(folderView.paneId, JSON.stringify(metrics.slots));
		fm.set_pane_grid(folderView.paneId, metrics.columns, metrics.rows);
		fm.set_pane_empty_slots(folderView.paneId, folderView.focusEmptySlots);
		// The viewport just became (or changed) usable; bring the cursor into
		// view in case the first attempt ran before the view was laid out.
		if (folderView.focusOwned && fm.focus_active && fm.current_pane === folderView.paneId)
			Qt.callLater(() => folderView.ensureFocusVisible());
	}

	// Toggling FocusEmptySlots takes effect immediately.
	onFocusEmptySlotsChanged: {
		const fm = folderView.focusManager;
		if (fm && folderView.paneId > 0)
			fm.set_pane_empty_slots(folderView.paneId, folderView.focusEmptySlots);
	}

	Connections {
		target: folderView.focusManager
		function onFocus_changed() {
			const fm = folderView.focusManager;
			// A focus sound on every cursor move, but only when the cursor really
			// moved: focus_changed also fires for pane / active changes, and a
			// scroll-follow cursor move should stay quiet.
			if (fm && fm.focus_active && fm.current_pane === folderView.paneId) {
				const path = String(fm.focused_path);
				if (path !== "" && path !== folderView.lastFocusSoundPath && !folderView.suppressFocusScroll
					&& !folderView.suppressFocusSound) {
					folderView.lastFocusSoundPath = path;
					// A held direction can step faster than the sound device
					// wants to open the PCM; keep one tick per 60 ms.
					const now = Date.now();
					if (now - folderView.lastFocusSoundTime >= 60) {
						folderView.lastFocusSoundTime = now;
						folderView.playSound("item-focus");
					}
				}
				saveFocusTimer.restart();
			}
			topScreenFocusTimer.restart();
			// Keep the window's item actions pointed at the pane holding the
			// cursor, even when the keyboard sits elsewhere (popup, dialog).
			// Assigning the same view again still emits a change and re-runs
			// every action binding that follows the target, so only do it when
			// the focused pane actually changed.
			if (fm && folderView.rootWindow && fm.current_pane === folderView.paneId
				&& folderView.rootWindow.focusedFolderView !== folderView)
				folderView.rootWindow.focusedFolderView = folderView;
			// Follow the cursor when it moves into this pane, but never take the
			// keyboard back from an open popup or a dialog that has taken it.
			if (fm && fm.view_focused && fm.current_pane === folderView.paneId && !folderView.activeFocus
				&& !(folderView.Window.window && folderView.Window.window.activeFocusItem))
				folderView.forceActiveFocus();
			// A scroll-follow move must not trigger the focus-driven scroll that
			// would yank the view back to the cursor. The same goes for a click,
			// which must leave the item under the finger: while the cursor sits
			// on the clicked path, no reveal is wanted.
			if (folderView.focusOwned && fm && fm.current_pane === folderView.paneId
				&& !folderView.suppressFocusScroll) {
				const focused = String(fm.focused_path);
				if (focused === "" || focused !== folderView.suppressRevealPath) {
					folderView.suppressRevealPath = "";
					folderView.ensureFocusVisible();
				}
			}
		}
		function onAccept_requested() {
			if (folderView.rootWindow && folderView.rootWindow.sheetOpen)
				return;
			if (folderView.focusOwned && folderView.focusManager.current_pane === folderView.paneId)
				folderView.activateFocused();
		}
		function onMenu_requested() {
			folderView.openFocusedMenu();
		}
		function onSelect_requested() {
			if (!folderView.focusOwned || folderView.focusManager.current_pane !== folderView.paneId)
				return;
			const fm = folderView.focusManager;
			const mgr = folderView.selectionManager;
			if (mgr && fm && fm.focus_active && String(fm.focused_path) !== "") {
				folderView.playSound("item-selected");
				mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
			}
		}
		function onDirectory_menu_requested() {
			if (folderView.focusOwned && folderView.focusManager.current_pane === folderView.paneId)
				folderView.openDirectoryMenu();
		}
		function onQuit_requested() {
			if (!folderView.focusOwned || folderView.focusManager.current_pane !== folderView.paneId)
				return;
			const am = folderView.rootWindow ? folderView.rootWindow.actionManager : null;
			if (am && am.quitAction.enabled)
				am.quitAction.trigger();
		}
		function onCancel_requested() {
			if (folderView.rootWindow && folderView.rootWindow.sheetOpen)
				return;
			if (!folderView.focusOwned || folderView.focusManager.current_pane !== folderView.paneId)
				return;

			if (folderView.openMenu && folderView.openMenu.visible) {
				folderView.openMenu.close();
				folderView.openMenu = null;
				return;
			}

			if (folderView.filterActive) {
				folderView.directory.clear_filter();
				return;
			}

			const mgr = folderView.selectionManager;
			if (mgr && mgr.selection_active) {
				mgr.exit_selection_mode();
				return;
			}

			// South is Back. It walks this pane's history rather than going to
			// the parent; with nothing behind it, it is silent.
			if (folderView.canGoBack && folderView.goBack())
				folderView.playSound("return");
		}
	}


	// The scan runs on a worker; poll it quickly so the rows appear as soon as
	// the card has answered, without a GUI-thread wait.
	Timer {
		interval: 30
		repeat: true
		running: folderView.directory ? folderView.directory.scanning : false
		onTriggered: if (folderView.directory)
			folderView.directory.poll_scan()
	}

	Timer {
		interval: 400
		running: true
		repeat: true
		onTriggered: {
			if (folderView.directory) {
				folderView.directory.poll_thumbnails();
				folderView.directory.poll_descriptors();
				folderView.directory.poll_changes();
			}
		}
	}


	Connections {
		target: folderView.directory

		// A rebuild re-resolves every icon to its plain MIME icon, so thumbnail
		// requests must be re-issued for the visible items afterwards.
		function onModelReset() {
			// The worker scan can reorder the rows without changing the count
			// (the placeholder pass sorts by name, the finished scan by the
			// folder's sort mode). `onCountChanged` therefore does not fire;
			// without this the pane kept the placeholder order and the D-pad
			// index and the published focus path disagreed. Tap was correct
			// because focusSlot refreshes the pane first.
			folderView.updateFocusItems();
			folderView.scheduleThumbnails();
		}

		function onScanning_changed() {
			if (!folderView.directory || folderView.directory.scanning)
				return;
			if (!folderView.entryScanPending)
				return;
			folderView.entryScanPending = false;
			folderView.resetEntryViewport();
			Qt.callLater(() => folderView.ensureFocusVisible());
		}

		// Filtering swaps the visible rows; re-point the pane at them and put
		// the focus on the first match while a filter is up.
		function onFilter_changed() {
			folderView.updateFocusItems();
			const fm = folderView.focusManager;
			if (fm && folderView.paneId > 0 && fm.current_pane === folderView.paneId && folderView.filterActive)
				fm.focus_first();
			folderView.scheduleThumbnails();
		}

		function onPathChanged() {
			const current = String(folderView.directory.path);
			const previous = folderView.lastPath;
			folderView.lastPath = current;
			if (folderView.historyNavigating)
				folderView.historyNavigating = false;
			else
				folderView.recordHistory(current);
			folderView.returnFocusPath = previous;

			// The scan now runs on a worker. Put the viewport at the top now,
			// and do it again when the rows arrive so a cold scan cannot leave
			// the view chasing the cursor.
			folderView.entryScanPending = true;
			folderView.resetEntryViewport();

			// The directory has already scanned the new folder (and re-read its
			// config) when the path was set, so only the view state is updated
			// here.
			if (folderView.focusManager)
				folderView.focusManager.clear_pane(folderView.paneId);
			// Entering a folder leaves the focus inactive, so no border shows
			// until the next directional input; a restored target activates it.
			folderView.updateFocusItems();
			folderView.scheduleThumbnails();
			if (folderView.selectionManager)
				folderView.selectionManager.exit_selection_mode();
		}

		function onConfig_changed() {
			// View-only settings (grid size, sorting, free placement, ...) are
			// applied by re-evaluating the grid bindings; the directory does not
			// need to be re-read. A grid size change may need thumbnails of a
			// different cache tier.
			folderView.updateFocusItems();
			folderView.scheduleThumbnails();
		}
	}

	Connections {
		target: folderView.config

		function onItems_changed() {
			// Only keys that change which files exist require a full re-scan.
			const includeHidden = !folderView.config.stash_dotfiles || folderView.config.show_stash;
			folderView.directory.load_directory(folderView.directory.path, includeHidden);
			folderView.updateFocusItems();
		}
	}

	readonly property string folderName: {
		if (!folderView.directory)
			return "/";
		let path = folderView.directory.path.toString();
		if (!path || path === "/" || path === ".")
			return "/";
		if (path.endsWith("/") && path.length > 1) {
			path = path.substring(0, path.length - 1);
		}
		let name = path.split("/").pop();
		return name !== "" ? name : "/";
	}

	Kirigami.Theme.colorSet: Kirigami.Theme.View

	Binding {
		target: folderView.Window.window
		property: "title"
		value: folderView.folderName
		restoreMode: Binding.RestoreBindingOrValue
	}

	// ── Background ──

	Image {
		id: wallpaper
		anchors.fill: parent
		source: String(folderView.config ? folderView.config.wallpaper : "")
		fillMode: Image.PreserveAspectCrop
		visible: status === Image.Ready
	}

	Rectangle {
		anchors.fill: parent
		color: wallpaper.status === Image.Ready ? "transparent" : Kirigami.Theme.backgroundColor
		radius: 8
		anchors.margins: 4
	}

	// Context menu for the folder being viewed. Formerly an undefined attached
	// object named "ContextMenu"; see FileSlot.qml for why that was replaced.
	// Lazy for the same reason as FileSlot's: it is only needed when opened.
	Loader {
		id: directoryMenuLoader
		active: false
		sourceComponent: directoryMenuComponent
	}

	Component {
		id: directoryMenuComponent
		ShellContextMenu {
			actionManager: folderView.rootWindow.actionManager
			directory: folderView.directory
			targetIsBackground: true
		}
	}

	readonly property ShellContextMenu directoryMenu: directoryMenuLoader.item

	MouseArea {
		id: backgroundMouseArea
		anchors.fill: parent
		z: -1
		acceptedButtons: Qt.LeftButton

		onClicked: mouse => {
			if (mouse.button === Qt.LeftButton) {
				folderView.forceActiveFocus();
				folderView.selectionManager.clear();
				if (folderView.focusManager)
					folderView.focusManager.clear_pane(folderView.paneId);
			}
		}
	}

	function isDropValid(targetPath, sourcePaths) {
		return window.dropValidator.is_drop_valid(targetPath, sourcePaths);
	}

	// In free placement mode a drop of items that already live in this folder
	// repositions them instead of moving them into a child.
	function isFreeRepositionDrop(sourcePaths) {
		const cfg = folderView.config;
		if (!cfg || cfg.sort !== 3 || cfg.view_mode !== 0 || !sourcePaths || sourcePaths.length === 0)
			return false;
		const dirPath = String(folderView.directory.path);
		for (let i = 0; i < sourcePaths.length; i++) {
			const sp = String(sourcePaths[i]);
			const sep = sp.lastIndexOf("/");
			if (sep < 0 || sp.substring(0, sep) !== dirPath)
				return false;
		}
		return true;
	}

	function freeSlotAt(x, y) {
		const metrics = folderView.gridMetrics;
		if (!metrics.free || metrics.columns < 1 || metrics.rows < 1)
			return { col: -1, row: -1 };
		const local = bgDropArea.mapToItem(gridContent, x, y);
		const col = Math.round((local.x - metrics.offsetX - metrics.itemWidth / 2) / (metrics.itemWidth + metrics.gap));
		const row = Math.round((local.y - metrics.offsetY - metrics.itemHeight / 2) / (metrics.itemHeight + metrics.gap));
		return {
			col: Math.max(0, Math.min(metrics.columns - 1, col)),
			row: Math.max(0, Math.min(metrics.rows - 1, row))
		};
	}

	function dirUnderPoint(x, y) {
		const count = grid.count;
		for (let i = 0; i < count; i++) {
			const slot = grid.slotAt(i);
			if (!slot || !slot.is_dir)
				continue;
			if (x >= slot.x && x <= slot.x + slot.width && y >= slot.y && y <= slot.y + slot.height)
				return slot;
		}
		return null;
	}

	function resetFolderDrop() {
		folderDropTimer.stop();
		folderView.updateFolderNavTarget("");
		if (folderView.folderDropPath !== "")
			folderView.folderDropPath = "";
		if (folderView.folderDropActive)
			folderView.folderDropActive = false;
	}

	// Arm (or clear) the spring-load navigation into a folder during a drag.
	// Re-arming on every move of the same folder would keep restarting the
	// timer, so the timer keeps running while the target is unchanged.
	function updateFolderNavTarget(path) {
		if (path === "") {
			if (folderView.folderNavPath !== "") {
				folderView.folderNavPath = "";
				folderNavTimer.stop();
			}
			return;
		}
		if (folderView.folderNavPath === path) {
			if (!folderNavTimer.running)
				folderNavTimer.restart();
			return;
		}
		folderView.folderNavPath = path;
		folderNavTimer.restart();
	}

	function updateFreeDropTarget(x, y, sourcePaths) {
		if (!folderView.gridMetrics.free) {
			folderView.freeDropCol = -1;
			folderView.freeDropRow = -1;
			folderView.resetFolderDrop();
			return;
		}

		const slot = folderView.freeSlotAt(x, y);
		folderView.freeDropCol = slot.col;
		folderView.freeDropRow = slot.row;

		const local = bgDropArea.mapToItem(gridContent, x, y);
		const dirSlot = folderView.dirUnderPoint(local.x, local.y);
		// Never spring-load into a folder the drop is invalid for — above all the
		// dragged item itself (dragging a folder onto its own icon). The source
		// paths are absolute and live on the window's drag handler for the whole
		// drag, so this still holds after navigating in and out of folders.
		if (dirSlot && folderView.isDropValid(dirSlot.path, sourcePaths || [])) {
			// Spring-load: hovering a folder long enough descends into it. The
			// background owns drops in free placement, so arm it here (the
			// regular grid does it in FileSlot's drop area).
			folderView.updateFolderNavTarget(dirSlot.path);
			if (folderView.folderDropPath !== dirSlot.path) {
				folderView.folderDropPath = dirSlot.path;
				folderView.folderDropActive = false;
				folderDropTimer.restart();
			}
		} else {
			folderView.resetFolderDrop();
		}
	}

	// True when the given window/scene point lies outside the window content.
	function repositionCursorOutsideWindow(wx, wy) {
		const win = folderView.Window.window;
		if (!win || !win.contentItem)
			return false;
		return wx < 0 || wy < 0 || wx > win.contentItem.width || wy > win.contentItem.height;
	}

	// Map the selected paths that live in this folder to their file names.
	function selectedNameMap(paths) {
		const dirPath = String(folderView.directory.path);
		const selected = {};
		for (let i = 0; i < paths.length; i++) {
			const sp = String(paths[i]);
			const sep = sp.lastIndexOf("/");
			if (sep < 0 || sp.substring(0, sep) !== dirPath)
				continue;
			selected[sp] = sp.substring(sep + 1);
		}
		return selected;
	}

	// Gather the current free-placement slot of every selected item so its
	// arrangement can be reproduced elsewhere.
	function selectedSlotEntries(selected) {
		const metrics = folderView.gridMetrics;
		const entries = [];
		if (!metrics.free || !metrics.slots)
			return entries;
		for (let i = 0; i < grid.count; i++) {
			const item = grid.slotAt(i);
			if (!item || selected[item.path] === undefined)
			continue;
			const slot = metrics.slots[i];
			if (!slot)
				continue;
			entries.push({ name: selected[item.path], path: item.path, title: item.title, icon: item.icon, isDir: item.is_dir, c: slot.c, r: slot.r });
		}
		return entries;
	}

	// The grabbed item is the anchor; without one, use the top-left of the block.
	function anchorEntry(entries, mainPath) {
		for (let i = 0; i < entries.length; i++) {
			if (entries[i].path === mainPath)
				return entries[i];
		}
		let anchor = entries[0];
		for (let i = 1; i < entries.length; i++) {
			const e = entries[i];
			if (e.c < anchor.c || (e.c === anchor.c && e.r < anchor.r))
				anchor = e;
		}
		return anchor;
	}

	// The on-disk name of an item path; free positions are stored by name.
	function itemName(path) {
		const sep = path.lastIndexOf("/");
		return sep >= 0 ? path.substring(sep + 1) : path;
	}

	// The free cell nearest (Manhattan) to (col,row), or null when the grid is
	// full. `taken` is keyed "col,row".
	function nearestFreeCell(taken, columns, rows, col, row) {
		let best = null;
		let bestDist = Infinity;
		for (let r = 0; r < rows; r++) {
			for (let c = 0; c < columns; c++) {
				if (taken[c + "," + r])
					continue;
				const dist = Math.abs(r - row) + Math.abs(c - col);
				if (dist < bestDist) {
					bestDist = dist;
					best = { c: c, r: r };
				}
			}
		}
		return best;
	}

	// Begin a custom, in-window reposition drag for the given selection.
	function beginRepositionDrag(mainPath, paths, wx, wy, hotspotX, hotspotY) {
		const cfg = folderView.config;
		if (!cfg || cfg.sort !== 3 || cfg.view_mode !== 0 || !paths || paths.length === 0)
			return false;
		const metrics = folderView.gridMetrics;
		if (!metrics.free || !metrics.slots || metrics.slots.length === 0)
			return false;

		const entries = folderView.selectedSlotEntries(folderView.selectedNameMap(paths));
		if (entries.length === 0)
			return false;

		const anchor = folderView.anchorEntry(entries, mainPath);
		const itemW = metrics.itemWidth;
		const itemH = metrics.itemHeight;
		const gap = metrics.gap;
		const previewItems = [];
		for (let i = 0; i < entries.length; i++) {
			const e = entries[i];
			previewItems.push({
				path: e.path,
				title: e.title,
				icon: e.icon,
				isDir: e.isDir,
				x: (e.c - anchor.c) * (itemW + gap),
				y: (e.r - anchor.r) * (itemH + gap),
				w: itemW,
				h: itemH
			});
		}

		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		if (handler) {
			handler.reposition_preview = JSON.stringify({ hotspotX: hotspotX, hotspotY: hotspotY, gridSize: (cfg.grid_size ? cfg.grid_size : 64), showLabels: cfg.show_labels, labelsBeside: folderView.labelsBesideIcons, items: previewItems });
			handler.reposition_active = true;
		}
		folderView.repositionDragActive = true;
		folderView.updateRepositionDrag(wx, wy);
		return true;
	}

	function updateRepositionDrag(wx, wy) {
		if (!folderView.repositionDragActive)
			return;
		const local = folderView.mapFromItem(null, wx, wy);
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		folderView.updateFreeDropTarget(local.x, local.y, handler ? handler.drag_source_paths : []);
		if (handler) {
			handler.update_cursor(wx, wy);
			handler.reposition_active = !folderView.folderDropActive;
		}
	}

	function cancelRepositionDrag() {
		folderView.repositionDragActive = false;
		folderView.freeDropCol = -1;
		folderView.freeDropRow = -1;
		folderView.resetFolderDrop();
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		if (handler) {
			handler.reposition_preview = "";
			handler.reposition_active = false;
		}
	}

	function endRepositionDrag(wx, wy) {
		if (!folderView.repositionDragActive)
			return;
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		const local = folderView.mapFromItem(null, wx, wy);
		const slot = folderView.freeSlotAt(local.x, local.y);
		const dropFolder = folderView.folderDropActive ? folderView.folderDropPath : "";
		folderView.cancelRepositionDrag();

		if (dropFolder !== "" && handler) {
			const fm = folderView.rootWindow ? folderView.rootWindow.fileManager : null;
			const uris = handler.drag_uris ? handler.drag_uris.join("\n") : "";
			const action = handler.drag_action ? String(handler.drag_action) : "move";
			if (uris.length > 0 && fm && fm.process_uris_action(dropFolder, uris, action))
				folderView.directory.reload();
			// Dropping into a folder ends the drag too; clear the selection it
			// made.
			if (folderView.selectionManager)
				folderView.selectionManager.exit_selection_mode();
			return;
		}

		folderView.applyRepositionToSlot(slot.col, slot.row);
	}

	// Move the selection so its anchor lands on (col,row). Anything already
	// sitting on a destination cell is displaced too: a single item swaps with
	// the one it lands on, a group pushes the occupant to the nearest free cell.
	// Without this the layout resolved the collision by item order, so a drop
	// could end up anywhere.
	function applyRepositionToSlot(col, row) {
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		if (!handler || !handler.drag_source_paths || handler.drag_source_paths.length === 0)
			return false;
		const metrics = folderView.gridMetrics;
		if (!metrics.free || !metrics.slots || metrics.slots.length === 0)
			return false;

		const entries = folderView.selectedSlotEntries(folderView.selectedNameMap(handler.drag_source_paths));
		if (entries.length === 0)
			return false;

		// Anchor the grabbed item on the target slot and shift the whole group so
		// nothing is clamped off the top/left edge.
		const anchor = folderView.anchorEntry(entries, String(handler.drag_main_path));
		let dCol = col - anchor.c;
		let dRow = row - anchor.r;
		let minCol = 0;
		let minRow = 0;
		for (let i = 0; i < entries.length; i++) {
			minCol = Math.min(minCol, entries[i].c + dCol);
			minRow = Math.min(minRow, entries[i].r + dRow);
		}
		dCol -= minCol;
		dRow -= minRow;

		// The cells the group is heading for, and the names in it.
		const movingTo = ({});
		const movingNames = ({});
		for (let i = 0; i < entries.length; i++) {
			const e = entries[i];
			movingTo[(e.c + dCol) + "," + (e.r + dRow)] = true;
			movingNames[e.name] = true;
		}

		// Occupancy starts as the destinations; everything that stays put adds to
		// it. Anything standing on a destination has to be displaced.
		const taken = ({});
		for (const cell in movingTo)
			taken[cell] = true;

		const displaced = [];
		for (let i = 0; i < grid.count; i++) {
			const item = grid.slotAt(i);
			const slot = metrics.slots[i];
			if (!item || !slot)
				continue;
			const name = folderView.itemName(item.path);
			if (movingNames[name])
				continue;
			const cell = slot.c + "," + slot.r;
			if (movingTo[cell])
				displaced.push({ name: name, c: slot.c, r: slot.r });
			else
				taken[cell] = true;
		}

		folderView.repositionAnimating = true;
		// Place the whole moved set in one write so its target cells win over
		// any older saved position in them (a visible item or a stashed
		// dotfile), then let the unpositioned items reflow around it.
		const movedPositions = {};
		for (let i = 0; i < entries.length; i++) {
			const e = entries[i];
			movedPositions[e.name] = [e.c + dCol, e.r + dRow];
		}
		folderView.directory.set_free_positions(JSON.stringify(movedPositions));

		// A one-for-one drop swaps with the item it lands on. A group pushes the
		// occupant aside; the cells the group is leaving are free, so the search
		// naturally prefers them.
		if (entries.length === 1 && displaced.length === 1) {
			folderView.directory.set_free_position(displaced[0].name, entries[0].c, entries[0].r);
		} else {
			for (let i = 0; i < displaced.length; i++) {
				const cell = folderView.nearestFreeCell(taken, metrics.columns, metrics.rows, displaced[i].c, displaced[i].r);
				if (!cell)
					continue;
				taken[cell.c + "," + cell.r] = true;
				folderView.directory.set_free_position(displaced[i].name, cell.c, cell.r);
			}
		}

		repositionAnimTimer.restart();
		// The drag selected the items it moved; the drop ends that gesture, so
		// the selection should not linger.
		if (folderView.selectionManager)
			folderView.selectionManager.exit_selection_mode();
		return true;
	}

	function repositionDroppedItems(drop) {
		const cfg = folderView.config;
		if (!cfg || cfg.sort !== 3 || cfg.view_mode !== 0)
			return false;
		const metrics = folderView.gridMetrics;
		if (!metrics.free || !metrics.slots || metrics.slots.length === 0)
			return false;
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		if (!handler || !handler.drag_source_paths || handler.drag_source_paths.length === 0)
			return false;

		const slot = folderView.freeSlotAt(drop.x, drop.y);
		return folderView.applyRepositionToSlot(slot.col, slot.row);
	}

	// Scroll the view when the drag cursor is within an edge margin. Farther
	// into the margin scrolls faster.
	function updateDragEdgeScroll() {
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		if (!handler || flickable.width <= 0 || flickable.height <= 0)
			return;
		const local = flickable.mapFromItem(null, handler.drag_cursor_x, handler.drag_cursor_y);
		const margin = Kirigami.Units.gridUnit * 2;
		const maxStep = 28;
		const horizontal = folderView.config ? folderView.config.scroll_horizontal : false;
		let dx = 0;
		let dy = 0;
		if (horizontal) {
			if (local.x >= 0 && local.x < margin)
				dx = -Math.ceil((1 - local.x / margin) * maxStep);
			else if (local.x > flickable.width - margin && local.x <= flickable.width)
				dx = Math.ceil((1 - (flickable.width - local.x) / margin) * maxStep);
		} else {
			if (local.y >= 0 && local.y < margin)
				dy = -Math.ceil((1 - local.y / margin) * maxStep);
			else if (local.y > flickable.height - margin && local.y <= flickable.height)
				dy = Math.ceil((1 - (flickable.height - local.y) / margin) * maxStep);
		}
		if (dx !== 0) {
			const maxX = Math.max(0, flickable.contentWidth - flickable.width);
			flickable.contentX = Math.max(0, Math.min(flickable.contentX + dx, maxX));
		}
		if (dy !== 0) {
			const maxY = Math.max(0, flickable.contentHeight - flickable.height);
			flickable.contentY = Math.max(0, Math.min(flickable.contentY + dy, maxY));
		}
	}

	// Keeps the move animation armed only for the reposition that just happened.
	Timer {
		id: repositionAnimTimer
		interval: 260
		repeat: false
		onTriggered: folderView.repositionAnimating = false
	}

	// Active Drop Highlight Border
	Rectangle {
		anchors.fill: parent
		anchors.margins: 4
		radius: 8
		color: "transparent"
		border.color: Kirigami.Theme.highlightColor
		border.width: 3
		z: 10
		opacity: bgDropArea.isHovered ? 0.85 : 0.0
		Behavior on opacity {
			NumberAnimation {
				duration: 120
			}
		}
	}

	DropArea {
		id: bgDropArea
		anchors.fill: parent
		keys: ["text/uri-list", "text/plain"]
		z: 0

		property bool isHovered: false
		property FileManager fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null
		property DragDropHandler dragHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null

		onEntered: drag => {
			folderView.resetFolderDrop();
			checkDrop(drag);
		}

		onPositionChanged: drag => {
			checkDrop(drag);
		}

		function checkDrop(drag) {
			let sourcePaths = [];
			if (typeof dragHandler !== 'undefined' && dragHandler && dragHandler.drag_source_paths && dragHandler.drag_source_paths.length > 0) {
				sourcePaths = dragHandler.drag_source_paths;
			} else if (drag.source) {
				sourcePaths = drag.source.dragSourcePaths || (drag.source.mainPath ? [drag.source.mainPath] : []);
			} else if (drag.hasUrls) {
				sourcePaths = drag.urls;
			}

			folderView.updateFreeDropTarget(drag.x, drag.y, sourcePaths);
			// Track the cursor before any early return below (a same-folder drop
			// is invalid and returns early, which used to freeze the drag ghost
			// whenever the finger was not over a folder).
			if (typeof dragHandler !== 'undefined' && dragHandler) {
				const pt = bgDropArea.mapToItem(null, drag.x, drag.y);
				dragHandler.track_mouse_shake(pt.x, pt.y);
			}
			const folderPath = folderView.folderDropPath;
			const overFolder = folderPath !== "";

			if (folderView.isFreeRepositionDrop(sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof dragHandler !== 'undefined' && dragHandler) {
					dragHandler.reposition_active = !folderView.folderDropActive;
					dragHandler.tooltip_active = true;
				}
				drag.accept();
				return;
			}

			const target = overFolder ? folderPath : folderView.directory.path;
			if (!folderView.isDropValid(target, sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof dragHandler !== 'undefined' && dragHandler)
					dragHandler.tooltip_active = false;
				// Keep the drop area as the drag target so it keeps receiving
				// move events; the ghost follows the cursor. The drop itself is
				// a no-op (a same-folder move with no destination).
				drag.accept();
				return;
			}

			// Free placement has no per-slot DropArea (the background owns the
			// drops), so spring-load navigation into a hovered folder is driven
			// from here. The regular grid keeps it in FileSlot's drop area.
			if (folderView.gridMetrics.free)
				folderView.updateFolderNavTarget(overFolder ? folderPath : "");

			bgDropArea.isHovered = !overFolder;
			if (typeof dragHandler !== 'undefined' && dragHandler) {
				dragHandler.reposition_active = false;
				dragHandler.tooltip_active = true;
				const pt = bgDropArea.mapToItem(null, drag.x, drag.y);
				dragHandler.track_mouse_shake(pt.x, pt.y);
			}
			drag.accept();
		}

		onExited: {
			bgDropArea.isHovered = false;
			folderView.freeDropCol = -1;
			folderView.freeDropRow = -1;
			folderView.resetFolderDrop();
			if (typeof dragHandler !== 'undefined' && dragHandler) {
				dragHandler.tooltip_active = false;
				dragHandler.reposition_active = false;
			}
		}

		onDropped: drop => {
			let sourcePaths = [];
			if (typeof dragHandler !== 'undefined' && dragHandler && dragHandler.drag_source_paths && dragHandler.drag_source_paths.length > 0) {
				sourcePaths = dragHandler.drag_source_paths;
			} else if (drop.source) {
				sourcePaths = drop.source.dragSourcePaths || (drop.source.mainPath ? [drop.source.mainPath] : []);
			} else if (drop.hasUrls) {
				sourcePaths = drop.urls;
			}

			const folderPath = folderView.folderDropPath;
			const sameFolderReposition = folderView.isFreeRepositionDrop(sourcePaths);
			const dropIntoFolder = folderPath !== "" && (!sameFolderReposition || folderView.folderDropActive);

			bgDropArea.isHovered = false;
			folderView.freeDropCol = -1;
			folderView.freeDropRow = -1;
			folderView.resetFolderDrop();
			if (typeof dragHandler !== 'undefined' && dragHandler) {
				dragHandler.tooltip_active = false;
				dragHandler.reposition_active = false;
			}

			if (!dropIntoFolder && folderView.repositionDroppedItems(drop)) {
				drop.accept();
				return;
			}

			let uris = "";
			if (typeof dragHandler !== 'undefined' && dragHandler && dragHandler.drag_uris && dragHandler.drag_uris.length > 0) {
				uris = dragHandler.drag_uris.join("\n");
			} else if (drop.source && drop.source.dragUris) {
				uris = drop.source.dragUris.join("\n");
			} else if (drop.hasUrls) {
				uris = drop.urls.join("\n");
			} else if (drop.hasText) {
				uris = drop.text;
			}

			if (uris.length > 0 && typeof fileManager !== 'undefined' && fileManager) {
				const target = dropIntoFolder ? folderPath : folderView.directory.path;
				const action = (typeof dragHandler !== 'undefined' && dragHandler) ? dragHandler.drag_action : "move";
				if (fileManager.process_uris_action(target, uris, action)) {
					const win = folderView.rootWindow;
					if (win && typeof win.requestDirectoryReload === 'function')
						win.requestDirectoryReload(folderView.directory);
					else
						folderView.directory.reload();
				}
				drop.accept();
			}
		}
	}

	// Switching from repositioning to dropping into a folder requires hovering
	// the same folder for this long first.
	Timer {
		id: folderDropTimer
		interval: 600
		repeat: false
		onTriggered: {
			if (folderView.folderDropPath === "")
				return;
			folderView.folderDropActive = true;
			const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
			if (handler) {
				handler.reposition_active = false;
				handler.tooltip_active = true;
			}
		}
	}

	// Hovering a folder during a drag long enough opens it, so a drag can
	// descend into it (spring-load). Used by the free-placement background,
	// which owns the drops there; the regular grid does this per slot.
	Timer {
		id: folderNavTimer
		interval: 600
		repeat: false
		onTriggered: {
			const path = folderView.folderNavPath;
			folderView.folderNavPath = "";
			if (path === "" || !folderView.directory)
				return;

			const navigate = function () {
				if (!folderView.directory)
					return;
				folderView.playSound("window-new");
				folderView.directory.open_path(path);
			};

			// In free placement the drag is an in-window reposition tracked by
			// the slot; navigating would destroy it. Hand it to an OS drag (which
			// lives on the window, not the slot) so it survives the folder change.
			// The hand-off queues `navigate` inside QDrag::exec(), because that
			// call does not return until the gesture ends. Opening the folder
			// after it returned was why the hover never descended.
			if (folderView.repositionDragActive) {
				const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
				const mainPath = handler ? String(handler.drag_main_path) : "";
				let source = null;
				for (let i = 0; i < grid.count; ++i) {
					const it = grid.slotAt(i);
					if (it && String(it.path) === mainPath) {
						source = it;
						break;
					}
				}
				if (source && handler && typeof source.handOffRepositionDrag === 'function') {
					source.handOffRepositionDrag(handler.drag_cursor_x, handler.drag_cursor_y, navigate);
					return;
				}
			}
			navigate();
		}
	}

	// Auto-scroll the view while an item is dragged near an edge, so a drag can
	// reach items that are off-screen. Runs for both the in-window reposition
	// drag and native drags (the window tracks their cursor position).
	Timer {
		id: dragEdgeScrollTimer
		interval: 24
		repeat: true
		running: folderView.repositionDragActive
			|| (folderView.rootWindow && folderView.rootWindow.internalDragInProcess)
		onTriggered: folderView.updateDragEdgeScroll()
	}

	// ── Input Shortcuts ───

	// Type-to-filter: printable keys extend the filter, Backspace trims it and
	// Escape clears it. Returns true when the key was consumed.
	function handleFilterKey(event) {
		const dir = folderView.directory;
		if (!dir)
			return false;

		const active = String(dir.filter).length > 0;
		const control = (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) !== 0;

		if (event.key === Qt.Key_Escape) {
			if (!active)
				return false;
			dir.clear_filter();
			return true;
		}

		if (event.key === Qt.Key_Backspace) {
			if (!active)
				return false;
			dir.backspace_filter();
			return true;
		}

		// Space keeps toggling the selection until the filter is up.
		if (event.key === Qt.Key_Space && !active)
			return false;

		if (control || event.text.length === 0)
			return false;

		// Tab, Return, Delete and friends carry control characters in `text`.
		for (let i = 0; i < event.text.length; i++) {
			const code = event.text.charCodeAt(i);
			if (code < 0x20 || code === 0x7f)
				return false;
		}

		dir.append_filter(event.text);
		return true;
	}

	Keys.onPressed: event => {
		if (folderView.handleFilterKey(event)) {
			event.accepted = true;
			return;
		}

		const mgr = folderView.selectionManager;
		const fm = folderView.focusManager;
		if (!mgr || !fm)
			return;

		const shift = (event.modifiers & Qt.ShiftModifier) !== 0;

		switch (event.key) {
		case Qt.Key_Left:
		case Qt.Key_Right:
		case Qt.Key_Up:
		case Qt.Key_Down: {
			folderView.endEntry();
			const direction = event.key === Qt.Key_Left ? "left" : event.key === Qt.Key_Right ? "right" : event.key === Qt.Key_Up ? "up" : "down";
			// Shift extends the selection with the item the cursor lands on;
			// that gesture owns its sound, so the focus move stays quiet.
			folderView.suppressFocusSound = shift;
			fm.move_focus(direction);
			folderView.suppressFocusSound = false;
			if (shift && fm.focus_active && String(fm.focused_path) !== "") {
				folderView.playSound("item-selected");
				mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
			}
			event.accepted = true;
			break;
		}
		case Qt.Key_Home:
			folderView.endEntry();
			fm.focus_first();
			event.accepted = true;
			break;
		case Qt.Key_End:
			folderView.endEntry();
			fm.focus_last();
			event.accepted = true;
			break;
		case Qt.Key_Space:
			if (fm.focus_active && String(fm.focused_path) !== "") {
				folderView.playSound("item-selected");
				mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
				event.accepted = true;
			}
			break;
		case Qt.Key_Return:
		case Qt.Key_Enter:
			if (fm.focus_active && String(fm.focused_path) !== "") {
				folderView.activateFocused();
				event.accepted = true;
			}
			break;
		case Qt.Key_Escape:
			if (mgr.selection_active)
				mgr.exit_selection_mode();
			fm.clear_pane(folderView.paneId);
			event.accepted = true;
			break;
		case Qt.Key_A:
			if (event.modifiers & Qt.ControlModifier) {
				folderView.selectAll();
				event.accepted = true;
			}
			break;
		}
	}

	// ── Grid ───

	// Short enough that a press feels like a move, not like an animation the
	// user is waiting for. It ends before the pad's next repeat, so a held
	// direction scrolls in complete steps.
	NumberAnimation {
		id: focusScrollY
		target: flickable
		property: "contentY"
		duration: 110
		easing.type: Easing.OutCubic
		onRunningChanged: {
			if (!running && !focusScrollX.running)
				folderView.focusScrollAnimating = false;
		}
	}

	NumberAnimation {
		id: focusScrollX
		target: flickable
		property: "contentX"
		duration: 110
		easing.type: Easing.OutCubic
		onRunningChanged: {
			if (!running && !focusScrollY.running)
				folderView.focusScrollAnimating = false;
		}
	}

	FolderGrid {
		id: grid
		z: 1
		anchors {
			top: parent.top
			left: parent.left
			right: parent.right
			bottom: parent.bottom
			leftMargin: Kirigami.Units.mediumSpacing
			rightMargin: Kirigami.Units.mediumSpacing
			bottomMargin: Kirigami.Units.mediumSpacing
			// The filter bar pushes the grid down while it is up.
			topMargin: folderView.filterActive ? filterBar.height + Kirigami.Units.mediumSpacing * 2 : Kirigami.Units.mediumSpacing
		}

		directory: folderView.directory
		config: folderView.config
		focusManager: folderView.focusManager
		selectionManager: folderView.selectionManager
		window: folderView.rootWindow
		paneId: folderView.paneId
		focusOwned: folderView.focusOwned
		filterActive: folderView.filterActive
		focusBorderSource: folderView.focusBorderSource
		horizontalScroll: folderView.horizontalScroll
		focusEmptySlots: folderView.focusEmptySlots
		freeDropCol: folderView.freeDropCol
		freeDropRow: folderView.freeDropRow
		repositionAnimating: folderView.repositionAnimating

		onItemSelectionToggled: (p, idx) => {
			folderView.forceActiveFocus();
			// The cursor follows the selection: the item the user just selected
			// is the one the keyboard then acts on.
			folderView.focusSlotForSelection(p);
			folderView.playSound("item-selected");
			if (folderView.selectionManager)
				folderView.selectionManager.toggle_selection(p, idx);
		}

		onItemShiftSelected: idx => {
			folderView.forceActiveFocus();
			const item = grid.slotAt(idx);
			if (item && item.path)
				folderView.focusSlotForSelection(String(item.path));
			folderView.playSound("item-selected");
			const mgr = folderView.selectionManager;
			if (mgr) {
				if (!mgr.selection_active)
					mgr.enter_selection_mode();
				const from = mgr.last_selected_index >= 0 ? mgr.last_selected_index : idx;
				mgr.range_select(from, idx);
			}
		}

		onItemPressHeld: (p, idx) => {
			folderView.forceActiveFocus();
			// A long press selects the item under the finger; the cursor has to
			// move with it, or the next keyboard action would apply elsewhere.
			folderView.focusSlotForSelection(p);
			folderView.playSound("item-selected");
			if (folderView.selectionManager)
				folderView.selectionManager.toggle_selection(p, idx);
		}

		onItemContextMenuRequested: (p, idx) => {
			folderView.forceActiveFocus();
			folderView.focusSlot(p, false);
			const mgr = folderView.selectionManager;
			if (mgr && !mgr.is_selected(p)) {
				mgr.clear();
				mgr.toggle_selection(p, idx);
			}
		}

		onBackgroundClicked: {
			folderView.forceActiveFocus();
			folderView.selectionManager.clear();
			if (folderView.focusManager)
				folderView.focusManager.clear_pane(folderView.paneId);
		}

		// Scrolling must not leave the cursor on a clipped item: the focus
		// follows the viewport, moving to the nearest item that is fully in
		// view. Throttled, so a fling does not walk the cursor for every pixel.
		onViewportScrolled: {
			folderView.lastViewMoveTime = Date.now();
			// Entry placement and a focus-driven reveal are programmatic; only
			// a user gesture should move the cursor to follow the viewport.
			if (folderView.entryScrollReset || folderView.focusScrollAnimating)
				return;
			folderView.scheduleFocusFollow();
		}
		// The gesture is over: settle the cursor now, so the border reappears
		// on a fully visible item instead of flashing on a clipped one.
		onScrollEnded: {
			focusFollowTimer.stop();
			folderView.keepFocusInView();
		}
	}

	// ── Filter Bar ───

	FolderFilterBar {
		id: filterBar
		directory: folderView.directory
		matchCount: grid.count
		filterActive: folderView.filterActive
		window: folderView.rootWindow
		onFocusRequested: folderView.forceActiveFocus()
		onClearRequested: {
			folderView.directory.clear_filter();
			folderView.forceActiveFocus();
		}
	}

	// ── Selection Toolbar ───

	// The bar overlays the bottom of the grid rather than displacing it: the grid
	// is not anchored to it, so entering selection mode cannot change how many
	// rows fit (which re-flowed the whole folder and made the grid jump).
	FolderSelectionBar {
		id: selectionBar
		selectionManager: folderView.selectionManager
		itemCount: grid.count
		window: folderView.rootWindow
		onSelectAllRequested: folderView.selectAll()
	}

	ExecuteDialog {
		id: execDialog
		directory: folderView.directory
		fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null
		window: folderView.rootWindow
	}
}
