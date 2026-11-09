import QtQuick
import QtQuick.Controls

// The switch for a `Type=Toggle` entry. The style draws the switch, so a
// toggle entry looks like every other switch in the interface instead of a
// hand-painted imitation. The slot's MouseArea owns activation; this switch is
// a state display only and never takes focus, hover or a press.
Item {
	id: toggle

	property bool on: false

	// The style draws the indicator partly outside the control's own implicit
	// height, so measure the real visual bounds and scale those into the slot.
	readonly property real switchWidth: control.implicitWidth
	readonly property real switchHeight: Math.max(
		control.implicitHeight,
		control.indicator
			? control.indicator.implicitHeight + control.topPadding + control.bottomPadding
			: 0)

	implicitWidth: toggle.switchWidth
	implicitHeight: toggle.switchHeight

	Switch {
		id: control
		anchors.centerIn: parent
		checked: toggle.on
		text: ""
		focusPolicy: Qt.NoFocus
		activeFocusOnTab: false
		hoverEnabled: false
		transformOrigin: Item.Center
		scale: Math.min(
			toggle.width / Math.max(1, toggle.switchWidth),
			toggle.height / Math.max(1, toggle.switchHeight))
	}
}
