import QtQuick
import QtQuick.Controls

// A Slider driven from press/move coordinates only. The style Slider
// recomputes its value from the release point, which is wrong on scaled
// touch setups; press and move coordinates are correct.
Slider {
	id: control

	// The authoritative value the slider should show when it is not being
	// dragged; the owner binds this to its own setting.
	property real boundValue: 0

	signal movedTo(real value)
	signal dragFinished()
	signal stepped()
	signal reachedEdge(bool atMinimum)
	signal dragStarted()

	property bool _dragging: false
	property real _dragValue: 0
	property bool _atMinimum: false
	property bool _atMaximum: false

	value: control._dragging ? control._dragValue : control.boundValue

	function _valueAt(x) {
		const handleWidth = control.handle ? control.handle.width : 0
		const extent = control.availableWidth - handleWidth
		if (extent <= 0)
			return control.value
		let pos = (x - control.leftPadding - handleWidth / 2) / extent
		pos = Math.max(0, Math.min(1, pos))
		let value = control.from + (control.to - control.from) * pos
		if (control.stepSize > 0)
			value = control.from + Math.round((value - control.from) / control.stepSize) * control.stepSize
		return Math.max(control.from, Math.min(control.to, value))
	}

	function _apply(x) {
		if (x < 0 || x > control.width)
			return
		const value = control._valueAt(x)
		if (control._dragging && value !== control._dragValue)
			control.stepped()
		const atMinimum = value <= control.from + 0.0001
		const atMaximum = value >= control.to - 0.0001
		if (atMinimum && !control._atMinimum)
			control.reachedEdge(true)
		else if (atMaximum && !control._atMaximum)
			control.reachedEdge(false)
		control._atMinimum = atMinimum
		control._atMaximum = atMaximum
		control._dragValue = value
		control.movedTo(value)
	}

	MouseArea {
		anchors.fill: control
		onPressed: mouse => {
			if (mouse.x < 0 || mouse.x > control.width)
				return
			control._dragging = true
			control._atMinimum = false
			control._atMaximum = false
			control.dragStarted()
			control._apply(mouse.x)
		}
		onPositionChanged: mouse => control._apply(mouse.x)
		onReleased: {
			control._dragging = false
			control.dragFinished()
		}
	}
}
