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

	// Custom in-window reposition drag: the selection is previewed and moved
	// directly instead of starting an OS drag-and-drop sequence.
	property bool repositionDragActive: false
	property bool repositionAnimating: false

	// Selection state is owned per view so selection mode and the selection
	// toolbar stay inside the pane instead of the whole window.
	SelectionManager {
		id: selectionManagerImpl
	}

	// Labels are placed beside (rather than under) the icon either when the tiny
	// icon size makes that the natural fit, or when the folder asks for it.
	readonly property bool labelsBesideIcons: {
		const cfg = folderView.config;
		if (!cfg || !cfg.show_labels)
			return false;
		return cfg.grid_labels_beside_icons || cfg.grid_size < 32;
	}

	readonly property size gridItemSize: {
		const iconSize = folderView.config ? folderView.config.grid_size : 64;
		if (folderView.labelsBesideIcons) {
			// The row grows with the icon so the label always keeps a usable width.
			const labelWidth = Kirigami.Units.gridUnit * 7;
			return Qt.size(Math.max(Kirigami.Units.gridUnit * 10, iconSize + labelWidth + Kirigami.Units.gridUnit * 2), Math.max(Kirigami.Units.gridUnit * 2, iconSize + Kirigami.Units.smallSpacing * 2));
		}
		return Qt.size(iconSize + Kirigami.Units.gridUnit * 3, iconSize + Kirigami.Units.gridUnit * 3);
	}

	// Width the pane needs for its fixed grid block: the block, its scrollbar inset
	// and the view margins; -1 lets the pane take a fill share of the layout instead.
	readonly property real preferredGridWidth: {
		const cfg = folderView.config;
		if (!cfg || folderView.paneCount <= 1 || cfg.scroll_horizontal || cfg.grid_lines <= 0 || cfg.grid_horizontal_align === 0)
			return -1;

		const size = folderView.gridItemSize;
		const gap = Kirigami.Units.mediumSpacing;
		const naturalWidth = cfg.grid_lines * size.width + (cfg.grid_lines - 1) * gap;
		const rows = Math.max(1, Math.ceil(itemRepeater.count / cfg.grid_lines));
		const naturalHeight = rows * size.height + (rows - 1) * gap;
		const scrollBar = naturalHeight > flickable.height ? verticalScrollBar.width + gap : 0;
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
		if (!mgr)
			return;
		let paths = [];
		for (let i = 0; i < itemRepeater.count; i++) {
			let item = itemRepeater.itemAt(i);
			if (item && item.path) {
				paths.push(item.path);
			}
		}
		mgr.select_all(paths);
	}


	readonly property var gridMetrics: {
		const cfg = folderView.config;
		const horizontal = cfg ? cfg.scroll_horizontal : false;
		const count = itemRepeater.count;
		const viewWidth = flickable.width;
		const viewHeight = flickable.height;
		const gap = Kirigami.Units.mediumSpacing;
		const itemWidth = folderView.gridItemSize.width;
		const itemHeight = folderView.gridItemSize.height;
		const barWidth = verticalScrollBar.width;
		const barHeight = horizontalScrollBar.height;
		const barInsetX = barWidth + gap;
		const barInsetY = barHeight + gap;

		function alignOffset(align, view, natural) {
			if (align === 1)
				return 0;
			if (align === 3)
				return Math.max(0, view - natural);
			return Math.max(0, (view - natural) / 2);
		}

		function computeFreeLayout(width, height) {
			const freeCfg = cfg;
			const json = folderView.directory.free_layout(
				freeCfg.free_placement_positions,
				freeCfg.grid_lines,
				horizontal,
				width,
				height,
				itemWidth,
				itemHeight,
				gap
			);
			try {
				return JSON.parse(json);
			} catch (e) {
				return {
					columns: 1,
					rows: 1,
					slots: [],
					naturalWidth: itemWidth,
					naturalHeight: itemHeight
				};
			}
		}

		function measure(insetX, insetY) {
			const width = viewWidth - insetX;
			const height = viewHeight - insetY;
			if (cfg && cfg.sort === 3 && cfg.view_mode === 0) {
				const free = computeFreeLayout(width, height);
				return {
					width: width,
					height: height,
					stride: horizontal ? free.rows : free.columns,
					columns: free.columns,
					rows: free.rows,
					naturalWidth: free.naturalWidth,
					naturalHeight: free.naturalHeight,
					slots: free.slots,
					free: true
				};
			}
			const lines = cfg ? cfg.grid_lines : 0;
			const viewMain = horizontal ? height : width;
			const itemMain = horizontal ? itemHeight : itemWidth;
			const stride = lines > 0 ? lines : Math.max(1, Math.floor((viewMain + gap) / (itemMain + gap)));
			const lineCount = Math.max(1, Math.ceil(count / stride));
			const columns = horizontal ? lineCount : stride;
			const rows = horizontal ? stride : lineCount;
			return {
				width: width,
				height: height,
				stride: stride,
				columns: columns,
				rows: rows,
				naturalWidth: columns * itemWidth + (columns - 1) * gap,
				naturalHeight: rows * itemHeight + (rows - 1) * gap
			};
		}

		if (count === 0) {
			return {
				horizontal: horizontal,
				stride: 1,
				columns: 0,
				rows: 0,
				itemWidth: itemWidth,
				itemHeight: itemHeight,
				gap: gap,
				insetX: 0,
				insetY: 0,
				offsetX: 0,
				offsetY: 0,
				contentWidth: viewWidth,
				contentHeight: viewHeight
			};
		}

		let insetX = 0;
		let insetY = 0;
		let metrics = measure(insetX, insetY);
		for (let i = 0; i < 3; i++) {
			const nextInsetX = metrics.naturalHeight > metrics.height ? barInsetX : 0;
			const nextInsetY = metrics.naturalWidth > metrics.width ? barInsetY : 0;
			if (nextInsetX === insetX && nextInsetY === insetY)
				break;
			insetX = nextInsetX;
			insetY = nextInsetY;
			metrics = measure(insetX, insetY);
		}

		return {
			horizontal: horizontal,
			stride: metrics.stride,
			columns: metrics.columns,
			rows: metrics.rows,
			itemWidth: itemWidth,
			itemHeight: itemHeight,
			gap: gap,
			insetX: insetX,
			insetY: insetY,
			offsetX: alignOffset(cfg ? cfg.grid_horizontal_align : 0, metrics.width, metrics.naturalWidth),
			offsetY: alignOffset(cfg ? cfg.grid_vertical_align : 0, metrics.height, metrics.naturalHeight),
			contentWidth: Math.max(viewWidth, metrics.naturalWidth + insetX),
			contentHeight: Math.max(viewHeight, metrics.naturalHeight + insetY),
			free: metrics.free === true,
			slots: metrics.slots ? metrics.slots : []
		};
	}

	readonly property int gridStride: folderView.gridMetrics.stride

	readonly property bool freeDropActive: folderView.freeDropCol >= 0 && folderView.freeDropRow >= 0 && folderView.gridMetrics.free

	readonly property real freeDropX: {
		const metrics = folderView.gridMetrics;
		return metrics.offsetX + folderView.freeDropCol * (metrics.itemWidth + metrics.gap);
	}

	readonly property real freeDropY: {
		const metrics = folderView.gridMetrics;
		return metrics.offsetY + folderView.freeDropRow * (metrics.itemHeight + metrics.gap);
	}

	function gridSlotX(index) {
		const metrics = folderView.gridMetrics;
		if (metrics.free && metrics.slots && metrics.slots[index]) {
			return metrics.offsetX + metrics.slots[index].c * (metrics.itemWidth + metrics.gap);
		}
		const column = metrics.horizontal ? Math.floor(index / metrics.rows) : index % metrics.columns;
		return metrics.offsetX + column * (metrics.itemWidth + metrics.gap);
	}

	function gridSlotY(index) {
		const metrics = folderView.gridMetrics;
		if (metrics.free && metrics.slots && metrics.slots[index]) {
			return metrics.offsetY + metrics.slots[index].r * (metrics.itemHeight + metrics.gap);
		}
		const row = metrics.horizontal ? index % metrics.rows : Math.floor(index / metrics.columns);
		return metrics.offsetY + row * (metrics.itemHeight + metrics.gap);
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
		fm.set_pane_positions(folderView.paneId, metrics.free ? JSON.stringify(metrics.slots) : "");
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
		// The focused item, or the empty cell the cursor is resting on.
		const item = itemRepeater.itemAt(fm.focused_index);
		let focusX, focusY, focusWidth, focusHeight;
		if (item) {
			focusX = item.x;
			focusY = item.y;
			focusWidth = item.width;
			focusHeight = item.height;
		} else if (fm.focus_on_empty) {
			focusX = metrics.offsetX + fm.focused_column * (metrics.itemWidth + metrics.gap);
			focusY = metrics.offsetY + fm.focused_row * (metrics.itemHeight + metrics.gap);
			focusWidth = metrics.itemWidth;
			focusHeight = metrics.itemHeight;
		} else {
			return;
		}

		const viewWidth = flickable.width - metrics.insetX;
		const viewHeight = flickable.height - metrics.insetY;
		let targetY = flickable.contentY;
		let targetX = flickable.contentX;

		if (cfg && cfg.center_focus) {
			targetY = focusY + focusHeight / 2 - viewHeight / 2;
			targetX = focusX + focusWidth / 2 - viewWidth / 2;
		} else {
			const top = focusY;
			const bottom = focusY + focusHeight;
			if (top < flickable.contentY)
				targetY = top;
			else if (bottom > flickable.contentY + viewHeight)
				targetY = bottom - viewHeight;

			const left = focusX;
			const right = focusX + focusWidth;
			if (left < flickable.contentX)
				targetX = left;
			else if (right > flickable.contentX + viewWidth)
				targetX = right - viewWidth;
		}

		targetY = Math.max(0, Math.min(targetY, flickable.contentHeight - flickable.height));
		targetX = Math.max(0, Math.min(targetX, flickable.contentWidth - flickable.width));

		if (Math.abs(targetY - flickable.contentY) < 1 && Math.abs(targetX - flickable.contentX) < 1)
			return;

		if (cfg && cfg.smooth_scrolling) {
			// Mark the motion as focus-driven so the scroll-follow logic leaves
			// it alone while it runs.
			folderView.focusScrollAnimating = true;
			focusScrollY.to = targetY;
			focusScrollY.restart();
			focusScrollX.to = targetX;
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
			folderView.rootWindow.actionManager.activatePath(String(fm.focused_path), itemRepeater.itemAt(fm.focused_index));
	}

	// Called on every scroll position change. Fires periodically during a
	// continuous flick (60 ms after the first change and then again as more
	// arrive), so the cursor tracks the viewport instead of only snapping once
	// the motion stops.
	function scheduleFocusFollow() {
		if (!focusFollowTimer.running)
			focusFollowTimer.start();
	}

	// Keeps the cursor on screen when the user scrolls it out of view, without
	// scrolling back: the cursor moves to the item at the leading edge of the
	// viewport, the one nearest the old cursor on the other axis. Scrolling back
	// toward the start snaps to the trailing edge instead, so the cursor follows
	// the direction the content moved.
	function keepFocusInView() {
		const fm = folderView.focusManager;
		if (!fm || !fm.focus_active || fm.current_pane !== folderView.paneId || !folderView.focusOwned)
			return;
		// Ignore the motion a focus-driven scroll is itself producing.
		if (folderView.focusScrollAnimating)
			return;

		const metrics = folderView.gridMetrics;
		let focusX, focusY, focusWidth, focusHeight;
		const focused = itemRepeater.itemAt(fm.focused_index);
		if (focused) {
			focusX = focused.x;
			focusY = focused.y;
			focusWidth = focused.width;
			focusHeight = focused.height;
		} else if (fm.focus_on_empty) {
			focusX = metrics.offsetX + fm.focused_column * (metrics.itemWidth + metrics.gap);
			focusY = metrics.offsetY + fm.focused_row * (metrics.itemHeight + metrics.gap);
			focusWidth = metrics.itemWidth;
			focusHeight = metrics.itemHeight;
		} else {
			return;
		}

		const left = flickable.contentX;
		const top = flickable.contentY;
		const right = left + flickable.width;
		const bottom = top + flickable.height;

		const offLeft = focusX + focusWidth <= left;
		const offRight = focusX >= right;
		const offTop = focusY + focusHeight <= top;
		const offBottom = focusY >= bottom;
		// Still at least partly on screen: leave the cursor alone.
		if (!offLeft && !offRight && !offTop && !offBottom)
			return;

		const offX = offLeft || offRight;
		const offY = offTop || offBottom;
		let byColumn;
		if (offX && !offY) {
			byColumn = true;
		} else if (offY && !offX) {
			byColumn = false;
		} else {
			const dx = offLeft ? (left - (focusX + focusWidth)) : (focusX - right);
			const dy = offTop ? (top - (focusY + focusHeight)) : (focusY - bottom);
			byColumn = dx >= dy;
		}

		// The side the cursor left from decides which edge to snap to.
		const wantMax = byColumn ? offRight : offBottom;
		const oldCentre = byColumn ? (focusY + focusHeight / 2) : (focusX + focusWidth / 2);

		let best = -1;
		let bestLead = 0;
		let bestAside = Infinity;
		const count = itemRepeater.count;
		for (let i = 0; i < count; i++) {
			const item = itemRepeater.itemAt(i);
			if (!item)
				continue;
			if (item.x + item.width <= left || item.x >= right)
				continue;
			if (item.y + item.height <= top || item.y >= bottom)
				continue;
			const lead = byColumn ? item.x : item.y;
			const aside = byColumn ? (item.y + item.height / 2) : (item.x + item.width / 2);
			const better = best < 0
				|| (wantMax ? lead > bestLead + 1 : lead < bestLead - 1)
				|| (Math.abs(lead - bestLead) <= 1 && Math.abs(aside - oldCentre) < bestAside);
			if (better) {
				best = i;
				bestLead = lead;
				bestAside = Math.abs(aside - oldCentre);
			}
		}

		if (best < 0 || best === fm.focused_index)
			return;
		const item = itemRepeater.itemAt(best);
		if (!item || !item.path)
			return;

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
	function focusSlot(path) {
		const fm = folderView.focusManager;
		if (!fm || !folderView.directory)
			return;
		folderView.forceActiveFocus();
		if (folderView.paneId <= 0)
			return;
		folderView.updateFocusItems();
		if (fm.set_pane_focus_path(folderView.paneId, path))
			Qt.callLater(() => folderView.ensureFocusVisible());
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
		const item = itemRepeater.itemAt(fm.focused_index);
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
		target: itemRepeater
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
		if (metrics.free)
			fm.set_pane_positions(folderView.paneId, JSON.stringify(metrics.slots));
		fm.set_pane_grid(folderView.paneId, metrics.columns, metrics.rows);
		fm.set_pane_empty_slots(folderView.paneId, folderView.focusEmptySlots);
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
			if (fm && fm.current_pane === folderView.paneId) {
				const path = String(fm.focused_path);
				if (path !== "" && path !== folderView.lastFocusSoundPath && !folderView.suppressFocusScroll) {
					folderView.lastFocusSoundPath = path;
					folderView.playSound("item-focus");
				}
			}
			// Keep the window's item actions pointed at the pane holding the
			// cursor, even when the keyboard sits elsewhere (popup, dialog).
			if (fm && folderView.rootWindow && fm.current_pane === folderView.paneId)
				folderView.rootWindow.focusedFolderView = folderView;
			// Follow the cursor when it moves into this pane, but never take the
			// keyboard back from an open popup or a dialog that has taken it.
			if (fm && fm.view_focused && fm.current_pane === folderView.paneId && !folderView.activeFocus
				&& !(folderView.Window.window && folderView.Window.window.activeFocusItem))
				folderView.forceActiveFocus();
			// A scroll-follow move must not trigger the focus-driven scroll that
			// would yank the view back to the cursor.
			if (folderView.focusOwned && fm && fm.current_pane === folderView.paneId && !folderView.suppressFocusScroll)
				folderView.ensureFocusVisible();
		}
		function onAccept_requested() {
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
		function onCancel_requested() {
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

			// Back only sounds, and only goes up, when there is somewhere to go:
			// at the root there is no back, and sounding anyway made every B press
			// feel like an action.
			const am = folderView.rootWindow ? folderView.rootWindow.actionManager : null;
			if (am && am.goUpAction.enabled) {
				folderView.playSound("return");
				am.goUpAction.trigger();
			}
		}
	}


	Timer {
		interval: 400
		running: true
		repeat: true
		onTriggered: {
			if (folderView.directory) {
				folderView.directory.poll_thumbnails();
				folderView.directory.poll_changes();
			}
		}
	}

	// Thumbnails are only requested for the items in (or near) the visible
	// area, like Dolphin does; the backend caches them, so scrolling back is
	// instant and a big folder never gets previewed all at once.
	property var thumbRequested: ({})
	property string thumbRequestKey: ""

	function scheduleThumbnails() {
		thumbnailTimer.restart();
	}

	function requestVisibleThumbnails() {
		const dir = folderView.directory;
		if (!dir || !flickable || flickable.height <= 0 || flickable.width <= 0)
			return;

		const cfg = folderView.config;
		const gridSize = cfg ? cfg.grid_size : 64;
		// Without labels the icons fill their slots, so ask for a thumbnail tier
		// big enough for the whole slot instead of just the icon size.
		const displaySize = cfg && !cfg.show_labels ? folderView.gridItemSize.width : gridSize;
		const bucket = displaySize <= 128 ? 128 : (displaySize <= 256 ? 256 : (displaySize <= 512 ? 512 : 1024));
		const key = String(dir.path) + "|" + bucket;
		if (key !== folderView.thumbRequestKey) {
			folderView.thumbRequestKey = key;
			folderView.thumbRequested = ({});
		}

		const requested = folderView.thumbRequested;
		const metrics = folderView.gridMetrics;
		const margin = Math.max(metrics.itemWidth, metrics.itemHeight);
		const top = flickable.contentY - margin;
		const bottom = flickable.contentY + flickable.height + margin;
		const left = flickable.contentX - margin;
		const right = flickable.contentX + flickable.width + margin;

		const count = itemRepeater.count;
		for (let i = 0; i < count; i++) {
			const item = itemRepeater.itemAt(i);
			if (!item || !item.path || requested[item.path])
				continue;
			if (item.y + item.height < top || item.y > bottom || item.x + item.width < left || item.x > right)
				continue;
			requested[item.path] = true;
			dir.request_thumbnail(item.path, bucket);
		}
	}

	Timer {
		id: thumbnailTimer
		interval: 120
		repeat: false
		onTriggered: folderView.requestVisibleThumbnails()
	}

	Connections {
		target: folderView.directory

		// A rebuild re-resolves every icon to its plain MIME icon, so thumbnail
		// requests must be re-issued for the visible items afterwards.
		function onModelReset() {
			folderView.thumbRequested = ({});
			folderView.thumbRequestKey = "";
			folderView.scheduleThumbnails();
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
			folderView.returnFocusPath = previous;

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
			folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
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
		const count = itemRepeater.count;
		for (let i = 0; i < count; i++) {
			const slot = itemRepeater.itemAt(i);
			if (!slot || !slot.is_dir)
				continue;
			if (x >= slot.x && x <= slot.x + slot.width && y >= slot.y && y <= slot.y + slot.height)
				return slot;
		}
		return null;
	}

	function resetFolderDrop() {
		folderDropTimer.stop();
		if (folderView.folderDropPath !== "")
			folderView.folderDropPath = "";
		if (folderView.folderDropActive)
			folderView.folderDropActive = false;
	}

	function updateFreeDropTarget(x, y) {
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
		if (dirSlot) {
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
		for (let i = 0; i < itemRepeater.count; i++) {
			const item = itemRepeater.itemAt(i);
			if (!item || selected[item.path] === undefined)
			continue;
			const slot = metrics.slots[i];
			if (!slot)
				continue;
			entries.push({ name: selected[item.path], path: item.path, title: item.title, icon: item.icon, c: slot.c, r: slot.r });
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
		folderView.updateFreeDropTarget(local.x, local.y);
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
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
			return;
		}

		folderView.applyRepositionToSlot(slot.col, slot.row);
	}

	// Move the selection to the given slot, preserving its arrangement.
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

		folderView.repositionAnimating = true;
		for (let i = 0; i < entries.length; i++) {
			const e = entries[i];
			folderView.directory.set_free_position(e.name, e.c + dCol, e.r + dRow);
		}
		repositionAnimTimer.restart();
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

			folderView.updateFreeDropTarget(drag.x, drag.y);
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
				drag.accepted = false;
				return;
			}

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
				const action = (typeof dragHandler !== 'undefined' && dragHandler) ? dragHandler.drag_action : "copy";
				if (fileManager.process_uris_action(target, uris, action)) {
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
			const direction = event.key === Qt.Key_Left ? "left" : event.key === Qt.Key_Right ? "right" : event.key === Qt.Key_Up ? "up" : "down";
			fm.move_focus(direction);
			if (shift && fm.focus_active && String(fm.focused_path) !== "") {
				folderView.playSound("item-selected");
				mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
			}
			event.accepted = true;
			break;
		}
		case Qt.Key_Home:
			fm.focus_first();
			event.accepted = true;
			break;
		case Qt.Key_End:
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

	NumberAnimation {
		id: focusScrollY
		target: flickable
		property: "contentY"
		duration: 180
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
		duration: 180
		easing.type: Easing.OutCubic
		onRunningChanged: {
			if (!running && !focusScrollY.running)
				folderView.focusScrollAnimating = false;
		}
	}

	Flickable {
		id: flickable
		z: 1
		clip: true
		anchors {
			top: parent.top
			left: parent.left
			right: parent.right
			bottom: selectionBar.top
			leftMargin: Kirigami.Units.mediumSpacing
			rightMargin: Kirigami.Units.mediumSpacing
			bottomMargin: Kirigami.Units.mediumSpacing
			// The filter bar pushes the grid down while it is up.
			topMargin: folderView.filterActive ? filterBar.height + Kirigami.Units.mediumSpacing * 2 : Kirigami.Units.mediumSpacing
		}

		onHeightChanged: folderView.scheduleThumbnails()
		onWidthChanged: folderView.scheduleThumbnails()
		contentWidth: folderView.gridMetrics.contentWidth
		contentHeight: folderView.gridMetrics.contentHeight

		// Scroll feedback, 3DS style. The view can scroll on either axis — the
		// layout picks which — so this follows whichever position actually
		// moves instead of trusting the config, which described the grid's
		// flow, not the flickable's. One tick fires per item crossed along the
		// moving axis, so a slow drag ticks on the same boundaries as a fast
		// flick. Both axes use the up/down vocabulary: a sideways grid must not
		// sound like a different kind of movement.
		//
		// Reaching either end plays the "edge" sound once, then stays quiet
		// until the position moves away from the end again.
		readonly property real scrollStepX: folderView.gridItemSize.width + Kirigami.Units.mediumSpacing
		readonly property real scrollStepY: folderView.gridItemSize.height + Kirigami.Units.mediumSpacing
		property real scrollRemainderX: 0
		property real scrollRemainderY: 0
		property real lastScrollX: 0
		property real lastScrollY: 0
		property bool atScrollStart: true
		property bool atScrollEnd: true

		function updateScrollEdges() {
			// Whichever axis can actually scroll is the one whose ends matter.
			const maxX = Math.max(0, flickable.contentWidth - flickable.width);
			const maxY = Math.max(0, flickable.contentHeight - flickable.height);
			const horizontal = maxX > 1 && maxY <= 1;
			const vertical = maxY > 1 && maxX <= 1;
			const max = horizontal ? maxX : (vertical ? maxY : Math.max(maxX, maxY));
			if (max <= 1) {
				flickable.atScrollStart = true;
				flickable.atScrollEnd = true;
				return;
			}
			const pos = horizontal ? flickable.contentX : flickable.contentY;
			const wasAtStart = flickable.atScrollStart;
			const wasAtEnd = flickable.atScrollEnd;
			flickable.atScrollStart = pos <= 1;
			flickable.atScrollEnd = pos >= max - 1;
			// Announce only when a real end is *reached*: the start is where the
			// view rests, so arriving back there is not an "edge" event.
			if (flickable.atScrollEnd && !wasAtEnd)
				folderView.playSound("scroll-edge");
			else if (flickable.atScrollStart && !wasAtStart)
				folderView.playSound("scroll-edge");
		}

		function tickAxis(axis) {
			const step = axis === "x" ? flickable.scrollStepX : flickable.scrollStepY;
			if (step <= 0)
				return;
			const pos = axis === "x" ? flickable.contentX : flickable.contentY;
			const last = axis === "x" ? flickable.lastScrollX : flickable.lastScrollY;
			let remainder = (axis === "x" ? flickable.scrollRemainderX : flickable.scrollRemainderY) + (pos - last);
			if (axis === "x") {
				flickable.lastScrollX = pos;
			} else {
				flickable.lastScrollY = pos;
			}
			if (Math.abs(remainder) >= step) {
				// One sound per axis, not per direction: scrolling sideways is
				// one kind of movement (however it is oriented), and scrolling
				// up or down is another. Two sounds total.
				folderView.playSound(axis === "x" ? "scroll-left" : "scroll-up");
				remainder = 0;
			}
			if (axis === "x")
				flickable.scrollRemainderX = remainder;
			else
				flickable.scrollRemainderY = remainder;
			flickable.updateScrollEdges();
		}

		onMovementStarted: {
			flickable.scrollRemainderX = 0;
			flickable.scrollRemainderY = 0;
			flickable.lastScrollX = flickable.contentX;
			flickable.lastScrollY = flickable.contentY;
			flickable.updateScrollEdges();
		}
		onMovementEnded: flickable.updateScrollEdges()

		onContentYChanged: {
			folderView.scheduleThumbnails();
			flickable.tickAxis("y");
			folderView.scheduleFocusFollow();
		}
		onContentXChanged: {
			folderView.scheduleThumbnails();
			flickable.tickAxis("x");
			folderView.scheduleFocusFollow();
		}

		// The panel is touch-only, so use the touch presentation of the bar (a
		// thin, auto-hiding handle with no groove) from the start. The style
		// otherwise picks it only after the first touch, showing the full desktop
		// bar until then.
		ScrollBar.vertical: ScrollBar {
			id: verticalScrollBar
			interactive: false
			policy: size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
			z: 2
		}

		ScrollBar.horizontal: ScrollBar {
			id: horizontalScrollBar
			interactive: false
			policy: size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
			z: 2
		}

		MouseArea {
			id: flickableBgMouseArea
			width: flickable.contentWidth
			height: flickable.contentHeight
			z: 0
			acceptedButtons: Qt.LeftButton
			onClicked: mouse => {
				folderView.forceActiveFocus();
				folderView.selectionManager.clear();
				if (folderView.focusManager)
					folderView.focusManager.clear_pane(folderView.paneId);
			}
		}

		Item {
			id: gridContent
			z: 1
			width: flickable.contentWidth
			height: flickable.contentHeight

			Rectangle {
				id: freeDropHighlight
				z: 0
				visible: folderView.freeDropActive
				width: folderView.gridMetrics.itemWidth
				height: folderView.gridMetrics.itemHeight
				x: folderView.freeDropX
				y: folderView.freeDropY
				radius: Kirigami.Units.cornerRadius
				color: Kirigami.Theme.focusColor
				opacity: 0.35
				border.color: Kirigami.Theme.highlightColor
				border.width: 2
			}

			// An empty free-placement cell has no item to draw the focus border,
			// so it is drawn here from the focused cell.
			Item {
				id: emptyFocusIndicator
				z: 2
				readonly property var fm: folderView.focusManager
				readonly property var metrics: folderView.gridMetrics
				readonly property bool shown: folderView.focusOwned
					&& emptyFocusIndicator.fm
					&& emptyFocusIndicator.fm.focus_active
					&& emptyFocusIndicator.fm.focus_on_empty
					&& emptyFocusIndicator.fm.current_pane === folderView.paneId
				visible: shown
				x: emptyFocusIndicator.fm
					? emptyFocusIndicator.metrics.offsetX + emptyFocusIndicator.fm.focused_column * (emptyFocusIndicator.metrics.itemWidth + emptyFocusIndicator.metrics.gap)
					: 0
				y: emptyFocusIndicator.fm
					? emptyFocusIndicator.metrics.offsetY + emptyFocusIndicator.fm.focused_row * (emptyFocusIndicator.metrics.itemHeight + emptyFocusIndicator.metrics.gap)
					: 0
				width: emptyFocusIndicator.metrics.itemWidth
				height: emptyFocusIndicator.metrics.itemHeight

				readonly property real cornerSize: Math.max(10, Math.round(Math.min(width, height) * 0.3))

				Image {
					anchors.left: parent.left
					anchors.top: parent.top
					width: emptyFocusIndicator.cornerSize
					height: emptyFocusIndicator.cornerSize
					source: folderView.focusBorderSource ? folderView.focusBorderSource + "-0.svg" : ""
					smooth: true
				}

				Image {
					anchors.right: parent.right
					anchors.top: parent.top
					width: emptyFocusIndicator.cornerSize
					height: emptyFocusIndicator.cornerSize
					source: folderView.focusBorderSource ? folderView.focusBorderSource + "-1.svg" : ""
					smooth: true
				}

				Image {
					anchors.right: parent.right
					anchors.bottom: parent.bottom
					width: emptyFocusIndicator.cornerSize
					height: emptyFocusIndicator.cornerSize
					source: folderView.focusBorderSource ? folderView.focusBorderSource + "-2.svg" : ""
					smooth: true
				}

				Image {
					anchors.left: parent.left
					anchors.bottom: parent.bottom
					width: emptyFocusIndicator.cornerSize
					height: emptyFocusIndicator.cornerSize
					source: folderView.focusBorderSource ? folderView.focusBorderSource + "-3.svg" : ""
					smooth: true
				}
			}

			Repeater {
				id: itemRepeater
				model: folderView.directory

				delegate: FileSlot {
					property SelectionManager selectionManager: folderView.selectionManager
					actionManager: folderView.rootWindow ? folderView.rootWindow.actionManager : null
					fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null

					dragDropHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null
					width: folderView.gridItemSize.width
					height: folderView.gridItemSize.height
					x: folderView.gridSlotX(index)
					y: folderView.gridSlotY(index)

					gridSize: folderView.config ? folderView.config.grid_size : 64
					showLabels: folderView.config ? folderView.config.show_labels : true
					labelBesideIcon: folderView.labelsBesideIcons
					labelShowsFilename: folderView.config ? folderView.config.label_text === 1 : false
					selectionActive: selectionManager ? selectionManager.selection_active : false
					focusActive: folderView.focusOwned && folderView.focusManager && folderView.focusManager.current_pane === folderView.paneId
					focusBorderSource: folderView.focusBorderSource
					isFocused: folderView.focusManager ? (folderView.focusManager.focus_active && String(folderView.focusManager.focused_path) === String(path)) : false
					isSelected: selectionManager ? (function () {
							try {
								return !!JSON.parse(selectionManager.selected_paths)[path];
							} catch (e) {
								return false;
							}
						})() : false

					onSelectionToggled: (p, idx) => {
						folderView.forceActiveFocus();
						folderView.playSound("item-selected");
						if (selectionManager) {
							selectionManager.toggle_selection(p, idx);
						}
					}

					onShiftSelected: idx => {
						folderView.forceActiveFocus();
						folderView.playSound("item-selected");
						if (selectionManager) {
							if (!selectionManager.selection_active)
								selectionManager.enter_selection_mode();
							const from = selectionManager.last_selected_index >= 0 ? selectionManager.last_selected_index : idx;
							selectionManager.range_select(from, idx);
						}
					}

					onPressHeld: (p, idx) => {
						folderView.forceActiveFocus();
						folderView.playSound("item-selected");
						if (selectionManager) {
							selectionManager.toggle_selection(p, idx);
						}
					}

					onContextMenuRequested: (slotPath, slotIndex) => {
						folderView.forceActiveFocus();
						if (selectionManager) {
							let isAlreadySelected = false;
							try {
								isAlreadySelected = !!JSON.parse(selectionManager.selected_paths)[slotPath];
							} catch (e) {}
							if (!isAlreadySelected) {
								selectionManager.clear();
								selectionManager.toggle_selection(slotPath, slotIndex);
							}
						}
					}
				}
			}
		}
	}

	// ── Filter Bar ───

	Rectangle {
		id: filterBar
		z: 3

		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.margins: Kirigami.Units.mediumSpacing
		height: Kirigami.Units.gridUnit * 2
		radius: Kirigami.Units.cornerRadius

		visible: opacity > 0
		opacity: folderView.filterActive ? 1 : 0
		Behavior on opacity {
			NumberAnimation {
				duration: 120
				easing.type: Easing.OutCubic
			}
		}

		Kirigami.Theme.colorSet: Kirigami.Theme.Header
		color: Kirigami.Theme.backgroundColor
		border.width: 1
		border.color: Kirigami.Theme.highlightColor

		MouseArea {
			anchors.fill: parent
			acceptedButtons: Qt.AllButtons
			onPressed: mouse => {
				mouse.accepted = true;
				folderView.forceActiveFocus();
			}
		}

		RowLayout {
			anchors.fill: parent
			anchors.leftMargin: Kirigami.Units.largeSpacing
			anchors.rightMargin: Kirigami.Units.smallSpacing
			spacing: Kirigami.Units.smallSpacing

			Kirigami.Icon {
				source: "search"
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Kirigami.Units.iconSizes.small
			}

			Label {
				text: folderView.directory ? String(folderView.directory.filter) : ""
				font.weight: Font.Medium
				elide: Text.ElideRight
				Layout.fillWidth: true
			}

			Label {
				text: itemRepeater.count === 1 ? qsTr("1 match") : qsTr("%1 matches").arg(itemRepeater.count)
				opacity: 0.7
				elide: Text.ElideRight
			}

			ToolButton {
				icon.name: "edit-clear"
				focusPolicy: Qt.NoFocus
				flat: true
				ToolTip.text: qsTr("Clear filter")
				ToolTip.visible: hovered
				onPressed: folderView.playSound("button-pressed")
				onReleased: folderView.playSound("button-released")
				onClicked: {
					folderView.directory.clear_filter();
					folderView.forceActiveFocus();
				}
			}
		}
	}

	// ── Selection Toolbar ───

	Rectangle {id: selectionBar
	z: 2

	anchors.left: parent.left
	anchors.right: parent.right
	anchors.bottom: parent.bottom
	anchors.margins: Kirigami.Units.mediumSpacing

	readonly property bool selectionActive: folderView.selectionManager ? folderView.selectionManager.selection_active : false

	// the labels are dropped so the buttons stay reachable in a narrow pane.
	readonly property bool compact: selectionBar.width < Kirigami.Units.largeSpacing * 50

	height: selectionBar.selectionActive ? 48 : 0
	visible: selectionBar.selectionActive
	radius: 6

	Kirigami.Theme.colorSet: Kirigami.Theme.Header
	color: Kirigami.Theme.backgroundColor

	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.AllButtons
		onClicked: mouse => {
			mouse.accepted = true;
		}
		onPressed: mouse => {
			mouse.accepted = true;
		}
	}

	TextMetrics {
		id: countMetrics
		font: countLabel.font
		text: countLabel.text
	}

	Kirigami.Separator {
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
	}

	Behavior on height {
		NumberAnimation {
			duration: 180
			easing.type: Easing.OutCubic
		}
	}

	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: Kirigami.Units.largeSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing

		CheckBox {
			id: selectAllCheckbox
			checked: folderView.selectionManager.selected_count > 0 && folderView.selectionManager.selected_count === itemRepeater.count
			tristate: folderView.selectionManager.selected_count > 0 && folderView.selectionManager.selected_count < itemRepeater.count
			checkState: tristate ? Qt.PartiallyChecked : (checked ? Qt.Checked : Qt.Unchecked)
			Layout.preferredWidth: Kirigami.Units.iconSizes.medium
			Layout.preferredHeight: Kirigami.Units.iconSizes.medium
			onClicked: {
				if (folderView.selectionManager.selected_count === itemRepeater.count) {
					folderView.selectionManager.deselect_all();
				} else {
					folderView.selectAll();
				}
			}
		}

		Label {
			property string countText: folderView.selectionManager.selected_count + " " + (
				selectionBar.compact
					? ""
					: (folderView.selectionManager.selected_count > 1
						? qsTr("items selected")
						: qsTr("item selected"))
			)
			id: countLabel
			text: countText
			font.weight: Font.Medium
			elide: Text.ElideRight
			Layout.fillWidth: true
			Layout.minimumWidth: selectionBar.compact ? 0 : countMetrics.width
		}

		ToolButton {
			id: deselectAllButton
			text: qsTr("Deselect")
			icon.name: "edit-select-none"
			display: selectionBar.compact ? AbstractButton.IconOnly : AbstractButton.TextUnderIcon
			ToolTip.text: qsTr("Deselect")
			ToolTip.visible: hovered
			flat: true
			onPressed: folderView.playSound("button-pressed")
			onReleased: folderView.playSound("button-released")
			onClicked: folderView.selectionManager.deselect_all()
		}
	}}

	ExecuteDialog {
		id: execDialog
		directory: folderView.directory
		fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null
		window: folderView.rootWindow
	}
}
