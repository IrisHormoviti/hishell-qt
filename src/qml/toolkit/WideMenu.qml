import QtQuick
import QtQuick.Controls
import org.kde.kirigami as Kirigami

// Qt Quick Controls sizes a menu to the text and shortcut without a gap.
// Give every menu enough room for both labels before it becomes visible, so
// opening it does not resize the popup.
Menu {
	function fitWidth() {
		width = implicitWidth + Kirigami.Units.gridUnit * 4
	}

	Component.onCompleted: fitWidth()
	onImplicitWidthChanged: if (!opened)
		fitWidth()
}
