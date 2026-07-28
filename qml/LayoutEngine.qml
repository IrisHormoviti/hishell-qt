pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

RowLayout {
	id: layoutEngine
	property string layoutString: "[]"
	property var fileModel: null

	property var layoutItems: {
		try {
			return JSON.parse(layoutEngine.layoutString);
		} catch (e) {
			return [];
		}
	}

	visible: layoutEngine.layoutItems.length > 0
	implicitWidth: layoutEngine.layoutItems.length > 0 ? -1 : 0
	implicitHeight: layoutEngine.layoutItems.length > 0 ? -1 : 0

	property var _createdItems: []

	onLayoutItemsChanged: updateLayout()
	Component.onCompleted: updateLayout()

	function updateLayout() {
		for (var i = 0; i < layoutEngine._createdItems.length; i++) {
			layoutEngine._createdItems[i].destroy();
		}
		layoutEngine._createdItems = [];

		for (var j = 0; j < layoutEngine.layoutItems.length; j++) {
			var component = Qt.createComponent(layoutEngine.layoutItems[j] + ".qml");
			if (component.status === Component.Ready) {
				var obj = component.createObject(layoutEngine);
				if (obj) {
					if ("fileModel" in obj) {
						obj.fileModel = Qt.binding(function () {
							return layoutEngine.fileModel;
						});
					}
					layoutEngine._createdItems.push(obj);
				}
			} else if (component.status === Component.Error) {
				console.error(component.errorString());
			}
		}
	}
}
