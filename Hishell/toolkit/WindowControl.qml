import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Hishell.Theme
import Hishell

Button {
	id: control
	Layout.alignment: Qt.AlignRight
	Layout.preferredWidth: Units.iconSizes.small
	Layout.preferredHeight: Units.iconSizes.small

	Layout.rightMargin: Units.largeSpacing
	Layout.leftMargin: Units.largeSpacing

	property Directory directory

	visible: !directory.config.native_titlebar

	// Event sounds (ClamOS XDG sound theme).
	function playSound(name) {
		const w = control.Window.window;
		if (w && w.sound)
			w.sound.play(name);
	}

	background: Rectangle {
		color: control.hovered ? Theme.highlightColor : Theme.textColor
		radius: width / 2

		Icon {
			source: "xsi-window-close-symbolic"
			visible: control.hovered
			anchors.fill: parent
		}
	}

	onPressed: control.playSound("button-pressed")
	onReleased: control.playSound("button-released")
	onClicked: {
		control.playSound("window-close");
		Qt.quit();
	}
}
