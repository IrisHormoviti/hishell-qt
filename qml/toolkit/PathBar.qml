pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../Hishell"

RowLayout {
	id: pathBar
	spacing: Kirigami.Units.smallSpacing

	property Directory directory
	property string currentPath: pathBar.directory ? pathBar.directory.path : ""

	property var segments: {
		var p = pathBar.currentPath;
		if (p === "" || p === ".")
			return ["/"];
		if (p.endsWith("/") && p.length > 1)
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
				text: "/"
				font.pointSize: 12
				color: Kirigami.Theme.disabledTextColor
			}

			Button {
				id: crumbButton
				flat: true
				hoverEnabled: true
				text: delegateRoot.modelData === "/" ? "/" : delegateRoot.modelData
				padding: Kirigami.Units.mediumSpacing
				implicitWidth: leftPadding + rightPadding + contentLayout.implicitWidth
				Kirigami.Theme.colorSet: Kirigami.Theme.Inactive

				background: Rectangle {
					color: (
						delegateRoot.index === pathBar.segments.length - 1
						? Kirigami.Theme.backgroundColor : "transparent"
					)
					radius: Kirigami.Units.mediumSpacing
				}

				contentItem: RowLayout {
					id: contentLayout
					spacing: Kirigami.Units.mediumSpacing

					Kirigami.Icon {
						visible: delegateRoot.index === pathBar.segments.length - 1
						source: pathBar.directory ? pathBar.directory.get_icon(pathBar.pathForIndex(delegateRoot.index)) : ""
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
					}

					Label {
						text: crumbButton.text
						color: Kirigami.Theme.textColor
						font.bold: delegateRoot.index === pathBar.segments.length - 1
						Layout.minimumWidth: implicitWidth
						elide: Text.ElideNone
					}
				}

				onClicked: {
					var target = pathBar.pathForIndex(delegateRoot.index);
					pathBar.directory.path = target;
				}
			}
		}
	}
}
