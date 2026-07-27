pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

RowLayout {
	id: layoutEngine
	property string layoutString: "[]"

	// Expose fileModel here on the engine
	property var fileModel: null

	visible: layoutEngine.layoutItems.length > 0
	implicitWidth: layoutEngine.layoutItems.length > 0 ? -1 : 0
	implicitHeight: layoutEngine.layoutItems.length > 0 ? -1 : 0

	property var layoutItems: {
		try {
			return JSON.parse(layoutEngine.layoutString);
		} catch (e) {
			return [];
		}
	}

	Repeater {
		model: layoutEngine.layoutItems

		Loader {
			id: componentLoader
			required property string modelData

			source: modelData + ".qml"

			onLoaded: {
				if ("fileModel" in item) {
					item.fileModel = Qt.binding(function () {
						return layoutEngine.fileModel;
					});
				}
			}
		}
	}
}
