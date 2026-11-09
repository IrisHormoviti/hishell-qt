import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import hishell_qt
import NativeDrag 1.0

ApplicationWindow {
	id: window
	width: 900
	height: 600
	title: {
		const directory = window.currentDirectory
		if (!directory)
			return "hishell"
		return directory.config.title.length > 0
			? directory.config.title : String(directory.path)
	}
	flags: window.currentDirectory && !window.currentDirectory.config.native_titlebar
		? Qt.Window | Qt.FramelessWindowHint : Qt.Window
	visible: !headless
	color: Kirigami.Theme.backgroundColor

	required property var leftDirectory
	required property var rightDirectory

	property bool headless: false
	property string testMiddleLayout: ""
	property var panes: []
	property Item activePane: null
	// The directory whose config supplies the window layout. It stays put while
	// a rebuild clears and recreates the panes, so the layout string does not
	// flip to a default mid-rebuild and set off a rebuild loop.
	property var layoutDirectory: leftDirectory
	property bool dragPreviewActive: false
	property var dragPreviewData: null
	property real dragCursorX: 0
	property real dragCursorY: 0
	property bool dragActive: false
	property bool dragTooltipActive: false
	property bool dragTooltipReposition: false
	property string dragTooltipAction: "copy"
	property string dismissedConfigError: ""

	function updateWindowIcon() {
		if (!window.currentDirectory)
			return
		DragHelper.setWindowIcon(window,
			window.currentDirectory.window_icon())
	}

	function applyConfiguredScreen() {
		if (!leftDirectory)
			return
		const wanted = String(leftDirectory.config.screen_name)
		if (wanted.length === 0)
			return
		const screens = Qt.application.screens
		for (let i = 0; i < screens.length; i++) {
			if (String(screens[i].name) === wanted) {
				window.screen = screens[i]
				return
			}
		}
	}

	Component.onCompleted: {
		window.updateWindowIcon()
		window.applyConfiguredScreen()
		if (leftDirectory && leftDirectory.config.maximized)
			Qt.callLater(function () { window.showFullScreen() })
	}



	readonly property var currentDirectory: activePane ? activePane.directory : null
	readonly property string homePath: leftDirectory ? leftDirectory.home_directory() : ""
	readonly property var headerPathBar: headerLayout ? headerLayout.pathBarItem : null
	readonly property var leftPane: panes.length > 0 ? panes[0] : null
	readonly property var rightPane: panes.length > 1 ? panes[1] : null

	function paneDirectory(index) {
		return index === 0 ? leftDirectory : rightDirectory
	}

	function clearPanes() {
		panes = []
		activePane = null
	}

	onActivePaneChanged: {
		if (activePane && activePane.directory) {
			window.layoutDirectory = activePane.directory
			window.updateWindowIcon()
		}
	}

	Connections {
		target: window.currentDirectory
		ignoreUnknownSignals: true
		function onPath_changed() { window.updateWindowIcon() }
		function onRevision_changed() { window.updateWindowIcon() }
	}

	function registerPane(pane) {
		panes = panes.concat([pane])
		if (!activePane)
			activePane = pane
	}

	function switchPane(direction) {
		const index = panes.indexOf(activePane)
		if (index < 0)
			return
		const next = direction === "right" ? index + 1 : index - 1
		if (next < 0 || next >= panes.length)
			return
		activePane = panes[next]
		if (direction === "right")
			activePane.focusFirst()
		else
			activePane.focusLast()
	}

	function segments(path) {
		let full = String(path)
		const home = window.homePath
		if (home.length > 1 && (full === home || full.startsWith(home + "/"))) {
			const rel = full === home ? "" : full.substring(home.length + 1)
			const parts = rel.split("/").filter(part => part.length > 0)
			let out = [{ "name": home.split("/").pop(), "path": home }]
			let current = home
			for (let i = 0; i < parts.length; i++) {
				current += "/" + parts[i]
				out.push({ "name": parts[i], "path": current })
			}
			return out
		}
		let parts = full.split("/").filter(part => part.length > 0)
		let out = [{ "name": "/", "path": "/" }]
		let current = ""
		for (let i = 0; i < parts.length; i++) {
			current += "/" + parts[i]
			out.push({ "name": parts[i], "path": current })
		}
		return out
	}

	function actionLabel(id) {
		const labels = {
			"open": "Open",
			"open-with": "Open With…",
			"open-window": "Open in Window",
			"navigate": "Navigate",
			"go-up": "Go Up",
			"refresh": "Refresh",
			"select-all": "Select All",
			"new-folder": "New Folder",
			"new-text-file": "New Text File",
			"copy": "Copy",
			"cut": "Cut",
			"paste": "Paste",
			"properties": "Properties",
			"duplicate": "Duplicate",
			"create-link": "Create Link",
			"rename": "Rename…",
			"trash": "Move to Trash…",
			"delete": "Delete…",
			"destroy": "Delete Permanently…",
			"toggle": "Toggle",
			"radio": "Select",
			"number": "Set Values…",
			"quit-active": "Quit",
			"set-default-app": "Set Default Application",
			"rotate-image": "Rotate Clockwise"
		}
		return labels[id] || id
	}


	Connections {
		target: window.headerPathBar
		function onLocationMenuRequested(anchor) {
			if (window.activePane && window.activePane.openLocationMenuAt)
				window.activePane.openLocationMenuAt(anchor)
		}
	}

	Shortcut {
		sequence: "F5"
		onActivated: if (window.currentDirectory)
			window.currentDirectory.invoke("refresh")
	}

	Shortcut {
		sequence: "Ctrl+O"
		onActivated: if (window.currentDirectory) window.currentDirectory.invoke("open")
	}

	Shortcut {
		sequence: "Ctrl+N"
		onActivated: {
			if (!window.currentDirectory)
				return
			const path = window.currentDirectory.focused_path.length > 0
				? window.currentDirectory.focused_path
				: window.currentDirectory.path
			window.currentDirectory.open_in_new_window(path)
		}
	}

	Shortcut {
		sequence: "Alt+Left"
		onActivated: if (window.currentDirectory) window.currentDirectory.back()
	}

	Shortcut {
		sequence: "Alt+Right"
		onActivated: if (window.currentDirectory) window.currentDirectory.forward()
	}

	Shortcut {
		sequence: "Ctrl+Alt+O"
		onActivated: if (window.currentDirectory) window.currentDirectory.invoke("open-with")
	}

	ColumnLayout {
		id: content
		anchors.fill: parent
		spacing: 0

		NativeMenuBar {
			Layout.fillWidth: true
			window: window
			visible: window.currentDirectory
				&& window.currentDirectory.config.native_menubar
		}

		Item {
			Layout.fillWidth: true
			Layout.preferredHeight: Math.max(48, Kirigami.Units.gridUnit * 3)

			Rectangle {
				anchors.fill: parent
				color: Kirigami.Theme.backgroundColor
			}

			DragHandler {
				target: null
				enabled: window.currentDirectory
					&& !window.currentDirectory.config.native_titlebar
				onActiveChanged: if (active) window.startSystemMove()
			}

			LayoutEngine {
				id: headerLayout
				anchors.fill: parent
				role: "header"
				window: window
				layoutString: window.layoutDirectory
					? window.layoutDirectory.config.header_layout
					: '["toolkit/PathBar","toolkit/Spacer","toolkit/MenuBar"]'
			}
		}

		Rectangle {
			visible: window.layoutDirectory
				&& window.layoutDirectory.config.error.length > 0
				&& window.layoutDirectory.config.error !== window.dismissedConfigError
			Layout.fillWidth: true
			Layout.preferredHeight: errorRow.implicitHeight
				+ Kirigami.Units.largeSpacing * 2
			color: Kirigami.Theme.negativeBackgroundColor

			RowLayout {
				id: errorRow
				anchors.centerIn: parent
				width: parent.width - Kirigami.Units.largeSpacing * 2
				spacing: Kirigami.Units.largeSpacing

				Label {
					Layout.fillWidth: true
					text: window.layoutDirectory
						? window.layoutDirectory.config.error : ""
					color: Kirigami.Theme.negativeTextColor
					wrapMode: Text.WordWrap
				}

				ToolButton {
					icon.name: "dialog-close"
					onClicked: window.dismissedConfigError =
						window.layoutDirectory.config.error
				}
			}
		}

		LayoutEngine {
			id: topLayout
			Layout.fillWidth: true
			Layout.fillHeight: false
			role: "top"
			window: window
			layoutString: window.layoutDirectory ? window.layoutDirectory.config.top_layout : "[]"
		}

		LayoutEngine {
			id: middleLayout
			Layout.fillWidth: true
			Layout.fillHeight: true
			role: "middle"
			window: window
			layoutString: window.testMiddleLayout.length > 0
				? window.testMiddleLayout
				: (window.layoutDirectory ? window.layoutDirectory.config.middle_layout : '["./"]')
		}

		LayoutEngine {
			id: bottomLayout
			Layout.fillWidth: true
			Layout.fillHeight: false
			role: "bottom"
			window: window
			layoutString: window.layoutDirectory ? window.layoutDirectory.config.bottom_layout : "[]"
		}
	}

	Timer {
		interval: 80
		repeat: true
		running: true
		onTriggered: {
			if (!window.activePane)
				return
			const action = window.activePane.directory.poll_gamepad()
			if (action.length > 0)
				window.activePane.handleGamepad(action)
		}
	}

	Timer {
		interval: 500
		repeat: true
		running: true
		onTriggered: {
			for (let i = 0; i < window.panes.length; i++)
				window.panes[i].directory.poll_descriptors()
		}
	}

	Timer {
		interval: 2000
		repeat: true
		running: true
		onTriggered: {
			for (let i = 0; i < window.panes.length; i++)
				window.panes[i].directory.refresh_active_items()
		}
	}

	DragTooltip {
		active: window.dragTooltipActive
		action: window.dragTooltipAction
		reposition: window.dragTooltipReposition
		cursorX: window.dragCursorX
		cursorY: window.dragCursorY
	}

	DragPreview {
		previewActive: window.dragPreviewActive && !!window.dragPreviewData
		cursorX: window.dragCursorX
		cursorY: window.dragCursorY
		previewData: window.dragPreviewData
	}

	Connections {
		target: DragHelper

		function onCursorMoved(x, y) {
			if (!window.dragTooltipActive && !window.dragPreviewActive)
				return
			if (!window.contentItem)
				return
			const point = window.contentItem.mapFromGlobal(x, y)
			window.dragCursorX = point.x
			window.dragCursorY = point.y
		}

		function onDragActionChanged(action) {
			window.dragTooltipAction = action
		}

		function onDragFinished() {
			window.dragActive = false
			if (window.dragPreviewActive)
				return
			window.dragTooltipActive = false
			window.dragTooltipReposition = false
		}
	}
}
