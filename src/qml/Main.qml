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
	property bool dragPreviewActive: false
	property var dragPreviewData: null
	property real dragCursorX: 0
	property real dragCursorY: 0
	property bool dragActive: false
	property bool dragGhostActive: false
	property string dragGhostSource: ""
	property var dragGhostGrab: null
	property real dragGhostWidth: 0
	property real dragGhostHeight: 0
	property bool dragTooltipActive: false
	property bool dragTooltipReposition: false
	property string dragTooltipAction: "copy"

	Component.onCompleted: {
		if (leftDirectory && leftDirectory.config.maximized)
			window.showMaximized()
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
			"rotate-image": "Rotate Clockwise"
		}
		return labels[id] || id
	}


	Shortcut {
		sequence: "Ctrl+O"
		onActivated: if (window.currentDirectory) window.currentDirectory.invoke("open")
	}

	Shortcut {
		sequence: "Ctrl+Alt+O"
		onActivated: if (window.currentDirectory) window.currentDirectory.invoke("open-with")
	}

	ColumnLayout {
		id: content
		anchors.fill: parent
		spacing: 0

		Item {
			Layout.fillWidth: true
			Layout.preferredHeight: Math.max(48, Kirigami.Units.gridUnit * 3)

			Rectangle {
				anchors.fill: parent
				color: Kirigami.Theme.backgroundColor
			}

			LayoutEngine {
				id: headerLayout
				anchors.fill: parent
				role: "header"
				window: window
				layoutString: window.currentDirectory
					? window.currentDirectory.config.header_layout
					: '["toolkit/PathBar","toolkit/Spacer","toolkit/MenuBar","toolkit/WindowControl"]'
			}
		}

		LayoutEngine {
			id: topLayout
			Layout.fillWidth: true
			Layout.fillHeight: false
			role: "top"
			window: window
			layoutString: window.currentDirectory ? window.currentDirectory.config.top_layout : "[]"
		}

		LayoutEngine {
			id: middleLayout
			Layout.fillWidth: true
			Layout.fillHeight: true
			role: "middle"
			window: window
			layoutString: window.testMiddleLayout.length > 0
				? window.testMiddleLayout
				: (window.currentDirectory ? window.currentDirectory.config.middle_layout : '["./"]')
		}

		LayoutEngine {
			id: bottomLayout
			Layout.fillWidth: true
			Layout.fillHeight: false
			role: "bottom"
			window: window
			layoutString: window.currentDirectory ? window.currentDirectory.config.bottom_layout : "[]"
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

	// The shell's ghost stands in for the compositor's drag icon unless the
	// folder asks for the native one, like the old ShellWindow ghost.
	Image {
		z: 9997
		source: window.dragGhostSource
		width: window.dragGhostWidth
		height: window.dragGhostHeight
		x: window.dragCursorX - width / 2
		y: window.dragCursorY - height / 2
		visible: window.dragGhostActive && source != "" && width > 0
			&& !(window.currentDirectory
				&& window.currentDirectory.config.native_drag)
		opacity: 0.9
		enabled: false
		fillMode: Image.PreserveAspectFit
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
			window.dragGhostActive = false
			window.dragGhostSource = ""
			window.dragGhostGrab = null
			if (window.dragPreviewActive)
				return
			window.dragTooltipActive = false
			window.dragTooltipReposition = false
		}
	}
}
