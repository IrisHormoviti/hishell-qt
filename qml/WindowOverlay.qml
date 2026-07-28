import QtQuick

Item {
	id: root
	anchors.fill: parent
	z: 9999

	property var targetWindow: Window.window
	property int margin: 12

	MouseArea {
		anchors.fill: parent
		hoverEnabled: true

		function getEdges(x, y) {
			var e = 0;
			if (x <= root.margin)
				e |= Qt.LeftEdge;
			if (x >= width - root.margin)
				e |= Qt.RightEdge;
			if (y <= root.margin)
				e |= Qt.TopEdge;
			if (y >= height - root.margin)
				e |= Qt.BottomEdge;
			return e;
		}

		cursorShape: {
			var e = getEdges(mouseX, mouseY);
			if (e === (Qt.TopEdge | Qt.LeftEdge) || e === (Qt.BottomEdge | Qt.RightEdge))
				return Qt.SizeFDiagCursor;
			if (e === (Qt.TopEdge | Qt.RightEdge) || e === (Qt.BottomEdge | Qt.LeftEdge))
				return Qt.SizeBDiagCursor;
			if (e & (Qt.LeftEdge | Qt.RightEdge))
				return Qt.SizeHorCursor;
			if (e & (Qt.TopEdge | Qt.BottomEdge))
				return Qt.SizeVerCursor;
			return Qt.ArrowCursor;
		}

		onPressed: mouse => {
			var e = getEdges(mouse.x, mouse.y);
			if (e !== 0 && root.targetWindow) {
				root.targetWindow.startSystemResize(e);
			} else {
				mouse.accepted = false; // Propagate click through to buttons/UI below
			}
		}
	}
}
