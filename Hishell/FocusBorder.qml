// The focus border: four corner brackets drawn around the focused item.
//
// One instance lives in the grid and follows the cursor, rather than every
// FileSlot carrying its own copy. A folder can hold hundreds of items but only
// one is focused, so a per-slot border meant loading and parsing four SVG
// documents for every item on every load. It also lets the border animate from
// one item to the next, which a per-slot border could not do.
//
// Size the host to the slot; the corner brackets scale to it.

import QtQuick

Item {
	id: focusBorder

	// Prefix the four corner documents are named from: "<source>-0.svg" is the
	// top-left bracket, then clockwise.
	property string source: ""

	// Half the pulse animation's duration, so a full breath is duration * 4
	// followed by duration * 2, matching the original per-slot border.
	property int duration: 200

	// How far the corners breathe in and out, as a scale delta.
	property real movement: 0.03

	// Driven 0 -> 1 -> -1 by the pulse below.
	property real pulse: 0.0

	readonly property real cornerSize: Math.max(10, Math.round(Math.min(width, height) * 0.3))

	scale: 1 + focusBorder.pulse * focusBorder.movement
	opacity: 0.95 - focusBorder.pulse * 0.35

	SequentialAnimation on pulse {
		running: focusBorder.visible
		loops: Animation.Infinite
		NumberAnimation {
			to: 1.0
			duration: focusBorder.duration * 4
			easing.type: Easing.InOutQuad
		}
		NumberAnimation {
			to: -1.0
			duration: focusBorder.duration * 2
			easing.type: Easing.InOutQuad
		}
	}

	Image {
		anchors.left: parent.left
		anchors.top: parent.top
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-0.svg" : ""
		smooth: true
	}

	Image {
		anchors.right: parent.right
		anchors.top: parent.top
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-1.svg" : ""
		smooth: true
	}

	Image {
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-2.svg" : ""
		smooth: true
	}

	Image {
		anchors.left: parent.left
		anchors.bottom: parent.bottom
		width: focusBorder.cornerSize
		height: focusBorder.cornerSize
		source: focusBorder.source ? focusBorder.source + "-3.svg" : ""
		smooth: true
	}
}
