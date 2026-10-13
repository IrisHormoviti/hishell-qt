import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Button {
	id: control
	Layout.alignment: Qt.AlignRight
	Layout.preferredWidth: Kirigami.Units.iconSizes.small
	Layout.preferredHeight: Kirigami.Units.iconSizes.small

	Layout.rightMargin: Kirigami.Units.largeSpacing
	Layout.leftMargin: Kirigami.Units.largeSpacing

	property Directory directory

	visible: !directory.config.native_titlebar

	// Event sounds (ClamOS XDG sound theme).
	function playSound(name) {
		const w = control.Window.window;
		if (w && w.sound)
			w.sound.play(name);
	}

	background: Rectangle {
		color: control.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
		radius: width / 2

		Kirigami.Icon {
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
