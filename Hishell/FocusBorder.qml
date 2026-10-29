// The focus border: four corner brackets drawn around the focused item.
//
// One instance lives in the grid and follows the cursor, rather than every
// FileSlot carrying its own copy. A folder can hold hundreds of items but only
// one is focused, so a per-slot border meant loading and parsing four SVG
// documents for every item on every load. It also lets the border animate from
// one item to the next, which a per-slot border could not do.
//
// Size the host to the slot; the corner brackets scale to it.
//
// The breathing animation moves each bracket outward in pixels rather than
// scaling the whole host. Scaling a wide list row would move its left and
// right corners by several centimetres while the short vertical edges barely
// moved, which read as the border sliding horizontally only.

import QtQuick

Item {
	id: focusBorder

	// Prefix the four corner documents are named from: "<source>-0.svg" is the
	// top-left bracket, then clockwise.
	property string source: ""

	// Half the pulse animation's duration, so a full breath is duration * 4
	// followed by duration * 2, matching the original per-slot border.
	property int duration: 200

	// How far the corners breathe in and out, as a fraction of the shorter
	// side. Capped so a very wide row still moves by a visible few pixels.
	property real movement: 0.03

	// Driven 0 -> 1 -> -1 by the pulse below.
	property real pulse: 0.0

	// Changes whenever the border lands on a different slot. The breath runs
	// after that, then rests: an endlessly animating border kept the panel
	// rendering at the display rate while the shell was otherwise idle.
	property string pulseKey: ""

	readonly property real cornerSize: Math.max(10, Math.round(Math.min(width, height) * 0.3))
	readonly property real travel: Math.min(8, Math.min(width, height) * focusBorder.movement)

	opacity: 0.95 - focusBorder.pulse * 0.35

	// Two breaths per move, then a short settle back to rest. Starting from
	// rest means the border is static (and the panel idle) between moves.
	SequentialAnimation {
		id: breathe
		loops: 2
		running: false
		NumberAnimation {
			target: focusBorder
			property: "pulse"
			to: 1.0
			duration: focusBorder.duration * 4
			easing.type: Easing.InOutQuad
		}
		NumberAnimation {
			target: focusBorder
			property: "pulse"
			to: -1.0
			duration: focusBorder.duration * 2
			easing.type: Easing.InOutQuad
		}
	}
	NumberAnimation {
		id: settle
		target: focusBorder
		property: "pulse"
		to: 0.0
		duration: focusBorder.duration * 2
		easing.type: Easing.InOutQuad
		running: false
	}
	Connections {
		target: breathe
		function onFinished() { settle.restart() }
	}

	onVisibleChanged: if (visible) breathe.restart()
	onPulseKeyChanged: if (visible) breathe.restart()

	Image {
		anchors.left: parent.left
		anchors.top: parent.top
		anchors.leftMargin: -focusBorder.travel * focusBorder.pulse
		anchors.topMargin: -focusBorder.travel * focusBorder.pulse
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-0.svg" : ""
		smooth: true
	}

	Image {
		anchors.right: parent.right
		anchors.top: parent.top
		anchors.rightMargin: -focusBorder.travel * focusBorder.pulse
		anchors.topMargin: -focusBorder.travel * focusBorder.pulse
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-1.svg" : ""
		smooth: true
	}

	Image {
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		anchors.rightMargin: -focusBorder.travel * focusBorder.pulse
		anchors.bottomMargin: -focusBorder.travel * focusBorder.pulse
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-2.svg" : ""
		smooth: true
	}

	Image {
		anchors.left: parent.left
		anchors.bottom: parent.bottom
		anchors.leftMargin: -focusBorder.travel * focusBorder.pulse
		anchors.bottomMargin: -focusBorder.travel * focusBorder.pulse
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-3.svg" : ""
		smooth: true
	}
}
