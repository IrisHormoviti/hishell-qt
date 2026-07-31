pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "Hishell"

RowLayout {
	id: layoutEngine
	property string layoutString: "[]"

	required property Directory directory

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
			(function (itemSpec) {
				var isPath = itemSpec.startsWith("/") || itemSpec.startsWith(".") || itemSpec.startsWith("~");
				var componentFile = isPath ? "FolderView.qml" : itemSpec + ".qml";

				var component = Qt.createComponent(componentFile);
				if (component.status === Component.Ready) {
					var obj = component.createObject(layoutEngine);
					if (obj) {
						if ("windowDirectory" in obj) {
							obj.windowDirectory = Qt.binding(function () {
								return layoutEngine.directory;
							});
						}

						if (isPath) {
							var customDir = Qt.createQmlObject('import "Hishell"; Directory {}', obj);
							if (customDir) {
								customDir.path = Qt.binding(function () {
									var base = layoutEngine.directory ? layoutEngine.directory.path : "";
									if (itemSpec.startsWith("/")) {
										return itemSpec;
									}
									if (!base)
										return itemSpec;
									return base + "/" + itemSpec;
								});
								obj.directory = customDir;
								layoutEngine._createdItems.push(customDir);
							}
						} else {
							if ("directory" in obj) {
								obj.directory = Qt.binding(function () {
									return layoutEngine.directory;
								});
							}
						}
						layoutEngine._createdItems.push(obj);
					}
				} else if (component.status === Component.Error) {
					console.error(component.errorString());
				}
			})(layoutEngine.layoutItems[j]);
		}
	}
}
