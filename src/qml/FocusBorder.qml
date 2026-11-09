import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami

// The focus border: four corner brackets drawn around the focused item.
// One instance lives in the view and follows the cursor, rather than every
// FileSlot carrying its own copy, and it can animate from one item to the next.
// Size the host to the slot; the corner brackets scale to it.
Item {
	id: focusBorder

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

	readonly property real cornerSize: Math.max(10,
		Math.round(Math.min(width, height) * 0.3))
	readonly property real travel: Math.min(8,
		Math.min(width, height) * focusBorder.movement)

	opacity: 0.95 - focusBorder.pulse * 0.35

	// Two breaths per move, then a short settle back to rest.
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

	// The old border came from four focus-border-N.svg documents. The shape is
	// one bracket rotated into each corner, so the same path is drawn four
	// times with the same 7.5-unit bevel stroke.
	Repeater {
		model: [0, 90, 180, 270]

		delegate: Item {
			required property int modelData

			width: focusBorder.cornerSize
			height: focusBorder.cornerSize
			x: (modelData === 0 || modelData === 270)
				? -focusBorder.travel * focusBorder.pulse
				: focusBorder.width - width
					+ focusBorder.travel * focusBorder.pulse
			y: (modelData === 0 || modelData === 90)
				? -focusBorder.travel * focusBorder.pulse
				: focusBorder.height - height
					+ focusBorder.travel * focusBorder.pulse
			rotation: modelData

			Shape {
				width: 32
				height: 32
				scale: focusBorder.cornerSize / 32
				transformOrigin: Item.TopLeft

				ShapePath {
					strokeColor: Kirigami.Theme.highlightColor
					strokeWidth: 7.5
					fillColor: "transparent"
					capStyle: ShapePath.FlatCap
					joinStyle: ShapePath.BevelJoin

					PathSvg {
						path: "M 8,27.744298 V 14 c 0,-4 2.000431,-6.0587208 6,-6 l 10.352255,0.1519897"
					}
				}
			}
		}
	}
}
