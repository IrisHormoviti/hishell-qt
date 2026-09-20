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

	background: Rectangle {
		color: control.hovered ? Kirigami.Theme.highlightColor : Kirigami.Theme.textColor
		radius: width / 2

		Kirigami.Icon {
			source: "xsi-window-close-symbolic"
			visible: control.hovered
			anchors.fill: parent
		}
	}

	onClicked: Qt.quit()
}
