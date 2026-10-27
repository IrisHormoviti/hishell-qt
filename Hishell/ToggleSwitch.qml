import QtQuick
import QtQuick.Controls

// The switch for a `Type=Toggle` entry.
//
// The active QML style draws the switch (ClamOS has its own QQC2 style, a
// desktop uses its own), so a toggle entry looks like every other switch in
// the interface instead of a hand-painted imitation.  The slot's MouseArea
// owns the activation, so this switch is a state display only: it never takes
// focus, hover or a press.
Item {
	id: toggle
	property bool on: false

	// The style draws the indicator partly outside the control's own implicit
	// height (ClamOS's has more padding than its content box), so measure the
	// real visual bounds and scale those into the icon slot.  Callers give this
	// item the space the icon would have used.
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
