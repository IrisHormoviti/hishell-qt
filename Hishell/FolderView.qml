pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: folderView
	property ShellWindow window
	readonly property ShellWindow rootWindow: folderView.window
	property Directory directory
	property Config config: directory.config
	readonly property bool horizontalScroll: folderView.config ? folderView.config.scroll_horizontal : false
	property FocusManager focusManager: folderView.rootWindow ? folderView.rootWindow.focusManager : null
	readonly property string focusBorderSource: folderView.focusManager ? folderView.focusManager.border_source(Kirigami.Theme.highlightColor.toString()) : ""
	property bool focusOwned: false
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

	// Selection state is owned per view so selection mode and the selection
	// toolbar stay inside the pane instead of the whole window.
	SelectionManager {
		id: selectionManagerImpl
	}

	readonly property size gridItemSize: {
		const iconSize = folderView.config ? folderView.config.grid_size : 64;
		if (iconSize < 32)
			return Qt.size(Kirigami.Units.gridUnit * 10, Kirigami.Units.gridUnit * 2);
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
			if (folderView.Window.window.active)
				folderView.forceActiveFocus();
			folderView.updateViewFocus();
		}
	}

	function updateViewFocus() {
		const fm = folderView.focusManager;
		const window = folderView.Window.window;
		if (!fm || folderView.paneId <= 0)
			return;
		// While the window is inactive the controller still drives the file
		// views; only focus owned elsewhere inside an active window (popups,
		// dialogs) hands the input over to Qt.
		fm.set_pane_keyboard(folderView.paneId, folderView.activeFocus || !(window && window.active));
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
		const item = itemRepeater.itemAt(fm.focused_index);
		if (!item)
			return;

		const cfg = folderView.config;
		const metrics = folderView.gridMetrics;
		const viewWidth = flickable.width - metrics.insetX;
		const viewHeight = flickable.height - metrics.insetY;
		let targetY = flickable.contentY;
		let targetX = flickable.contentX;

		if (cfg && cfg.center_focus) {
			targetY = item.y + item.height / 2 - viewHeight / 2;
			targetX = item.x + item.width / 2 - viewWidth / 2;
		} else {
			const top = item.y;
			const bottom = item.y + item.height;
			if (top < flickable.contentY)
				targetY = top;
			else if (bottom > flickable.contentY + viewHeight)
				targetY = bottom - viewHeight;

			const left = item.x;
			const right = item.x + item.width;
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
			folderView.rootWindow.actionManager.openAction.execute(String(fm.focused_path), itemRepeater.itemAt(fm.focused_index), false);
	}

	// Enter / gamepad accept: toggle the focused item in selection mode, otherwise open it
	function activateFocused() {
		const fm = folderView.focusManager;
		const mgr = folderView.selectionManager;
		if (!fm || !fm.focus_active || String(fm.focused_path) === "")
			return;
		if (mgr && mgr.selection_active) {
			mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
			return;
		}
		folderView.openFocused();
	}

	// Context menu for the focused item, shared by the gamepad menu button and
	// the Menu key.
	function openFocusedMenu() {
		const fm = folderView.focusManager;
		if (!folderView.focusOwned || !fm || !fm.focus_active || fm.current_pane !== folderView.paneId)
			return;
		const item = itemRepeater.itemAt(fm.focused_index);
		if (item)
			folderView.openMenu = item.openContextMenu();
	}

	// Context menu for the folder being viewed, opened by the gamepad start
	// button.
	function openDirectoryMenu() {
		if (folderView.rootWindow)
			folderView.rootWindow.actionManager.pasteTargetPath = "";
		const menu = ContextMenu.menu;
		if (!menu)
			return;
		const position = folderView.mapToItem(menu.parent, 0, 0);
		menu.x = position.x;
		menu.y = position.y;
		menu.open();
		folderView.openMenu = menu;
	}

	Component.onCompleted: {
		Qt.callLater(() => {
			const window = folderView.Window.window;
			// The layout creates one view after another; only the first one
			// claims the keyboard, the rest leave it alone.
			if (!window || !window.activeFocusItem)
				folderView.forceActiveFocus();
			if (folderView.focusManager)
				folderView.paneId = folderView.focusManager.register_pane();
			folderView.updateViewFocus();
			folderView.updateGeometry();
			if (folderView.config && folderView.directory) {
				folderView.config.load(folderView.directory.path);
				folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
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
			if (folderView.rootWindow && folderView.selectionManager.selection_active)
				folderView.rootWindow.selectionManager = folderView.selectionManager;
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
			if (folderView.rootWindow)
				folderView.rootWindow.selectionManager = folderView.selectionManager;
		}
	}

	Connections {
		target: itemRepeater
		function onCountChanged() {
			folderView.updateFocusItems();
		}
	}







	onGridStrideChanged: {
		if (folderView.focusOwned && folderView.focusManager && folderView.paneId > 0)
			folderView.focusManager.set_pane_columns(folderView.paneId, folderView.gridStride);
	}

	Connections {
		target: folderView.focusManager
		function onFocus_changed() {
			const fm = folderView.focusManager;
			// Follow the cursor when it moves into this pane, but never take the
			// keyboard back from an open popup.
			if (fm && fm.view_focused && fm.current_pane === folderView.paneId && !folderView.activeFocus)
				folderView.forceActiveFocus();
			if (folderView.focusOwned && fm && fm.current_pane === folderView.paneId)
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
			if (mgr && fm && fm.focus_active && String(fm.focused_path) !== "")
				mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
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

			const mgr = folderView.selectionManager;
			if (mgr && mgr.selection_active) {
				mgr.exit_selection_mode();
				return;
			}

			if (folderView.rootWindow && folderView.rootWindow.actionManager)
				folderView.rootWindow.actionManager.goUpAction.trigger();
		}
	}


	Timer {
		interval: 400
		running: true
		repeat: true
		onTriggered: {
			if (folderView.directory) {
				folderView.directory.poll_thumbnails();
			}
		}
	}

	Connections {
		target: folderView.directory

		function onPathChanged() {
			const previous = folderView.lastPath;
			folderView.lastPath = String(folderView.directory.path);
			folderView.returnFocusPath = previous;

			if (folderView.config && folderView.directory) {
				folderView.config.load(folderView.directory.path);
				folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
			}
			if (folderView.focusManager)
				folderView.focusManager.clear_pane(folderView.paneId);
			// Entering a folder leaves the focus inactive, so no border shows
			// until the next directional input; a restored target activates it.
			folderView.updateFocusItems();
			if (folderView.selectionManager)
				folderView.selectionManager.exit_selection_mode();
		}

		function onConfig_changed() {
			folderView.directory.load_directory(folderView.directory.path, !folderView.config.stash_dotfiles);
			folderView.updateFocusItems();
		}
	}

	readonly property string folderName: {
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

	ContextMenu.menu: ShellContextMenu {
		actionManager: folderView.rootWindow.actionManager
		targetIsBackground: true
	}
	ContextMenu.onRequested: {
		if (folderView.rootWindow)
			folderView.rootWindow.actionManager.pasteTargetPath = "";
	}

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

	function updateFreeDropTarget(x, y) {
		const metrics = folderView.gridMetrics;
		if (!metrics.free) {
			folderView.freeDropCol = -1;
			folderView.freeDropRow = -1;
			return;
		}
		const local = bgDropArea.mapToItem(gridContent, x, y);
		let col = Math.round((local.x - metrics.offsetX) / (metrics.itemWidth + metrics.gap));
		let row = Math.round((local.y - metrics.offsetY) / (metrics.itemHeight + metrics.gap));
		folderView.freeDropCol = Math.max(0, Math.min(metrics.columns - 1, col));
		folderView.freeDropRow = Math.max(0, Math.min(metrics.rows - 1, row));
	}

	function repositionDroppedItems(drop) {
		const cfg = folderView.config;
		if (!cfg || cfg.sort !== 3 || cfg.view_mode !== 0)
			return false;
		const metrics = folderView.gridMetrics;
		if (!metrics.free || !metrics.slots)
			return false;
		const handler = folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null;
		if (!handler || !handler.drag_source_paths || handler.drag_source_paths.length === 0)
			return false;

		const dirPath = String(folderView.directory.path);
		const local = bgDropArea.mapToItem(gridContent, drop.x, drop.y);
		let col = Math.round((local.x - metrics.offsetX) / (metrics.itemWidth + metrics.gap));
		let row = Math.round((local.y - metrics.offsetY) / (metrics.itemHeight + metrics.gap));
		col = Math.max(0, Math.min(metrics.columns - 1, col));
		row = Math.max(0, Math.min(metrics.rows - 1, row));

		let moved = false;
		let placed = 0;
		for (let i = 0; i < handler.drag_source_paths.length; i++) {
			const sp = String(handler.drag_source_paths[i]);
			const sep = sp.lastIndexOf("/");
			if (sep < 0 || sp.substring(0, sep) !== dirPath)
				continue;
			const name = sp.substring(sep + 1);
			const c = col + (placed % metrics.columns);
			const r = row + Math.floor((col + placed) / metrics.columns);
			folderView.directory.set_free_position(name, c, r);
			moved = true;
			placed++;
		}
		return moved;
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

			if (folderView.isFreeRepositionDrop(sourcePaths)) {
				folderView.updateFreeDropTarget(drag.x, drag.y);
				bgDropArea.isHovered = false;
				if (typeof dragHandler !== 'undefined' && dragHandler) {
					dragHandler.reposition_active = true;
					dragHandler.tooltip_active = true;
				}
				drag.accept();
				return;
			}

			if (!folderView.isDropValid(folderView.directory.path, sourcePaths)) {
				bgDropArea.isHovered = false;
				if (typeof dragHandler !== 'undefined' && dragHandler)
					dragHandler.tooltip_active = false;
				drag.accepted = false;
				return;
			}

			bgDropArea.isHovered = true;
			if (typeof dragHandler !== 'undefined' && dragHandler) {
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
			if (typeof dragHandler !== 'undefined' && dragHandler) {
				dragHandler.tooltip_active = false;
				dragHandler.reposition_active = false;
			}
		}

		onDropped: drop => {
			bgDropArea.isHovered = false;
			folderView.freeDropCol = -1;
			folderView.freeDropRow = -1;
			if (typeof dragHandler !== 'undefined' && dragHandler) {
				dragHandler.tooltip_active = false;
				dragHandler.reposition_active = false;
			}

			if (folderView.repositionDroppedItems(drop)) {
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
				const action = (typeof dragHandler !== 'undefined' && dragHandler) ? dragHandler.drag_action : "copy";
				if (fileManager.process_uris_action(folderView.directory.path, uris, action)) {
					folderView.directory.reload();
				}
				drop.accept();
			}
		}
	}

	DragTooltip {
		property var dragHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null

		active: dragHandler ? dragHandler.tooltip_active : false
		action: dragHandler ? dragHandler.drag_action : "copy"
		reposition: dragHandler ? dragHandler.reposition_active : false
		cursorX: dragHandler ? dragHandler.drag_cursor_x + 16 : 0
		cursorY: dragHandler ? dragHandler.drag_cursor_y + 16 : 0
	}

	// ── Input Shortcuts ───
	Keys.onPressed: event => {
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
			if (shift && fm.focus_active && String(fm.focused_path) !== "")
				mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
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
	}

	NumberAnimation {
		id: focusScrollX
		target: flickable
		property: "contentX"
		duration: 180
		easing.type: Easing.OutCubic
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
		}
		anchors.margins: Kirigami.Units.mediumSpacing
		contentWidth: folderView.gridMetrics.contentWidth
		contentHeight: folderView.gridMetrics.contentHeight

		ScrollBar.vertical: ScrollBar {
			id: verticalScrollBar
			policy: size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
			z: 2
		}

		ScrollBar.horizontal: ScrollBar {
			id: horizontalScrollBar
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

			Repeater {
				id: itemRepeater
				model: folderView.directory

				delegate: FileSlot {
					property SelectionManager selectionManager: folderView.selectionManager
					actionManager: folderView.rootWindow ? folderView.rootWindow.actionManager : null
					fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null

					dragDropHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null
					width: labelBesideIcon ? Kirigami.Units.gridUnit * 10 : gridSize + Kirigami.Units.gridUnit * 3
					height: labelBesideIcon ? Kirigami.Units.gridUnit * 2 : gridSize + Kirigami.Units.gridUnit * 3
					x: folderView.gridSlotX(index)
					y: folderView.gridSlotY(index)

					gridSize: folderView.config.grid_size
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
						if (selectionManager) {
							selectionManager.toggle_selection(p, idx);
						}
					}

					onShiftSelected: idx => {
						folderView.forceActiveFocus();
						if (selectionManager) {
							if (!selectionManager.selection_active)
								selectionManager.enter_selection_mode();
							const from = selectionManager.last_selected_index >= 0 ? selectionManager.last_selected_index : idx;
							selectionManager.range_select(from, idx);
						}
					}

					onPressHeld: (p, idx) => {
						folderView.forceActiveFocus();
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

	// ── Selection Toolbar ───

	Rectangle {
		id: selectionBar
		z: 2

		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.margins: 4
		anchors.bottomMargin: 4

		readonly property bool selectionActive: folderView.selectionManager ? folderView.selectionManager.selection_active : false

		// Width the row needs to show the buttons with their labels. Below it
		// the labels are dropped so the buttons stay reachable in a narrow pane.
		readonly property bool compact: selectionBar.width < selectionBar.expandedMinWidth
		readonly property real expandedMinWidth: {
			const spacing = Kirigami.Units.smallSpacing;
			const pad = Kirigami.Units.smallSpacing * 2;
			const icon = Kirigami.Units.iconSizes.small;
			const margins = Kirigami.Units.largeSpacing + Kirigami.Units.smallSpacing;
			const safety = Kirigami.Units.gridUnit * 2;
			const label = Math.max(countMetrics.width, Kirigami.Units.gridUnit * 4);
			const selectAll = Math.max(icon, selectAllMetrics.width) + pad;
			const deselectAll = Math.max(icon, deselectAllMetrics.width) + pad;
			return margins + icon + spacing + label + spacing + selectAll + spacing + deselectAll + safety;
		}

		height: selectionBar.selectionActive ? 48 : 0
		visible: selectionBar.selectionActive
		radius: 6

		Kirigami.Theme.colorSet: Kirigami.Theme.Header
		color: Kirigami.Theme.backgroundColor

		TextMetrics {
			id: countMetrics
			font: countLabel.font
			text: countLabel.text
		}

		TextMetrics {
			id: selectAllMetrics
			font: selectAllButton.font
			text: selectAllButton.text
		}

		TextMetrics {
			id: deselectAllMetrics
			font: deselectAllButton.font
			text: deselectAllButton.text
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

			Kirigami.Icon {
				source: "checkmark"
				Layout.preferredWidth: Kirigami.Units.iconSizes.small
				Layout.preferredHeight: Kirigami.Units.iconSizes.small
			}

			Label {
				id: countLabel
				text: {
					const n = folderView.selectionManager ? folderView.selectionManager.selected_count : 0;
					return n === 1 ? qsTr("1 item selected") : qsTr("%1 items selected").arg(n);
				}
				font.weight: Font.Medium
				elide: Text.ElideRight
				Layout.fillWidth: true
				Layout.minimumWidth: selectionBar.compact ? 0 : countMetrics.width
			}

			ToolButton {
				id: selectAllButton
				text: qsTr("Select All")
				icon.name: "edit-select-all"
				display: selectionBar.compact ? AbstractButton.IconOnly : AbstractButton.TextUnderIcon
				ToolTip.text: qsTr("Select All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.selectAll()
			}

			ToolButton {
				id: deselectAllButton
				text: qsTr("Deselect All")
				icon.name: "edit-select-none"
				display: selectionBar.compact ? AbstractButton.IconOnly : AbstractButton.TextUnderIcon
				ToolTip.text: qsTr("Deselect All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.selectionManager.deselect_all()
			}
		}
	}

	ExecuteDialog {
		id: execDialog
		directory: folderView.directory
		fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null
	}
}