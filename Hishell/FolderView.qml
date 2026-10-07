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

	Layout.fillWidth: true
	Layout.fillHeight: true

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
		if (!fm)
			return;
		// While the window is inactive the controller still drives the file
		// view; only focus owned elsewhere inside an active window (popups,
		// dialogs) hands the input over to Qt.
		fm.view_focused = folderView.activeFocus || !(window && window.active);
	}

	function selectAll() {
		const mgr = folderView.rootWindow ? folderView.rootWindow.selectionManager : null;
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
		const iconSize = cfg ? cfg.grid_size : 64;
		const besideIcon = iconSize < 32;
		const itemWidth = besideIcon ? Kirigami.Units.gridUnit * 10 : iconSize + Kirigami.Units.gridUnit * 3;
		const itemHeight = besideIcon ? Kirigami.Units.gridUnit * 2 : iconSize + Kirigami.Units.gridUnit * 3;
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

		function measure(insetX, insetY) {
			const width = viewWidth - insetX;
			const height = viewHeight - insetY;
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
			contentHeight: Math.max(viewHeight, metrics.naturalHeight + insetY)
		};
	}

	readonly property int gridStride: folderView.gridMetrics.stride

	function gridSlotX(index) {
		const metrics = folderView.gridMetrics;
		const column = metrics.horizontal ? Math.floor(index / metrics.rows) : index % metrics.columns;
		return metrics.offsetX + column * (metrics.itemWidth + metrics.gap);
	}

	function gridSlotY(index) {
		const metrics = folderView.gridMetrics;
		const row = metrics.horizontal ? index % metrics.rows : Math.floor(index / metrics.columns);
		return metrics.offsetY + row * (metrics.itemHeight + metrics.gap);
	}

	function updateFocusItems() {
		const fm = folderView.focusManager;
		if (!fm || !folderView.directory)
			return;
		const paths = folderView.directory.get_all_paths();
		if (paths.length === 0) {
			fm.clear();
			return;
		}
		fm.set_horizontal(folderView.horizontalScroll);
		fm.set_items(paths, folderView.gridStride);
		folderView.focusOwned = true;

		if (folderView.returnFocusPath !== "") {
			const target = folderView.returnFocusPath;
			folderView.returnFocusPath = "";
			if (fm.set_focus_path(target))
				Qt.callLater(() => folderView.ensureFocusVisible());
		}
	}

	function ensureFocusVisible() {
		if (!folderView.focusManager || !folderView.focusManager.focus_active)
			return;
		const item = itemRepeater.itemAt(folderView.focusManager.focused_index);
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
		const mgr = folderView.rootWindow ? folderView.rootWindow.selectionManager : null;
		if (!fm || !fm.focus_active || String(fm.focused_path) === "")
			return;
		if (mgr && mgr.selection_active) {
			mgr.toggle_selection(String(fm.focused_path), fm.focused_index);
			return;
		}
		folderView.openFocused();
	}

	Component.onCompleted: {
		folderView.forceActiveFocus();
		Qt.callLater(() => {
			folderView.forceActiveFocus();
			folderView.updateViewFocus();
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

	onActiveFocusChanged: {
		folderView.updateViewFocus();
		if (folderView.activeFocus) {
			folderView.focusOwned = true;
			folderView.updateFocusItems();
		}
	}

	Connections {
		target: itemRepeater
		function onCountChanged() {
			folderView.updateFocusItems();
		}
	}

	onGridStrideChanged: {
		if (folderView.focusOwned && folderView.focusManager)
			folderView.focusManager.set_columns(folderView.gridStride);
	}

	Connections {
		target: folderView.focusManager
		function onFocus_changed() {
			if (folderView.focusOwned)
				folderView.ensureFocusVisible();
		}
		function onAccept_requested() {
			if (folderView.focusOwned)
				folderView.activateFocused();
		}
		function onMenu_requested() {
			if (!folderView.focusOwned || !folderView.focusManager || !folderView.focusManager.focus_active)
				return;
			const item = itemRepeater.itemAt(folderView.focusManager.focused_index);
			if (item)
				folderView.openMenu = item.openContextMenu();
		}
		function onCancel_requested() {
			if (!folderView.focusOwned)
				return;

			if (folderView.openMenu && folderView.openMenu.visible) {
				folderView.openMenu.close();
				folderView.openMenu = null;
				return;
			}

			const mgr = folderView.rootWindow ? folderView.rootWindow.selectionManager : null;
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
				folderView.focusManager.clear();
			// Entering a folder leaves the focus inactive, so no border shows
			// until the next directional input; a restored target activates it.
			folderView.updateFocusItems();
			if (folderView.rootWindow && folderView.rootWindow.selectionManager) {
				folderView.rootWindow.selectionManager.exit_selection_mode();
			}
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
				if (folderView.rootWindow && folderView.rootWindow.selectionManager)
					folderView.rootWindow.selectionManager.clear();
				if (folderView.focusManager)
					folderView.focusManager.clear();
			}
		}
	}

	function isDropValid(targetPath, sourcePaths) {
		return window.dropValidator.is_drop_valid(targetPath, sourcePaths);
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
			if (typeof dragHandler !== 'undefined' && dragHandler)
				dragHandler.tooltip_active = false;
		}

		onDropped: drop => {
			bgDropArea.isHovered = false;
			if (typeof dragHandler !== 'undefined' && dragHandler)
				dragHandler.tooltip_active = false;

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
		cursorX: dragHandler ? dragHandler.drag_cursor_x + 16 : 0
		cursorY: dragHandler ? dragHandler.drag_cursor_y + 16 : 0
	}

	// ── Input Shortcuts ───
	Keys.onPressed: event => {
		const mgr = folderView.rootWindow ? folderView.rootWindow.selectionManager : null;
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
			fm.clear();
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
				if (folderView.rootWindow && folderView.rootWindow.selectionManager)
					folderView.rootWindow.selectionManager.clear();
				if (folderView.focusManager)
					folderView.focusManager.clear();
			}
		}

		Item {
			id: gridContent
			z: 1
			width: flickable.contentWidth
			height: flickable.contentHeight

			Repeater {
				id: itemRepeater
				model: folderView.directory

				delegate: FileSlot {
					property SelectionManager selectionManager: folderView.rootWindow ? folderView.rootWindow.selectionManager : null
					actionManager: folderView.rootWindow ? folderView.rootWindow.actionManager : null
					fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null

					dragDropHandler: folderView.rootWindow ? folderView.rootWindow.dragDropHandler : null
					width: labelBesideIcon ? Kirigami.Units.gridUnit * 10 : gridSize + Kirigami.Units.gridUnit * 3
					height: labelBesideIcon ? Kirigami.Units.gridUnit * 2 : gridSize + Kirigami.Units.gridUnit * 3
					x: folderView.gridSlotX(index)
					y: folderView.gridSlotY(index)

					gridSize: folderView.config.grid_size
					selectionActive: selectionManager ? selectionManager.selection_active : false
					focusActive: folderView.focusOwned
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

		height: (folderView.rootWindow && folderView.rootWindow.selectionManager && folderView.rootWindow.selectionManager.selection_active) ? 48 : 0
		visible: folderView.rootWindow && folderView.rootWindow.selectionManager && folderView.rootWindow.selectionManager.selection_active
		radius: 6

		Kirigami.Theme.colorSet: Kirigami.Theme.Header
		color: Kirigami.Theme.backgroundColor

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
				text: {
					const n = (folderView.rootWindow && folderView.rootWindow.selectionManager) ? folderView.rootWindow.selectionManager.selected_count : 0;
					return n === 1 ? qsTr("1 item selected") : qsTr("%1 items selected").arg(n);
				}
				font.weight: Font.Medium
				Layout.fillWidth: true
			}

			ToolButton {
				text: qsTr("Select All")
				icon.name: "edit-select-all"
				ToolTip.text: qsTr("Select All")
				ToolTip.visible: hovered
				flat: true
				onClicked: folderView.selectAll()
			}

			ToolButton {
				text: qsTr("Deselect All")
				icon.name: "edit-select-none"
				ToolTip.text: qsTr("Deselect All")
				ToolTip.visible: hovered
				flat: true
				onClicked: if (folderView.rootWindow && folderView.rootWindow.selectionManager)
					folderView.rootWindow.selectionManager.deselect_all()
			}
		}
	}

	ExecuteDialog {
		id: execDialog
		directory: folderView.directory
		fileManager: folderView.rootWindow ? folderView.rootWindow.fileManager : null
	}
}