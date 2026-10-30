// The visual half of closing a folder.
//
// Opening uses the live FolderView itself: it is scaled around the folder icon
// and lifted, so the panel grows out of the icon. Closing cannot do that
// directly, because the grid behind the shrinking folder is the *parent*, which
// only exists after the path changes. A snapshot of the folder being left is
// therefore drawn over the freshly loaded parent and scaled down into the
// folder's icon there.
//
// The image keeps its geometry fixed and is scaled with a scene-graph
// transform, so the animation never re-renders or re-decodes anything.

import QtQuick

Item {
	id: transition
	anchors.fill: parent
	visible: false
	z: 50

	// The grid area of the folder being left, in this view's coordinates.
	property rect gridRect: Qt.rect(0, 0, width, height)
	// The icon it shrinks into, also in this view's coordinates.
	property rect iconRect: Qt.rect(0, 0, 0, 0)
	property int duration: 200
	property real progress: 0

	readonly property real scaleX: 1.0 + (transition.iconRect.width / Math.max(1, transition.gridRect.width) - 1.0) * transition.progress
	readonly property real scaleY: 1.0 + (transition.iconRect.height / Math.max(1, transition.gridRect.height) - 1.0) * transition.progress
	readonly property real opacityFade: transition.progress < 0.75
		? 1.0
		: Math.max(0.0, 1.0 - (transition.progress - 0.75) / 0.25)

	signal finished()

	NumberAnimation {
		id: motion
		target: transition
		property: "progress"
		from: 0
		to: 1
		duration: transition.duration
		easing.type: Easing.OutCubic
		running: false
		onFinished: {
			transition.visible = false;
			transition.finished();
		}
	}

	// Dims the parent behind the shrinking panel; fades out as it settles.
	Rectangle {
		anchors.fill: parent
		color: "black"
		opacity: 0.45 * (1 - transition.progress)
	}

	Image {
		id: snapshot
		x: transition.gridRect.x
		y: transition.gridRect.y
		width: Math.max(1, transition.gridRect.width)
		height: Math.max(1, transition.gridRect.height)
		opacity: transition.opacityFade
		fillMode: Image.Stretch
		smooth: true
		cache: false
		asynchronous: false
		// Scaling about the destination icon's centre makes the whole snapshot
		// converge on the icon: at progress 1 it occupies exactly iconRect.
		transform: Scale {
			origin.x: transition.iconRect.x + transition.iconRect.width / 2 - transition.gridRect.x
			origin.y: transition.iconRect.y + transition.iconRect.height / 2 - transition.gridRect.y
			xScale: transition.scaleX
			yScale: transition.scaleY
		}
	}

	// Keep the grab result alive for as long as the image uses its URL: the
	// image data belongs to the result object, not to the URL string.
	property var snapshotResult: null

	// Swallow presses while the transition runs so a second tap cannot start
	// another navigation on a half-built view.
	MouseArea {
		anchors.fill: parent
		enabled: transition.visible
		acceptedButtons: Qt.AllButtons
	}

	function closeInto(gridRect, iconRect, result) {
		transition.gridRect = gridRect;
		transition.iconRect = iconRect;
		transition.snapshotResult = result;
		snapshot.source = result ? result.url : "";
		transition.progress = 0;
		transition.visible = true;
		motion.restart();
	}

	function cancel() {
		motion.stop();
		transition.visible = false;
	}
}
