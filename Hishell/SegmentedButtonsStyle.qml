import QtQuick
import ClamOS

// The ClamOS style's own segmented control. Loaded by SegmentedButtons.qml
// only when the ClamOS QML modules are installed; the width follows the
// layout cell instead of the control's own implicit width.

SegmentedButtons {
	width: parent ? parent.width : implicitWidth
}
