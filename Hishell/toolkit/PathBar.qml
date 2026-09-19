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
	property string homePath: String(window.fileManager.get_home_directory());

	property var segments: {
		let p = pathBar.currentPath;
		let home = pathBar.homePath;
		if (p === "" || p === ".")
			return ["/"];
		if (p.endsWith("/") && p.length > 1)
			p = p.substring(0, p.length - 1);
		if (home.endsWith("/") && home.length > 1)
			home = home.substring(0, home.length - 1);

		if (p === home || p.startsWith(home + "/")) {
			let rel = p === home ? "" : p.substring(home.length + 1);
			let homeName = home.split("/").pop();
			let result = [homeName];
			if (rel !== "") {
				const parts = rel.split("/");
				for (let i = 0; i < parts.length; i++) {
					if (parts[i] !== "") {
						result.push(parts[i]);
					}
				}
			}
			return result;
		} else {
			const parts = p.split("/");
			let result = ["/"];
			for (let i = 0; i < parts.length; i++) {
				if (parts[i] !== "") {
					result.push(parts[i]);
				}
			}
			return result;
		}
	}

	function pathForIndex(idx) {
		let p = pathBar.currentPath;
		let home = pathBar.homePath;
		if (p === "" || p === ".")
			return "/";
		if (p.endsWith("/") && p.length > 1)
			p = p.substring(0, p.length - 1);
		if (home.endsWith("/") && home.length > 1)
			home = home.substring(0, home.length - 1);

		if (p === home || p.startsWith(home + "/")) {
			if (idx === 0)
				return home;
			let rel = p === home ? "" : p.substring(home.length + 1);
			const parts = rel.split("/").filter(function (s) {
				return s !== "";
			});
			return home + "/" + parts.slice(0, idx).join("/");
		} else {
			if (idx === 0)
				return "/";
			const parts = p.split("/").filter(function (s) {
				return s !== "";
			});
			return "/" + parts.slice(0, idx).join("/");
		}
	}

	Repeater {
		model: pathBar.segments

		delegate: RowLayout {
			id: delegateRoot
			spacing: Kirigami.Units.smallSpacing

			required property int index
			required property string modelData

			Label {
				visible: delegateRoot.index > 0 && (pathBar.segments[0] !== "/" || delegateRoot.index > 1)
				text: "/"
				font.pointSize: 12
				color: Kirigami.Theme.disabledTextColor
			}

			FileSlot {
				id: crumbSlot
				path: pathBar.pathForIndex(delegateRoot.index)
				title: delegateRoot.modelData === "/" ? "/" : delegateRoot.modelData
				showIcon: delegateRoot.index === pathBar.segments.length - 1

				dragDropHandler: pathBar.window.dragDropHandler
				fileManager: pathBar.window.fileManager
				actionManager: pathBar.window.actionManager

				is_dir: true
				index: delegateRoot.index
				gridSize: Kirigami.Units.iconSizes.smallMedium
				labelBesideIcon: true
				isSelected: delegateRoot.index === pathBar.segments.length - 1
				fixedWidth: false

				Layout.preferredWidth: implicitWidth
				Layout.preferredHeight: implicitHeight
			}
		}
	}
}
