pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

// A Slider driven from press/move coordinates only.
//
// Under QT_SCALE_FACTOR > 1 on this device's Wayland compositor, Qt 6.8.2
// delivers the release point of a touch offset by the window's width (a
// pointer released at x on a 206px slider arrives as x + 512). The style
// Slider recomputes its value from the release point, so every drag snapped
// to the maximum on release. Press and move coordinates are correct, so this
// control moves the value from those and ignores the release point.
//
// The value is otherwise a normal bound property: while a drag is in progress
// the internal position is shown, and as soon as it ends the binding takes
// over again, so the owner keeps a single source of truth.
Slider {
	id: control

	// The authoritative value the slider should show when it is not being
	// dragged; the owner binds this to its own setting.
	property real boundValue: 0

	// Emitted as the finger moves, with the value the position corresponds to.
	signal movedTo(real value)

	// Emitted once when the drag ends, so an owner can play one feedback sound
	// per adjustment instead of one per pixel moved.
	signal dragFinished()

	// Emitted while dragging, once per step the handle crosses, so the owner
	// can play a slide tick.
	signal stepped()

	// Emitted when the handle reaches either end of the range, once per end.
	signal reachedEdge(bool atMinimum)

	// Emitted when a drag begins.
	signal dragStarted()

	property bool _dragging: false
	property real _dragValue: 0

	value: control._dragging ? control._dragValue : control.boundValue

	function _valueAt(x) {
		const hw = control.handle ? control.handle.width : 0;
		const extent = control.availableWidth - hw;
		if (extent <= 0)
			return control.value;
		let pos = (x - control.leftPadding - hw / 2) / extent;
		pos = Math.max(0, Math.min(1, pos));
		let v = control.from + (control.to - control.from) * pos;
		if (control.stepSize > 0)
			v = control.from + Math.round((v - control.from) / control.stepSize) * control.stepSize;
		return Math.max(control.from, Math.min(control.to, v));
	}

	// A touch that lands inside the control; the wrong release coordinate is
	// always outside its width, so anything out of bounds is dropped.
	function _apply(x) {
		if (x < 0 || x > control.width)
			return;
		const v = control._valueAt(x);
		// Tick once per step crossed so a drag sounds like discrete notches.
		if (control._dragging && v !== control._dragValue)
			control.stepped();
		// Report reaching an end once, not on every pixel at that end.
		const atMinimum = v <= control.from + 0.0001;
		const atMaximum = v >= control.to - 0.0001;
		if (atMinimum && !control._atMinimum)
			control.reachedEdge(true);
		else if (atMaximum && !control._atMaximum)
			control.reachedEdge(false);
		control._atMinimum = atMinimum;
		control._atMaximum = atMaximum;
		control._dragValue = v;
		control.movedTo(v);
	}

	property bool _atMinimum: false
	property bool _atMaximum: false

	// Consumes the pointer so the style's own handling (which trusts the
	// release point) never runs.
	MouseArea {
		anchors.fill: control
		onPressed: mouse => {
			if (mouse.x < 0 || mouse.x > control.width)
				return;
			control._dragging = true;
			control._atMinimum = false;
			control._atMaximum = false;
			control.dragStarted();
			control._apply(mouse.x);
		}
		onPositionChanged: mouse => control._apply(mouse.x)
		onReleased: {
			control._dragging = false;
			control.dragFinished();
		}
	}
}
