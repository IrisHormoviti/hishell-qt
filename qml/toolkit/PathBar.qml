pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Hishell"
import "../"

RowLayout {
	id: pathBar
	spacing: Kirigami.Units.smallSpacing

	property ShellWindow window
	property Directory directory
	property var pathUtils: window.pathUtils
	property string currentPath: pathBar.directory ? pathBar.directory.path : ""

	property var segments: {
		return pathUtils ? pathUtils.get_segments(currentPath) : ["/"];
	}

	function pathForIndex(idx) {
		return pathUtils ? pathUtils.path_for_index(currentPath, idx) : currentPath;
	}

	Repeater {
		model: pathBar.segments

		delegate: RowLayout {
			id: delegateRoot
			spacing: Kirigami.Units.smallSpacing

			// Qualify delegate properties for qmllint
			required property int index
			required property string modelData

			Label {
				visible: delegateRoot.index > 0
				text: "/"
				font.pointSize: 12
				color: Kirigami.Theme.disabledTextColor
			}

			FileSlot {
				id: crumbSlot
				path: pathBar.pathForIndex(delegateRoot.index)
				title: delegateRoot.modelData === "/" ? "/" : delegateRoot.modelData
				icon: delegateRoot.index === pathBar.segments.length - 1 && pathBar.directory ? String(pathBar.directory.icon) : ""
				dragDropHandler: pathBar.window.dragDropHandler

				is_dir: true
				index: delegateRoot.index
				gridSize: 22
				labelBesideIcon: true
				isSelected: delegateRoot.index === pathBar.segments.length - 1
				fixedWidth: false

				Layout.preferredWidth: implicitWidth
				Layout.preferredHeight: implicitHeight

				onNavigate: targetPath => {
					pathBar.directory.path = targetPath;
				}
			}
		}
	}
}
