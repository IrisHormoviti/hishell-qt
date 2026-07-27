import QtQuick
import QtQuick.Layouts

RowLayout {
	id: root
	property string layoutString: "[]"

	// Collapse entirely when there are no items
	visible: root.layoutItems.length > 0
	implicitWidth: root.layoutItems.length > 0 ? undefined : 0
	implicitHeight: root.layoutItems.length > 0 ? undefined : 0

	property var layoutItems: {
		try {
			return JSON.parse(root.layoutString);
		} catch (e) {
			console.warn("Failed to parse layout string: " + root.layoutString);
			return [];
		}
	}

	Repeater {
		model: root.layoutItems

		Loader {
			id: componentLoader
			source: modelData + ".qml"

			onStatusChanged: {
				if (componentLoader.status == Loader.Error) {
					console.error("Failed to load component: " + componentLoader.source);
				}
			}
		}
	}
}
