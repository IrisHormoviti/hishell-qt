import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Button {
	id: control
	Layout.alignment: Qt.AlignRight
	Layout.preferredWidth: 20
	Layout.preferredHeight: 20

	background: Rectangle {
		color: control.pressed ? Kirigami.Theme.negativeTextColor : "white"
		radius: width / 2
	}

	onClicked: Qt.quit()
}
