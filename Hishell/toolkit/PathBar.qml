pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

RowLayout {
	id: pathBar
	spacing: Kirigami.Units.mediumSpacing

	property ShellWindow window
	property Directory directory
	property string currentPath: pathBar.directory ? pathBar.directory.path : ""

	property var segments: {
		let p = pathBar.currentPath;
		if (p === "" || p === ".")
			return ["/"];
		if (p.endsWith("/") && p.length > 1)
			p = p.substring(0, p.length - 1);
		const parts = p.split("/");
		let result = [];
		for (let i = 0; i < parts.length; i++) {
			if (parts[i] !== "") {
				result.push(parts[i]);
			}
		}
		if (result.length === 0)
			result.push("/");
		return result;
	}

	function pathForIndex(idx) {
		let p = pathBar.currentPath;
		if (p === "" || p === ".")
			return "/";
		if (p.endsWith("/") && p.length > 1)
			p = p.substring(0, p.length - 1);
		const parts = p.split("/").filter(function (s) {
			return s !== "";
		});
		const result = "/" + parts.slice(0, idx + 1).join("/");

		return result;
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
				fileManager: pathBar.window.fileManager
				actionManager: pathBar.window.actionManager

				is_dir: true
				index: delegateRoot.index
				gridSize: 32
				labelBesideIcon: true
				isSelected: delegateRoot.index === pathBar.segments.length - 1
				fixedWidth: false

				Layout.preferredWidth: implicitWidth
				Layout.preferredHeight: implicitHeight

				// onNavigate: targetPath => {
				// 	pathBar.directory.path = targetPath;
				// }
			}
		}
	}
}
