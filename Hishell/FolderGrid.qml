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

	readonly property bool freeGrid: grid.config ? (grid.config.sort === 3 && grid.config.view_mode === 0) : false

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

	// The view actually in charge; free placement and the normal grid never share
	// one, so scroll and focus code goes through this.
	readonly property var flickable: grid.freeGrid ? freeFlickable : gridView
	// Content item the drop handling maps coordinates into.
	readonly property var gridContent: grid.freeGrid ? freeGridContent : gridView.contentItem
	readonly property int count: grid.freeGrid ? freeRepeater.count : gridView.count
	readonly property int gridStride: grid.gridMetrics.stride
	// Width of the vertical scrollbar in the active view, for the pane's fixed
	// grid width.
	readonly property real verticalBarWidth: grid.freeGrid ? freeVerticalScrollBar.width : verticalScrollBar.width

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
		if (metrics.free && metrics.slots && metrics.slots[index]) {
			return metrics.offsetX + metrics.slots[index].c * (metrics.itemWidth + metrics.gap);
		}
		const column = metrics.horizontal ? Math.floor(index / metrics.rows) : index % metrics.columns;
		return metrics.offsetX + column * (metrics.itemWidth + metrics.gap);
	}

	function gridSlotY(index) {
		const metrics = grid.gridMetrics;
		if (metrics.free && metrics.slots && metrics.slots[index]) {
			return metrics.offsetY + metrics.slots[index].r * (metrics.itemHeight + metrics.gap);
		}
		const row = metrics.horizontal ? index % metrics.rows : Math.floor(index / metrics.columns);
		return metrics.offsetY + row * (metrics.itemHeight + metrics.gap);
	}

	// The live delegate for an item index, when it exists. Only visible items are
	// instantiated in the GridView, so callers must handle null.
	function slotAt(index) {
		return grid.freeGrid ? freeRepeater.itemAt(index) : gridView.itemAtIndex(index);
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

		const count = grid.count;
		for (let i = 0; i < count; i++) {
			const item = grid.slotAt(i);
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
			grid.lastScrollX = grid.flickable.contentX;
			grid.lastScrollY = grid.flickable.contentY;
			grid.scrollRemainderX = 0;
			grid.scrollRemainderY = 0;
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
	readonly property real scrollStepX: grid.gridItemSize.width + Kirigami.Units.mediumSpacing
	readonly property real scrollStepY: grid.gridItemSize.height + Kirigami.Units.mediumSpacing
	property real scrollRemainderX: 0
	property real scrollRemainderY: 0
	property real lastScrollX: 0
	property real lastScrollY: 0
	property bool atScrollStart: true
	property bool atScrollEnd: true

	function updateScrollEdges() {
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
		// Announce only when a real end is *reached*: the start is where the view
		// rests, so arriving back there is not an "edge" event.
		if (grid.atScrollEnd && !wasAtEnd)
			grid.playSound("scroll-edge");
		else if (grid.atScrollStart && !wasAtStart)
			grid.playSound("scroll-edge");
	}

	function tickAxis(axis) {
		const step = axis === "x" ? grid.scrollStepX : grid.scrollStepY;
		if (step <= 0)
			return;
		const view = grid.flickable;
		if (!view)
			return;
		const pos = axis === "x" ? view.contentX : view.contentY;
		const last = axis === "x" ? grid.lastScrollX : grid.lastScrollY;
		let remainder = (axis === "x" ? grid.scrollRemainderX : grid.scrollRemainderY) + (pos - last);
		if (axis === "x")
			grid.lastScrollX = pos;
		else
			grid.lastScrollY = pos;
		if (Math.abs(remainder) >= step) {
			// One sound per axis, not per direction: scrolling sideways is one kind
			// of movement (however it is oriented), and scrolling up or down is
			// another. Two sounds total.
			grid.playSound(axis === "x" ? "scroll-left" : "scroll-up");
			remainder = 0;
		}
		if (axis === "x")
			grid.scrollRemainderX = remainder;
		else
			grid.scrollRemainderY = remainder;
		grid.updateScrollEdges();
	}

	function onMovementStarted() {
		grid.scrollRemainderX = 0;
		grid.scrollRemainderY = 0;
		grid.lastScrollX = grid.flickable.contentX;
		grid.lastScrollY = grid.flickable.contentY;
		grid.updateScrollEdges();
	}

	function onViewportMoved() {
		grid.scheduleThumbnails();
		grid.tickAxis("y");
		grid.tickAxis("x");
		grid.viewportScrolled();
	}

	// ── Normal grid (lazy) ──
	// A GridView ignores leftMargin when it places delegates, so the grid block is
	// positioned by insetting the view itself: the delegates then start at the
	// view's left edge, which lands at the alignment offset.
	GridView {
		id: gridView
		z: 1
		clip: true
		visible: !grid.freeGrid
		model: grid.freeGrid ? null : grid.directory
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.leftMargin: grid.gridMetrics.offsetX
		anchors.topMargin: grid.gridMetrics.offsetY

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
			grid.updateScrollEdges();
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

		delegate: FileSlot {
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
			isFocused: grid.focusManager ? (grid.focusManager.focus_active && String(grid.focusManager.focused_path) === String(path)) : false
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
			grid.updateScrollEdges();
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

				delegate: FileSlot {
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
					isFocused: grid.focusManager ? (grid.focusManager.focus_active && String(grid.focusManager.focused_path) === String(path)) : false
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
				}
			}
		}
	}

	// ── Overlays ──
	// The free-placement drop cell, drawn under the items.
	Rectangle {
		id: freeDropHighlight
		parent: grid.freeGrid ? freeGridContent : gridView.contentItem
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
		parent: grid.freeGrid ? freeGridContent : gridView.contentItem
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
		readonly property real originX: grid.freeGrid ? 0 : focusBorderHost.metrics.offsetX
		readonly property real originY: grid.freeGrid ? 0 : focusBorderHost.metrics.offsetY
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
