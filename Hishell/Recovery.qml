pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme

// The recovery screen the shell shows when it has crashed.
//
// The supervisor in /usr/bin/hishell runs `clam-shell --recovery` in place of
// the file manager after a crash. This window is deliberately tiny and shares
// nothing with the file manager: no Directory, no Config, no model. If the
// file manager's crash was in one of those, this still comes up.
//
// It offers one action — restart the shell — and restarts by itself after a

// way the process exits and the supervisor starts the real shell again.
Window {
	id: recovery

	width: 512
	height: 384
	// Fullscreen: weston pins a fullscreen surface to whichever output sits at
	// the virtual-desktop origin when it maps. The host puts the touch panel
	// (DSI-2) at the origin before this window is created and restores the stock
	// arrangement only after it closes, so the prompt lands on the touch panel
	// (which is the one with a screen to tap). Choosing the output by name does
	// not move an already-shown window here, so the origin is what decides it.
	visible: true
	visibility: Window.FullScreen
	color: "black"
	title: qsTr("Shell recovery")

	// Seconds until the shell restarts on its own. Tapping Restart does it now.
	// Long enough to read the diagnostic below.
	property int secondsLeft: 20

	// What the supervisor recorded about the crash (exit status, signal, the
	// tail of the log). A context property set by the host; empty when absent.
	readonly property string diagnostic: typeof recoveryDiagnostic !== "undefined" ? String(recoveryDiagnostic) : ""

	signal restartRequested()

	function restart() {
		if (recovery.secondsLeft < 0)
			return;
		recovery.secondsLeft = -1;
		recovery.restartRequested();
		Qt.quit();
	}

	// Keys attach to an Item, not a Window, so the whole content is one focus
	// scope. It takes the focus on sight, which is what makes Back / A / Enter
	// restart without the touchscreen.
	Item {
		id: content
		anchors.fill: parent
		focus: true

		Component.onCompleted: content.forceActiveFocus()

		Keys.onPressed: event => {
			switch (event.key) {
			case Qt.Key_Escape:
			case Qt.Key_Back:
			case Qt.Key_Backspace:
			case Qt.Key_Return:
			case Qt.Key_Enter:
			case Qt.Key_Space:
				recovery.restart();
				event.accepted = true;
				break;
			}
		}

		ColumnLayout {
			id: column
			anchors.fill: parent
			anchors.margins: Units.largeSpacing
			spacing: Units.smallSpacing

			Icon {
				source: "dialog-error"
				Layout.alignment: Qt.AlignHCenter
				Layout.preferredWidth: Units.iconSizes.large
				Layout.preferredHeight: Units.iconSizes.large
			}

			Label {
				text: qsTr("The shell crashed!")
				Layout.fillWidth: true
				horizontalAlignment: Text.AlignHCenter
				font.pointSize: 14
				font.weight: Font.DemiBold
				color: "white"
			}

			Button {
				text: qsTr("Press Return to restart")
				Layout.alignment: Qt.AlignHCenter
				Layout.preferredWidth: Units.gridUnit * 12
				Layout.preferredHeight: Units.gridUnit * 2.5
				onClicked: recovery.restart()
			}

			// The diagnostic: what the supervisor recorded, kept small and dim
			// so it is there when wanted but the message still leads.
			Rectangle {
				Layout.fillWidth: true
				Layout.fillHeight: true
				Layout.minimumHeight: Units.gridUnit * 3
				visible: recovery.diagnostic !== ""
				color: Qt.rgba(1, 1, 1, 0.08)
				radius: Units.cornerRadius
				clip: true

				Flickable {
					anchors.fill: parent
					anchors.margins: Units.smallSpacing
					contentWidth: width
					contentHeight: diagnosticText.implicitHeight
					clip: true
					boundsBehavior: Flickable.StopAtBounds

					Text {
						id: diagnosticText
						width: parent.width
						text: recovery.diagnostic
						color: "white"
						opacity: 0.7
						font.family: "monospace"
						font.pointSize: 7
						wrapMode: Text.WrapAnywhere
					}
				}
			}
		}
	}
}
