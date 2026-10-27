// The scrollable grid of items: the layout maths, the view itself, the scroll
// feedback, the focus border and the visible-area thumbnail requests. Split out
// of FolderView, which owns the directory, the selection, the drop handling and
// the keyboard.
//
// Two views, because free placement and laziness pull in opposite directions:
//
//   * A normal grid uses a GridView, which instantiates only the items on screen
//     and recycles them. A folder of thousands therefore opens as fast as one of
//     ten; an eager view paid for every item in the folder up front.
//   * Free placement puts items at arbitrary cells from a stored layout, which a
//     GridView cannot do (it owns delegate positions), so that mode keeps an
//     explicit Repeater. It is the uncommon mode, and the user chose the layout.
//
// Only the active view is given a model, so the inactive one holds no items.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Item {
	id: grid

	property Directory directory
	property Config config
	property FocusManager focusManager
	property SelectionManager selectionManager
	// The root window, for the action manager, the file manager and drag state.
	property var window
	property int paneId: -1
	property bool focusOwned: false
	property bool filterActive: false
	property string focusBorderSource: ""
	property bool horizontalScroll: false
	property bool focusEmptySlots: false
	// The free-placement drop cell, driven by the view's drop handling.
	property int freeDropCol: -1
	property int freeDropRow: -1
	// Whether a reposition animation is in flight, so slots animate their x/y.
	property bool repositionAnimating: false

	// Item interactions. The view performs them, because they need the keyboard,
	// the selection and the event sounds, all of which it owns.
	signal itemSelectionToggled(string path, int index)
	signal itemShiftSelected(int index)
	signal itemPressHeld(string path, int index)
	signal itemContextMenuRequested(string path, int index)
	signal backgroundClicked()
	// The viewport moved (a touch scroll, a fling, a scrollbar jump). The view
	// uses it to keep the cursor on a fully visible item.
	signal viewportScrolled()
	// A touch drag or its fling finished. The view re-settles the cursor at
	// once, before the border is shown again.
	signal scrollEnded()

	// True while a touch drag or its fling moves the viewport. The focus border
	// hides for the gesture: the cursor follows the viewport, and a border
	// sliding from item to item while the content moves reads as jitter.
	// Keyboard navigation scrolls through the focus animation instead, which
	// never sets this, so the border keeps following the cursor there.
	property bool userScrolling: false

	function playSound(name) {
		if (grid.window && grid.window.sound)
			grid.window.sound.play(name);
	}

	// A scroll tick is only feedback while the content is moving: give it a
	// short deadline in the sound queue, so the end of a fling is silent
	// instead of playing back the ticks it outran.
	function playScrollSound(name) {
		if (grid.window && grid.window.sound)
			grid.window.sound.play_transient(name);
	}

	readonly property bool freeGrid: grid.config ? (grid.config.sort === 3 && grid.config.view_mode === 0) : false
	// A list is a single column of full-width rows. It keeps the grid's focus,
	// selection and drag interaction but replaces the cell maths with rows.
	readonly property bool listMode: grid.config ? grid.config.view_mode === 1 : false
	// Grouped folders use an explicit layout: a section header is not item
	// sized, and a GridView cannot reserve a row for one. Free placement is
	// never grouped.
	readonly property bool grouped: grid.config
		? (!grid.freeGrid && (grid.config.group_mode > 0 || grid.config.show_stash))
		: false
	readonly property real groupHeaderSize: Math.max(Kirigami.Units.gridUnit * 1.45, 20)
	readonly property real listRowHeight: Math.max(Kirigami.Units.gridUnit * 2.6, 44)
	readonly property real listIconSize: Math.max(16, Math.min(28, grid.listRowHeight - Kirigami.Units.largeSpacing))
	readonly property real listPadding: Kirigami.Units.smallSpacing * 2
	readonly property real listHeaderHeight: Kirigami.Units.gridUnit * 2
	readonly property bool showListHeader: grid.config ? grid.config.list_header : true
	readonly property bool listHeaderVisible: grid.listMode && grid.showListHeader && grid.count > 0
	// Columns in display order. TITLE/FILENAME are the name columns; at least
	// one is kept so list rows always have a label.
	readonly property var listColumnKeys: {
		const cfg = grid.config;
		if (!cfg)
			return ["TITLE"];
		let parsed = [];
		try {
			parsed = JSON.parse(String(cfg.list_columns));
		} catch (e) {
			parsed = [];
		}
		if (!Array.isArray(parsed))
			parsed = [];
		const known = {
			"TITLE": true, "FILENAME": true, "COMMENT": true, "SIZE": true,
			"MODIFIED": true, "CREATED": true, "ACCESSED": true, "TYPE": true
		};
		const seen = {};
		const keys = [];
		for (const value of parsed) {
			const key = String(value).toUpperCase();
			if (!known[key] || seen[key])
				continue;
			seen[key] = true;
			keys.push(key);
		}
		if (!keys.some(key => key === "TITLE" || key === "FILENAME"))
			keys.unshift("TITLE");
		return keys;
	}
	// The normalised columns together with the layout weight and alignment the
	// header and row share. Title/Filename get the largest weight, so a name
	// stays the wide column on a narrow pane.
	readonly property var listColumnSpecs: {
		const weights = {
			"TITLE": 4.0, "FILENAME": 4.0, "COMMENT": 3.2, "SIZE": 1.0,
			"MODIFIED": 1.8, "CREATED": 1.8, "ACCESSED": 1.8, "TYPE": 1.0
		};
		const labels = {
			"TITLE": qsTr("Title"),
			"FILENAME": qsTr("File Name"),
			"COMMENT": qsTr("Comment"),
			"SIZE": qsTr("Size"),
			"MODIFIED": qsTr("Modified"),
			"CREATED": qsTr("Created"),
			"ACCESSED": qsTr("Accessed"),
			"TYPE": qsTr("Type")
		};
		const specs = [];
		const keys = grid.listColumnKeys;
		for (let i = 0; i < keys.length; i++) {
			const key = keys[i];
			specs.push({
				key: key,
				title: labels[key] || key,
				weight: weights[key] || 1.0,
				align: key === "SIZE" ? Text.AlignRight : Text.AlignLeft,
				nameColumn: key === "TITLE" || key === "FILENAME"
			});
		}
		return specs;
	}
	// Space kept clear for the vertical scrollbar; rows stop before it instead
	// of sliding underneath.
	readonly property real listBarInset: listVerticalScrollBar.width + Kirigami.Units.mediumSpacing
	// A fixed line count (Folder View > Lines). The GridView wraps by its own
	// size, so with a count set the view has to be sized to exactly that many
	// cells; see the view margins below.
	readonly property bool fixedLines: grid.config ? grid.config.grid_lines > 0 : false

	// The item cell size: icon plus room for the label, or a wide row when the
	// label sits beside the icon.
	readonly property size gridItemSize: {
		const iconSize = grid.config ? grid.config.grid_size : 64;
		const beside = grid.labelsBesideIcons;
		if (beside) {
			const labelWidth = Kirigami.Units.gridUnit * 7;
			return Qt.size(Math.max(Kirigami.Units.gridUnit * 10, iconSize + labelWidth + Kirigami.Units.gridUnit * 2), Math.max(Kirigami.Units.gridUnit * 2, iconSize + Kirigami.Units.smallSpacing * 2));
		}
		return Qt.size(iconSize + Kirigami.Units.gridUnit * 3, iconSize + Kirigami.Units.gridUnit * 3);
	}

	readonly property bool labelsBesideIcons: {
		const cfg = grid.config;
		if (!cfg || !cfg.show_labels)
			return false;
		return cfg.grid_labels_beside_icons || cfg.grid_size < 32;
	}

	// The view actually in charge; free placement, grouping, the list and the
	// normal grid never share one, so scroll and focus code goes through this.
	readonly property var flickable: grid.freeGrid
		? freeFlickable
		: (grid.grouped ? groupedFlickable : (grid.listMode ? listView : gridView))
	// Content item the drop handling maps coordinates into.
	readonly property var gridContent: grid.freeGrid
		? freeGridContent
		: (grid.grouped ? groupedContent : (grid.listMode ? listView.contentItem : gridView.contentItem))
	readonly property int count: grid.freeGrid
		? freeRepeater.count
		: (grid.grouped ? groupedRepeater.count : (grid.listMode ? listView.count : gridView.count))
	readonly property int gridStride: grid.gridMetrics.stride
	// Width of the vertical scrollbar in the active view, for the pane's fixed
	// grid width.
	readonly property real verticalBarWidth: grid.freeGrid ? freeVerticalScrollBar.width : (grid.listMode ? listVerticalScrollBar.width : verticalScrollBar.width)

	readonly property var gridMetrics: {
		const cfg = grid.config;
		const horizontal = cfg ? cfg.scroll_horizontal : false;
		const count = grid.count;
		const viewWidth = grid.width;
		const viewHeight = grid.height;
		const gap = Kirigami.Units.mediumSpacing;
		const itemWidth = grid.gridItemSize.width;
		const itemHeight = grid.gridItemSize.height;
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
			const json = grid.directory.free_layout(
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

		function measureGrouped(insetX, insetY) {
			const list = grid.listMode;
			const tableInset = list && grid.listHeaderVisible ? grid.listHeaderHeight : 0;
			const width = list
				? Math.max(1, viewWidth - grid.listBarInset)
				: Math.max(1, viewWidth - insetX);
			const height = Math.max(1, viewHeight - insetY - tableInset);
			const rowWidth = Math.max(1, viewWidth - grid.listBarInset);
			const json = grid.directory.group_layout(
				horizontal,
				width,
				height,
				list ? rowWidth : itemWidth,
				list ? grid.listRowHeight : itemHeight,
				gap,
				grid.groupHeaderSize,
				cfg ? cfg.grid_lines : 0,
				list
			);
			let parsed = null;
			try {
				parsed = JSON.parse(json);
			} catch (e) {
				parsed = null;
			}
			if (!parsed)
				parsed = { stride: 1, columns: 1, rows: 0, slots: [], groups: [], naturalWidth: 0, naturalHeight: 0 };
			return {
				width: width,
				height: height,
				stride: parsed.stride,
				columns: parsed.columns,
				rows: parsed.rows,
				itemWidth: list ? rowWidth : itemWidth,
				itemHeight: list ? grid.listRowHeight : itemHeight,
				naturalWidth: parsed.naturalWidth,
				naturalHeight: parsed.naturalHeight,
				slots: parsed.slots || [],
				groups: parsed.groups || [],
				grouped: true,
				free: false
			};
		}

		function measure(insetX, insetY) {
			const width = viewWidth - insetX;
			const height = viewHeight - insetY;
			if (grid.grouped) {
				return measureGrouped(insetX, insetY);
			}
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
			// A fixed Lines count is a cap, not a promise: the pane may not have
			// room for that many lines. Clamp it so the layout maths and the
			// GridView (which wraps by its own size) agree even then.
			const fitting = Math.max(1, Math.floor((viewMain + gap) / (itemMain + gap)));
			const stride = lines > 0 ? Math.min(lines, fitting) : fitting;
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
				contentHeight: viewHeight,
				free: false,
				grouped: false,
				slots: [],
				groups: []
			};
		}

		// The list is one column of rows. Its items fill the table width minus
		// the scrollbar strip; the row height is independent of the grid icon
		// size.
		if (grid.listMode) {
			const rowWidth = Math.max(1, viewWidth - grid.listBarInset);
			const rowHeight = grid.listRowHeight;
			return {
				horizontal: false,
				stride: 1,
				columns: 1,
				rows: count,
				itemWidth: rowWidth,
				itemHeight: rowHeight,
				gap: gap,
				insetX: grid.listBarInset,
				insetY: 0,
				offsetX: 0,
				offsetY: 0,
				contentWidth: viewWidth,
				contentHeight: Math.max(viewHeight - (grid.listHeaderVisible ? grid.listHeaderHeight : 0), count * rowHeight + Math.max(0, count - 1) * gap),
				free: false,
				slots: []
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
			contentHeight: Math.max(metrics.grouped ? metrics.height : viewHeight, metrics.naturalHeight + insetY),
			free: metrics.free === true,
			grouped: metrics.grouped === true,
			slots: metrics.slots ? metrics.slots : [],
			groups: metrics.groups ? metrics.groups : []
		};
	}

	readonly property bool freeDropActive: grid.freeDropCol >= 0 && grid.freeDropRow >= 0 && grid.gridMetrics.free

	readonly property real freeDropX: {
		const metrics = grid.gridMetrics;
		return metrics.offsetX + grid.freeDropCol * (metrics.itemWidth + metrics.gap);
	}

	readonly property real freeDropY: {
		const metrics = grid.gridMetrics;
		return metrics.offsetY + grid.freeDropRow * (metrics.itemHeight + metrics.gap);
	}

	function gridSlotX(index) {
		const metrics = grid.gridMetrics;
		const slot = metrics.slots ? metrics.slots[index] : null;
		if ((metrics.free || metrics.grouped) && slot) {
			if (slot.x !== undefined)
				return metrics.offsetX + slot.x;
			return metrics.offsetX + slot.c * (metrics.itemWidth + metrics.gap);
		}
		const column = metrics.horizontal ? Math.floor(index / metrics.rows) : index % metrics.columns;
		return metrics.offsetX + column * (metrics.itemWidth + metrics.gap);
	}

	function gridSlotY(index) {
		const metrics = grid.gridMetrics;
		const slot = metrics.slots ? metrics.slots[index] : null;
		if ((metrics.free || metrics.grouped) && slot) {
			if (slot.y !== undefined)
				return metrics.offsetY + slot.y;
			return metrics.offsetY + slot.r * (metrics.itemHeight + metrics.gap);
		}
		const row = metrics.horizontal ? index % metrics.rows : Math.floor(index / metrics.columns);
		return metrics.offsetY + row * (metrics.itemHeight + metrics.gap);
	}

	// The live delegate for an item index, when it exists. Only visible items are
	// instantiated in the GridView, so callers must handle null.
	function slotAt(index) {
		if (grid.freeGrid)
			return freeRepeater.itemAt(index);
		if (grid.grouped)
			return groupedRepeater.itemAt(index);
		return grid.listMode ? listView.itemAtIndex(index) : gridView.itemAtIndex(index);
	}

	// ── Progressive delegate fill ──
	// The model exposes the whole listing so scroll geometry is final, but a
	// delegate starts as an empty slot at its final size. This timer fills the
	// slots that are on screen with a small per-frame budget. Its work is
	// bounded by the viewport (plus a row of prefetch), not by folder size, so
	// a thousand-item folder costs the same as a ten-item one.
	function schedulePopulate() {
		if (!populateTimer.running)
			populateTimer.start();
	}

	function populateSome() {
		const started = Date.now();
		if (grid.freeGrid || grid.grouped) {
			// Free placement and grouped folders lay every item out
			// explicitly, but only the ones near the viewport need their
			// content yet.
			const view = grid.flickable;
			const repeater = grid.freeGrid ? freeRepeater : groupedRepeater;
			const count = repeater.count;
			const margin = grid.gridMetrics.itemWidth;
			const left = view.contentX - margin;
			const top = view.contentY - margin;
			const right = view.contentX + view.width + margin;
			const bottom = view.contentY + view.height + margin;
			let filled = 0;
			for (let i = 0; i < count; i++) {
				const slot = repeater.itemAt(i);
				if (!slot || slot.populateReady !== false)
					continue;
				if (slot.x + slot.width < left || slot.x > right
					|| slot.y + slot.height < top || slot.y > bottom)
					continue;
				slot.populateReady = true;
				filled++;
				if (Date.now() - started >= 5)
					break;
			}
			if (filled > 0 && grid.window && grid.window.fileManager && grid.window.fileManager.perf_mode() > 0)
				grid.window.fileManager.perf_log("populate " + filled + " slots in " + (Date.now() - started) + "ms");
			if (filled === 0)
				populateTimer.stop();
			return;
		}
		const view = grid.listMode ? listView : gridView;
		const content = view ? view.contentItem : null;
		if (!content) {
			populateTimer.stop();
			return;
		}
		// Walk the live delegates instead of asking `indexAt()` for the range.
		// The grid block is inset from the view's origin, so a corner probe can
		// land in the margin and return -1 even though the screen is full of
		// items; that left the slots empty forever. GridView only instantiates
		// visible (and cache) delegates, so this loop is bounded by the screen,
		// not by the folder size.
		const children = content.children;
		let filled = 0;
		for (let i = 0; i < children.length; i++) {
			const slot = children[i];
			if (!slot || slot.populateReady !== false)
				continue;
			slot.populateReady = true;
			filled++;
			if (Date.now() - started >= 5)
				break;
		}
		if (filled > 0 && grid.window && grid.window.fileManager && grid.window.fileManager.perf_mode() > 0)
			grid.window.fileManager.perf_log("populate " + filled + " slots in " + (Date.now() - started) + "ms");
		// The next viewport move or delegate completion asks again when more
		// slots come into view.
		if (filled === 0)
			populateTimer.stop();
	}

	Timer {
		id: populateTimer
		interval: 12
		repeat: true
		running: false
		onTriggered: grid.populateSome()
	}

	// ── Thumbnails ──
	// Only the items in (or near) the visible area are requested, like Dolphin
	// does; the backend caches them, so scrolling back is instant and a big folder
	// never gets previewed all at once.
	property var thumbRequested: ({})
	property string thumbRequestKey: ""

	function scheduleThumbnails() {
		thumbnailTimer.restart();
	}

	function requestVisibleThumbnails() {
		const dir = grid.directory;
		const view = grid.flickable;
		if (!dir || !view || view.height <= 0 || view.width <= 0)
			return;

		const cfg = grid.config;
		const gridSize = cfg ? cfg.grid_size : 64;
		// Without labels the icons fill their slots, so ask for a thumbnail tier
		// big enough for the whole slot instead of just the icon size.
		const displaySize = cfg && !cfg.show_labels ? grid.gridItemSize.width : gridSize;
		const bucket = displaySize <= 128 ? 128 : (displaySize <= 256 ? 256 : (displaySize <= 512 ? 512 : 1024));
		const key = String(dir.path) + "|" + bucket;
		if (key !== grid.thumbRequestKey) {
			grid.thumbRequestKey = key;
			grid.thumbRequested = ({});
		}

		const requested = grid.thumbRequested;
		const metrics = grid.gridMetrics;
		const margin = Math.max(metrics.itemWidth, metrics.itemHeight);
		const top = view.contentY - margin;
		const bottom = view.contentY + view.height + margin;
		const left = view.contentX - margin;
		const right = view.contentX + view.width + margin;

		// Only the delegates around the viewport can have items. Asking
		// `slotAt` for every index made a big folder pay for a thousand QML
		// calls each time the view stopped moving; indexAt brackets the visible
		// range so the loop is a screen's worth even for thousands of files.
		let first = 0;
		let last = grid.count - 1;
		const flickable = view;
		if (flickable && typeof flickable.indexAt === "function") {
			const start = flickable.indexAt(flickable.contentX, flickable.contentY);
			const end = flickable.indexAt(flickable.contentX + flickable.width - 1,
				flickable.contentY + flickable.height - 1);
			if (start >= 0) {
				first = Math.max(0, Math.min(start, end >= 0 ? end : start) - 4);
				last = Math.min(grid.count - 1, Math.max(start, end >= 0 ? end : start) + 4);
			}
		}
		for (let i = first; i <= last; i++) {
			const item = grid.slotAt(i);
			if (!item || !item.path || requested[item.path])
				continue;
			if (item.y + item.height < top || item.y > bottom || item.x + item.width < left || item.x > right)
				continue;
			requested[item.path] = true;
			dir.request_thumbnail(item.path, bucket);
			// Descriptors (a ROM's title and artwork) are generated for what
			// the user can see, not for a whole folder at once.
			dir.request_descriptor(item.path);
		}
	}

	Timer {
		id: thumbnailTimer
		interval: 120
		repeat: false
		onTriggered: grid.requestVisibleThumbnails()
	}

	Connections {
		target: grid.directory
		// A rebuild re-resolves every icon to its plain MIME icon, so thumbnail
		// requests must be re-issued for the visible items afterwards. It also
		// re-lays the view out from the top, which is not a scroll: baseline the
		// tracker so the move to the restored item is not mistaken for one and
		// does not tick a sound for every row it passes.
		function onModelReset() {
			grid.thumbRequested = ({});
			grid.thumbRequestKey = "";
			grid.scheduleThumbnails();
			grid.schedulePopulate();
			grid.lastScrollX = grid.flickable.contentX;
			grid.lastScrollY = grid.flickable.contentY;
			grid.scrollRemainderX = 0;
			grid.scrollRemainderY = 0;
		}

		// A newly opened folder exposes its rows a few at a time; ask for the
		// thumbnails and descriptors of each batch as it appears.
		function onRowsInserted() {
			grid.scheduleThumbnails();
		}
	}

	// ── Scroll feedback, 3DS style ──
	// The view can scroll on either axis — the layout picks which — so this
	// follows whichever position actually moves instead of trusting the config,
	// which described the grid's flow, not the view's. One tick fires per item
	// crossed along the moving axis, so a slow drag ticks on the same boundaries
	// as a fast flick. Both axes use the up/down vocabulary: a sideways grid must
	// not sound like a different kind of movement. Reaching either end plays the
	// "edge" sound once, then stays quiet until the position moves away again.
	readonly property real scrollStepX: grid.listMode
		? grid.gridMetrics.itemWidth + Kirigami.Units.mediumSpacing
		: grid.gridItemSize.width + Kirigami.Units.mediumSpacing
	readonly property real scrollStepY: grid.listMode
		? grid.listRowHeight + Kirigami.Units.mediumSpacing
		: grid.gridItemSize.height + Kirigami.Units.mediumSpacing
	property real scrollRemainderX: 0
	property real scrollRemainderY: 0
	property real lastScrollX: 0
	property real lastScrollY: 0
	property bool atScrollStart: true
	property bool atScrollEnd: true
	// The tick rate is capped, not the item rate: a fast fling crosses many
	// items per frame, and a sound per crossing is both unintelligible and
	// enough to fill the sound queue.
	readonly property int scrollSoundInterval: 90
	property double lastScrollSoundTime: 0

	function updateScrollEdges(userGesture) {
		const view = grid.flickable;
		if (!view)
			return;
		// Whichever axis can actually scroll is the one whose ends matter.
		const maxX = Math.max(0, view.contentWidth - view.width);
		const maxY = Math.max(0, view.contentHeight - view.height);
		const horizontal = maxX > 1 && maxY <= 1;
		const vertical = maxY > 1 && maxX <= 1;
		const max = horizontal ? maxX : (vertical ? maxY : Math.max(maxX, maxY));
		if (max <= 1) {
			grid.atScrollStart = true;
			grid.atScrollEnd = true;
			return;
		}
		const pos = horizontal ? view.contentX : view.contentY;
		const wasAtStart = grid.atScrollStart;
		const wasAtEnd = grid.atScrollEnd;
		grid.atScrollStart = pos <= 1;
		grid.atScrollEnd = pos >= max - 1;
		// Announce only when a real end is *reached* by the user. Entry and
		// focus-driven scrolls change contentY too, and they must stay silent.
		if (!userGesture)
			return;
		if (grid.atScrollEnd && !wasAtEnd)
			grid.playSound("scroll-edge");
		else if (grid.atScrollStart && !wasAtStart)
			grid.playSound("scroll-edge");
	}

	function tickAxis(axis) {
		const view = grid.flickable;
		if (!view)
			return;
		const pos = axis === "x" ? view.contentX : view.contentY;
		const last = axis === "x" ? grid.lastScrollX : grid.lastScrollY;
		if (pos === last)
			return;
		const step = axis === "x" ? grid.scrollStepX : grid.scrollStepY;
		if (step <= 0)
			return;
		let remainder = (axis === "x" ? grid.scrollRemainderX : grid.scrollRemainderY) + (pos - last);
		if (axis === "x")
			grid.lastScrollX = pos;
		else
			grid.lastScrollY = pos;
		if (Math.abs(remainder) >= step) {
			// One sound per axis, not per direction: scrolling sideways is one kind
			// of movement (however it is oriented), and scrolling up or down is
			// another. Two sounds total. Cap the rate: a fling crosses several
			// items per frame, and each would otherwise be another queued tick.
			const now = Date.now();
			if (grid.userScrolling && !grid.focusScrollAnimating
				&& now - grid.lastScrollSoundTime >= grid.scrollSoundInterval) {
				grid.lastScrollSoundTime = now;
				grid.playScrollSound(axis === "x" ? "scroll-left" : "scroll-up");
			}
			remainder = 0;
		}
		if (axis === "x")
			grid.scrollRemainderX = remainder;
		else
			grid.scrollRemainderY = remainder;
	}

	function onMovementStarted() {
		grid.scrollRemainderX = 0;
		grid.scrollRemainderY = 0;
		// A new gesture earns its first tick even if the last one was a
		// moment ago.
		grid.lastScrollSoundTime = 0;
		grid.lastScrollX = grid.flickable.contentX;
		grid.lastScrollY = grid.flickable.contentY;
		grid.updateScrollEdges();
	}

	function onViewportMoved() {
		grid.scheduleThumbnails();
		grid.schedulePopulate();
		grid.tickAxis("y");
		grid.tickAxis("x");
		// The ends only change when the position does; a fling asks this once
		// per frame instead of once per axis.
		grid.updateScrollEdges();
		grid.viewportScrolled();
	}

	// ── Normal grid (lazy) ──
	// A GridView ignores leftMargin when it places delegates, so the grid block is
	// positioned by insetting the view itself: the delegates then start at the
	// view's left edge, which lands at the alignment offset. Insets also shrink
	// the area the view uses to wrap, which is how a fixed Lines count is
	// enforced (see the right/bottom margins below).
	GridView {
		id: gridView
		z: 1
		clip: true
		visible: !grid.freeGrid && !grid.listMode && !grid.grouped
		model: (grid.freeGrid || grid.listMode || grid.grouped) ? null : grid.directory
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.leftMargin: grid.gridMetrics.offsetX
		anchors.topMargin: grid.gridMetrics.offsetY
		// A fixed Lines count has to be enforced on the view itself: GridView
		// wraps by the space it has, not by the layout maths. Size the view to
		// exactly gridMetrics.columns (or rows, when scrolling sideways) cells so
		// the visual wrap and the focus grid cannot disagree. The trailing cell
		// gap is where the scrollbar sits, so the block is not covered.
		anchors.rightMargin: (!grid.horizontalScroll && grid.fixedLines)
			? Math.max(0, parent.width - grid.gridMetrics.offsetX
				- grid.gridMetrics.columns * (grid.gridMetrics.itemWidth + grid.gridMetrics.gap))
			: 0
		anchors.bottomMargin: (grid.horizontalScroll && grid.fixedLines)
			? Math.max(0, parent.height - grid.gridMetrics.offsetY
				- grid.gridMetrics.rows * (grid.gridMetrics.itemHeight + grid.gridMetrics.gap))
			: 0

		// Uniform cells: the delegate fills the item box, the gap lives in the
		// cell.
		cellWidth: grid.gridMetrics.itemWidth + grid.gridMetrics.gap
		cellHeight: grid.gridMetrics.itemHeight + grid.gridMetrics.gap
		flow: grid.horizontalScroll ? GridView.TopToBottom : GridView.LeftToRight
		// A fast touch fling outruns a 2-row cache and makes the view build
		// delegates while the finger is still moving, which shows up as small
		// stutters when the fling reverses. Four rows costs a few megabytes and
		// keeps the incoming row ready.
		cacheBuffer: Math.max(grid.gridMetrics.itemHeight, grid.gridMetrics.itemWidth) * 4

		onHeightChanged: {
			grid.scheduleThumbnails();
			grid.schedulePopulate();
		}
		onWidthChanged: {
			grid.scheduleThumbnails();
			grid.schedulePopulate();
		}
		onCountChanged: grid.schedulePopulate()
		onContentYChanged: grid.onViewportMoved()
		onContentXChanged: grid.onViewportMoved()
		onMovementStarted: {
			grid.userScrolling = true;
			grid.onMovementStarted();
		}
		onMovementEnded: {
			grid.userScrolling = false;
			grid.updateScrollEdges(true);
			// The fling's last position may have clipped the cursor after the
			// throttled follow last ran; settle it once the view has stopped,
			// before the border comes back.
			grid.viewportScrolled();
			grid.scrollEnded();
		}

		ScrollBar.vertical: ScrollBar {
			id: verticalScrollBar
			interactive: false
			// The grid scrolls on one axis only, so the other bar stays off. A
			// vertical-flow GridView leaves contentWidth unset (-1), which would
			// otherwise make the horizontal bar's size meaningless and force it on.
			policy: grid.horizontalScroll ? ScrollBar.AlwaysOff : (size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff)
			z: 2
		}

		ScrollBar.horizontal: ScrollBar {
			id: horizontalScrollBar
			interactive: false
			policy: grid.horizontalScroll ? (size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff) : ScrollBar.AlwaysOff
			z: 2
		}

		MouseArea {
			width: gridView.contentWidth
			height: gridView.contentHeight
			z: 0
			acceptedButtons: Qt.LeftButton
			onClicked: mouse => grid.backgroundClicked()
		}

		delegate: DeferredFileSlot {
			width: grid.gridMetrics.itemWidth
			height: grid.gridMetrics.itemHeight
			gridSize: grid.config ? grid.config.grid_size : 64
			showLabels: grid.config ? grid.config.show_labels : true
			labelBesideIcon: grid.labelsBesideIcons
			labelShowsFilename: grid.config ? grid.config.label_text === 1 : false
			property SelectionManager selectionManager: grid.selectionManager
			selectionActive: grid.selectionManager ? grid.selectionManager.selection_active : false
			actionManager: grid.window ? grid.window.actionManager : null
			fileManager: grid.window ? grid.window.fileManager : null
			dragDropHandler: grid.window ? grid.window.dragDropHandler : null
			isSelected: {
				const mgr = grid.selectionManager;
				if (!mgr)
					return false;
				mgr.selected_paths; // dependency: re-check when the selection changes
				return mgr.is_selected(path);
			}

			onSelectionToggled: (p, idx) => grid.itemSelectionToggled(p, idx)
			onShiftSelected: idx => grid.itemShiftSelected(idx)
			onPressHeld: (p, idx) => grid.itemPressHeld(p, idx)
			onContextMenuRequested: (p, idx) => grid.itemContextMenuRequested(p, idx)
			Component.onCompleted: grid.schedulePopulate()
		}
	}

	// ── List (lazy rows) ──
	// A fixed header names the columns. It is drawn outside the ListView so it
	// stays put while the rows scroll. Its padding, icon gap, spacing and
	// column weights match FileSlot's list layout, so header and rows line up.
	Rectangle {
		id: listHeader
		z: 2
		visible: grid.listHeaderVisible
		height: grid.listHeaderHeight
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		color: Qt.alpha(Kirigami.Theme.textColor, 0.05)

		RowLayout {
			anchors.fill: parent
			anchors.leftMargin: grid.listPadding
			anchors.rightMargin: grid.listPadding + grid.listBarInset
			spacing: Kirigami.Units.mediumSpacing

			Item {
				Layout.preferredWidth: grid.listIconSize
				Layout.preferredHeight: grid.listIconSize
			}
			Repeater {
				model: grid.listColumnSpecs

				delegate: Label {
					required property var modelData
					Layout.fillWidth: true
					Layout.preferredWidth: modelData.weight
					Layout.minimumWidth: 0
					text: modelData.title
					elide: Text.ElideRight
					horizontalAlignment: modelData.align
					opacity: 0.7
					font.bold: true
				}
			}
		}
	}

	ListView {
		id: listView
		z: 1
		clip: true
		visible: grid.listMode && !grid.grouped
		model: (grid.listMode && !grid.grouped) ? grid.directory : null
		anchors.top: grid.listHeaderVisible ? listHeader.bottom : parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		spacing: Kirigami.Units.mediumSpacing
		// Rows are a few screens' worth of delegates; keep a small cache, like
		// the grid, so a fling does not build while the finger is moving.
		cacheBuffer: grid.listRowHeight * 4

		onHeightChanged: {
			grid.scheduleThumbnails();
			grid.schedulePopulate();
		}
		onWidthChanged: {
			grid.scheduleThumbnails();
			grid.schedulePopulate();
		}
		onCountChanged: grid.schedulePopulate()
		onContentYChanged: grid.onViewportMoved()
		onMovementStarted: {
			grid.userScrolling = true;
			grid.onMovementStarted();
		}
		onMovementEnded: {
			grid.userScrolling = false;
			grid.updateScrollEdges(true);
			grid.viewportScrolled();
			grid.scrollEnded();
		}

		ScrollBar.vertical: ScrollBar {
			id: listVerticalScrollBar
			interactive: false
			policy: size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
			z: 2
		}
		ScrollBar.horizontal: ScrollBar {
			policy: ScrollBar.AlwaysOff
		}

		MouseArea {
			width: listView.contentWidth
			height: listView.contentHeight
			z: 0
			acceptedButtons: Qt.LeftButton
			onClicked: mouse => grid.backgroundClicked()
		}

		delegate: DeferredFileSlot {
			width: grid.gridMetrics.itemWidth
			height: grid.gridMetrics.itemHeight
			listMode: true
			listColumns: grid.listColumnSpecs
			listIconSize: grid.listIconSize
			gridSize: grid.config ? grid.config.grid_size : 64
			showLabels: true
			labelBesideIcon: true
			labelShowsFilename: grid.config ? grid.config.label_text === 1 : false
			property SelectionManager selectionManager: grid.selectionManager
			selectionActive: grid.selectionManager ? grid.selectionManager.selection_active : false
			actionManager: grid.window ? grid.window.actionManager : null
			fileManager: grid.window ? grid.window.fileManager : null
			dragDropHandler: grid.window ? grid.window.dragDropHandler : null
			isSelected: {
				const mgr = grid.selectionManager;
				if (!mgr)
					return false;
				mgr.selected_paths; // dependency: re-check when the selection changes
				return mgr.is_selected(path);
			}

			onSelectionToggled: (p, idx) => grid.itemSelectionToggled(p, idx)
			onShiftSelected: idx => grid.itemShiftSelected(idx)
			onPressHeld: (p, idx) => grid.itemPressHeld(p, idx)
			onContextMenuRequested: (p, idx) => grid.itemContextMenuRequested(p, idx)
			Component.onCompleted: grid.schedulePopulate()
		}
	}

	// ── Grouped (headers + explicit item positions) ──
	// A header is not item sized, so a GridView cannot reserve a row for it.
	// This view lays every item out explicitly and draws the group labels in
	// the same content item, which also gives horizontal folders their rotated
	// labels.
	Flickable {
		id: groupedFlickable
		z: 1
		clip: true
		visible: grid.grouped
		anchors.top: grid.listMode && grid.listHeaderVisible ? listHeader.bottom : parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		contentWidth: grid.gridMetrics.contentWidth
		contentHeight: grid.gridMetrics.contentHeight

		onHeightChanged: {
			grid.scheduleThumbnails();
			grid.schedulePopulate();
		}
		onWidthChanged: {
			grid.scheduleThumbnails();
			grid.schedulePopulate();
		}
		onContentYChanged: grid.onViewportMoved()
		onContentXChanged: grid.onViewportMoved()
		onMovementStarted: {
			grid.userScrolling = true;
			grid.onMovementStarted();
		}
		onMovementEnded: {
			grid.userScrolling = false;
			grid.updateScrollEdges(true);
			grid.viewportScrolled();
			grid.scrollEnded();
		}

		ScrollBar.vertical: ScrollBar {
			id: groupedVerticalScrollBar
			interactive: false
			policy: grid.horizontalScroll ? ScrollBar.AlwaysOff : (size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff)
			z: 2
		}

		ScrollBar.horizontal: ScrollBar {
			id: groupedHorizontalScrollBar
			interactive: false
			policy: grid.horizontalScroll ? (size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff) : ScrollBar.AlwaysOff
			z: 2
		}

		MouseArea {
			width: groupedFlickable.contentWidth
			height: groupedFlickable.contentHeight
			z: 0
			acceptedButtons: Qt.LeftButton
			onClicked: mouse => grid.backgroundClicked()
		}

		Item {
			id: groupedContent
			z: 1
			width: groupedFlickable.contentWidth
			height: groupedFlickable.contentHeight

			Repeater {
				id: groupedHeaderRepeater
				model: grid.grouped ? grid.gridMetrics.groups : []

				delegate: groupHeaderComponent
			}

			Repeater {
				id: groupedRepeater
				model: grid.grouped ? grid.directory : null

				delegate: DeferredFileSlot {
					width: grid.gridMetrics.itemWidth
					height: grid.gridMetrics.itemHeight
					x: grid.gridSlotX(index)
					y: grid.gridSlotY(index)
					listMode: grid.listMode
					listColumns: grid.listColumnSpecs
					listIconSize: grid.listIconSize
					gridSize: grid.config ? grid.config.grid_size : 64
					showLabels: grid.listMode ? true : (grid.config ? grid.config.show_labels : true)
					labelBesideIcon: grid.listMode ? true : grid.labelsBesideIcons
					labelShowsFilename: grid.config ? grid.config.label_text === 1 : false
					property SelectionManager selectionManager: grid.selectionManager
					selectionActive: grid.selectionManager ? grid.selectionManager.selection_active : false
					actionManager: grid.window ? grid.window.actionManager : null
					fileManager: grid.window ? grid.window.fileManager : null
					dragDropHandler: grid.window ? grid.window.dragDropHandler : null
					isSelected: {
						const mgr = grid.selectionManager;
						if (!mgr)
							return false;
						mgr.selected_paths;
						return mgr.is_selected(path);
					}

					onSelectionToggled: (p, idx) => grid.itemSelectionToggled(p, idx)
					onShiftSelected: idx => grid.itemShiftSelected(idx)
					onPressHeld: (p, idx) => grid.itemPressHeld(p, idx)
					onContextMenuRequested: (p, idx) => grid.itemContextMenuRequested(p, idx)
					Component.onCompleted: grid.schedulePopulate()
				}
			}
		}
	}

	Component {
		id: groupHeaderComponent

		Item {
			id: groupHeader
			property var modelData
			x: grid.gridMetrics.offsetX + (modelData ? modelData.x : 0)
			y: grid.gridMetrics.offsetY + (modelData ? modelData.y : 0)
			width: modelData ? modelData.width : 0
			height: modelData ? modelData.height : 0
			visible: modelData ? modelData.label !== "" : false
			z: 2

			Text {
				id: verticalGroupLabel
				visible: groupHeader.modelData ? !groupHeader.modelData.horizontal : false
				text: groupHeader.modelData ? groupHeader.modelData.label : ""
				width: Math.max(0, parent.width - Kirigami.Units.largeSpacing)
				anchors.left: parent.left
				anchors.verticalCenter: parent.verticalCenter
				elide: Text.ElideRight
				color: Kirigami.Theme.textColor
				opacity: 0.75
				font.bold: true
				font.pixelSize: Math.max(12, Kirigami.Units.gridUnit * 0.85)
			}

			Rectangle {
				visible: verticalGroupLabel.visible
				height: 1
				color: Qt.alpha(Kirigami.Theme.textColor, 0.22)
				anchors.left: verticalGroupLabel.right
				anchors.leftMargin: Kirigami.Units.mediumSpacing
				anchors.right: parent.right
				anchors.verticalCenter: parent.verticalCenter
			}

			Item {
				id: horizontalGroupLabelBox
				visible: groupHeader.modelData ? groupHeader.modelData.horizontal : false
				width: parent.width
				height: Math.min(parent.height, Kirigami.Units.gridUnit * 4)
				anchors.top: parent.top

				Text {
					id: horizontalGroupLabel
					text: groupHeader.modelData ? groupHeader.modelData.label : ""
					color: Kirigami.Theme.textColor
					opacity: 0.75
					font.bold: true
					font.pixelSize: Math.max(12, Kirigami.Units.gridUnit * 0.85)
					rotation: -90
					transformOrigin: Item.TopLeft
					x: parent.width
					y: parent.height
					width: parent.height
					height: parent.width
					verticalAlignment: Text.AlignVCenter
					horizontalAlignment: Text.AlignLeft
					elide: Text.ElideRight
				}
			}

			Rectangle {
				visible: horizontalGroupLabelBox.visible
				width: 1
				color: Qt.alpha(Kirigami.Theme.textColor, 0.22)
				anchors.horizontalCenter: parent.horizontalCenter
				anchors.top: horizontalGroupLabelBox.bottom
				anchors.bottom: parent.bottom
			}
		}
	}

	// ── Free placement (explicit positions) ──
	Flickable {
		id: freeFlickable
		z: 1
		anchors.fill: parent
		clip: true
		visible: grid.freeGrid
		contentWidth: grid.gridMetrics.contentWidth
		contentHeight: grid.gridMetrics.contentHeight

		onHeightChanged: grid.scheduleThumbnails()
		onWidthChanged: grid.scheduleThumbnails()
		onContentYChanged: grid.onViewportMoved()
		onContentXChanged: grid.onViewportMoved()
		onMovementStarted: {
			grid.userScrolling = true;
			grid.onMovementStarted();
		}
		onMovementEnded: {
			grid.userScrolling = false;
			grid.updateScrollEdges(true);
			// The fling's last position may have clipped the cursor after the
			// throttled follow last ran; settle it once the view has stopped,
			// before the border comes back.
			grid.viewportScrolled();
			grid.scrollEnded();
		}

		ScrollBar.vertical: ScrollBar {
			id: freeVerticalScrollBar
			interactive: false
			policy: grid.horizontalScroll ? ScrollBar.AlwaysOff : (size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff)
			z: 2
		}

		ScrollBar.horizontal: ScrollBar {
			id: freeHorizontalScrollBar
			interactive: false
			policy: grid.horizontalScroll ? (size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff) : ScrollBar.AlwaysOff
			z: 2
		}

		MouseArea {
			width: freeFlickable.contentWidth
			height: freeFlickable.contentHeight
			z: 0
			acceptedButtons: Qt.LeftButton
			onClicked: mouse => grid.backgroundClicked()
		}

		Item {
			id: freeGridContent
			z: 1
			width: freeFlickable.contentWidth
			height: freeFlickable.contentHeight

			Repeater {
				id: freeRepeater
				model: grid.freeGrid ? grid.directory : null

				delegate: DeferredFileSlot {
					width: grid.gridItemSize.width
					height: grid.gridItemSize.height
					x: grid.gridSlotX(index)
					y: grid.gridSlotY(index)
					gridSize: grid.config ? grid.config.grid_size : 64
					showLabels: grid.config ? grid.config.show_labels : true
					labelBesideIcon: grid.labelsBesideIcons
					labelShowsFilename: grid.config ? grid.config.label_text === 1 : false
					property SelectionManager selectionManager: grid.selectionManager
					selectionActive: grid.selectionManager ? grid.selectionManager.selection_active : false
					actionManager: grid.window ? grid.window.actionManager : null
					fileManager: grid.window ? grid.window.fileManager : null
					dragDropHandler: grid.window ? grid.window.dragDropHandler : null
					isSelected: {
						const mgr = grid.selectionManager;
						if (!mgr)
							return false;
						mgr.selected_paths;
						return mgr.is_selected(path);
					}

					onSelectionToggled: (p, idx) => grid.itemSelectionToggled(p, idx)
					onShiftSelected: idx => grid.itemShiftSelected(idx)
					onPressHeld: (p, idx) => grid.itemPressHeld(p, idx)
					onContextMenuRequested: (p, idx) => grid.itemContextMenuRequested(p, idx)
					Component.onCompleted: grid.schedulePopulate()
				}
			}
		}
	}

	// ── Overlays ──
	// The free-placement drop cell, drawn under the items.
	Rectangle {
		id: freeDropHighlight
		parent: grid.freeGrid ? freeGridContent : (grid.listMode ? listView.contentItem : gridView.contentItem)
		z: 0
		visible: grid.freeDropActive
		width: grid.gridMetrics.itemWidth
		height: grid.gridMetrics.itemHeight
		x: grid.freeDropX
		y: grid.freeDropY
		radius: Kirigami.Units.cornerRadius
		color: Kirigami.Theme.focusColor
		opacity: 0.35
		border.color: Kirigami.Theme.highlightColor
		border.width: 2
	}

	// The focus border: one shared border drawn at the focused slot (or the empty
	// cell the cursor rests on), instead of every slot carrying its own copy. The
	// x/y behaviours smooth the move between items.
	Item {
		id: focusBorderHost
		parent: grid.freeGrid
			? freeGridContent
			: (grid.grouped ? groupedContent : (grid.listMode ? listView.contentItem : gridView.contentItem))
		z: 3
		readonly property var fm: grid.focusManager
		readonly property var metrics: grid.gridMetrics
		readonly property bool paneActive: grid.focusOwned
			&& focusBorderHost.fm
			&& focusBorderHost.fm.focus_active
			&& focusBorderHost.fm.current_pane === grid.paneId
		readonly property bool onEmpty: paneActive && focusBorderHost.fm.focus_on_empty
		readonly property bool onItem: paneActive && !focusBorderHost.fm.focus_on_empty
			&& focusBorderHost.fm.focused_index >= 0
		// The border lives in the view's content item, which sits at the view's
		// origin. In a GridView that origin is the alignment offset, so subtract
		// it to place the border on the slot's real position.
		readonly property real originX: (grid.freeGrid || grid.listMode || grid.grouped) ? 0 : focusBorderHost.metrics.offsetX
		readonly property real originY: (grid.freeGrid || grid.listMode || grid.grouped) ? 0 : focusBorderHost.metrics.offsetY
		visible: (onEmpty || onItem) && !grid.userScrolling
		width: focusBorderHost.metrics.itemWidth
		height: focusBorderHost.metrics.itemHeight
		// Animate only while the border is already on screen, so the first
		// appearance jumps straight to the item instead of sliding in from
		// wherever it last was (or from the origin).
		property bool moving: false
		onVisibleChanged: {
			if (visible)
				Qt.callLater(() => focusBorderHost.moving = true);
			else
				focusBorderHost.moving = false;
		}
		x: (focusBorderHost.onEmpty
			? focusBorderHost.metrics.offsetX + focusBorderHost.fm.focused_column * (focusBorderHost.metrics.itemWidth + focusBorderHost.metrics.gap)
			: (focusBorderHost.onItem ? grid.gridSlotX(focusBorderHost.fm.focused_index) : 0)) - focusBorderHost.originX
		y: (focusBorderHost.onEmpty
			? focusBorderHost.metrics.offsetY + focusBorderHost.fm.focused_row * (focusBorderHost.metrics.itemHeight + focusBorderHost.metrics.gap)
			: (focusBorderHost.onItem ? grid.gridSlotY(focusBorderHost.fm.focused_index) : 0)) - focusBorderHost.originY

		Behavior on x {
			enabled: focusBorderHost.moving
			NumberAnimation {
				duration: 160
				easing.type: Easing.OutCubic
			}
		}

		Behavior on y {
			enabled: focusBorderHost.moving
			NumberAnimation {
				duration: 160
				easing.type: Easing.OutCubic
			}
		}

		FocusBorder {
			anchors.fill: parent
			source: grid.focusBorderSource
		}
	}
}
