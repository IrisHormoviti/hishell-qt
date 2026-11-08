import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import hishell_qt

ApplicationWindow {
	id: window
	width: 1100
	height: 650
	visible: true
	title: "hishell"

	required property var leftDirectory
	required property var rightDirectory

	property Item activePane: null

	function switchPane(direction) {
		if (direction === "right" && window.activePane === leftPane) {
			window.activePane = rightPane
			rightPane.focusFirst()
		} else if (direction === "left" && window.activePane === rightPane) {
			window.activePane = leftPane
			leftPane.focusLast()
		}
	}

	SplitView {
		anchors.fill: parent
		orientation: Qt.Horizontal

		handle: Rectangle {
			implicitWidth: 3
			color: palette.mid
		}

		FolderPane {
			id: leftPane
			SplitView.preferredWidth: window.width / 2
			directory: window.leftDirectory
			active: window.activePane === leftPane
			onActivated: window.activePane = leftPane
			onFocusEdge: function (direction) { window.switchPane(direction) }
		}

		FolderPane {
			id: rightPane
			SplitView.preferredWidth: window.width / 2
			directory: window.rightDirectory
			active: window.activePane === rightPane
			onActivated: window.activePane = rightPane
			onFocusEdge: function (direction) { window.switchPane(direction) }
		}
	}

	Component.onCompleted: window.activePane = leftPane

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
			leftPane.directory.poll_descriptors()
			rightPane.directory.poll_descriptors()
		}
	}
}
