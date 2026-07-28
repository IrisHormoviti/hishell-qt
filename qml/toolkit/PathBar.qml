pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

RowLayout {
	id: pathBar
	spacing: Kirigami.Units.smallSpacing

	property var fileModel
	property string currentPath: pathBar.fileModel ? pathBar.fileModel.current_path : ""

	property var segments: {
		var p = pathBar.currentPath;
		if (p === "" || p === ".")
			return ["/"];
		p = p.substring(0, p.length - 1);
		var parts = p.split("/");
		var result = [];
		for (var i = 0; i < parts.length; i++) {
			if (parts[i] !== "") {
				result.push(parts[i]);
			}
		}
		if (result.length === 0)
			result.push("/");
		return result;
	}

	function pathForIndex(idx) {
		var p = pathBar.currentPath;
		if (p === "" || p === ".")
			return "/";
		if (p.endsWith("/") && p.length > 1)
			p = p.substring(0, p.length - 1);
		var parts = p.split("/").filter(function (s) {
			return s !== "";
		});
		var result = "/" + parts.slice(0, idx + 1).join("/");
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
				text: "›"
				font.pointSize: 12
				color: Kirigami.Theme.disabledTextColor
			}

			Button {
				id: crumbButton
				flat: true
				text: delegateRoot.modelData === "/" ? "Root" : delegateRoot.modelData

				background: Rectangle {
					color: delegateRoot.index === pathBar.segments.length - 1 ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15) : "transparent"
					radius: Kirigami.Units.smallSpacing
				}

				contentItem: RowLayout {
					spacing: Kirigami.Units.smallSpacing

					Kirigami.Icon {
						visible: delegateRoot.index === pathBar.segments.length - 1
						source: pathBar.fileModel ? pathBar.fileModel.get_icon_name(pathBar.pathForIndex(delegateRoot.index)) : ""
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
					}

					Label {
						text: crumbButton.text
						color: Kirigami.Theme.textColor
						font.bold: delegateRoot.index === pathBar.segments.length - 1
					}
				}

				onClicked: {
					var target = pathBar.pathForIndex(delegateRoot.index);
					pathBar.fileModel.current_path = target;
				}
			}
		}
	}
}
