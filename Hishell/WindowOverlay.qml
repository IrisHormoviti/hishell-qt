import QtQuick

Item {
	id: root
	anchors.fill: parent
	z: 9999

	property var targetWindow: Window.window
	property int margin: 12

	MouseArea {
		id: topEdge
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.top: parent.top
		height: root.margin
		hoverEnabled: true
		cursorShape: {
			if (mouseX <= root.margin)
				return Qt.SizeFDiagCursor;
			if (mouseX >= width - root.margin)
				return Qt.SizeBDiagCursor;
			return Qt.SizeVerCursor;
		}
		onPressed: mouse => {
			let e = Qt.TopEdge;
			if (mouse.x <= root.margin)
				e |= Qt.LeftEdge;
			if (mouse.x >= width - root.margin)
				e |= Qt.RightEdge;
			if (root.targetWindow)
				root.targetWindow.startSystemResize(e);
		}
	}

	MouseArea {
		id: bottomEdge
		anchors.left: parent.left
		anchors.right: parent.right
		anchors.bottom: parent.bottom
		height: root.margin
		hoverEnabled: true
		cursorShape: {
			if (mouseX <= root.margin)
				return Qt.SizeBDiagCursor;
			if (mouseX >= width - root.margin)
				return Qt.SizeFDiagCursor;
			return Qt.SizeVerCursor;
		}
		onPressed: mouse => {
			let e = Qt.BottomEdge;
			if (mouse.x <= root.margin)
				e |= Qt.LeftEdge;
			if (mouse.x >= width - root.margin)
				e |= Qt.RightEdge;
			if (root.targetWindow)
				root.targetWindow.startSystemResize(e);
		}
	}

	MouseArea {
		id: leftEdge
		anchors.left: parent.left
		anchors.top: topEdge.bottom
		anchors.bottom: bottomEdge.top
		width: root.margin
		hoverEnabled: true
		cursorShape: Qt.SizeHorCursor
		onPressed: mouse => {
			if (root.targetWindow)
				root.targetWindow.startSystemResize(Qt.LeftEdge);
		}
	}

	MouseArea {
		id: rightEdge
		anchors.right: parent.right
		anchors.top: topEdge.bottom
		anchors.bottom: bottomEdge.top
		width: root.margin
		hoverEnabled: true
		cursorShape: Qt.SizeHorCursor
		onPressed: mouse => {
			if (root.targetWindow)
				root.targetWindow.startSystemResize(Qt.RightEdge);
		}
	}
}
