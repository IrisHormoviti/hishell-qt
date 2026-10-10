pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

RowLayout {
	id: layoutEngine
	property string layoutString: "[]"
	property string errorString: ""

	required property Directory directory
	required property ShellWindow window

	property var layoutItems: []
	property var _createdItems: []

	visible: layoutEngine.layoutItems.length > 0 || layoutEngine.errorString.length > 0
	implicitWidth: visible ? -1 : 0
	implicitHeight: visible ? -1 : 0

	onLayoutStringChanged: rebuild()
	onLayoutItemsChanged: updateLayout()
	Component.onCompleted: rebuild()

	Text {
		visible: layoutEngine.errorString.length > 0
		Layout.fillWidth: true
		text: layoutEngine.errorString
		color: Kirigami.Theme.negativeTextColor
		wrapMode: Text.WordWrap
	}

	function rebuild() {
		layoutEngine.errorString = "";
		let items = [];
		try {
			const parsed = JSON.parse(layoutEngine.layoutString);
			if (Array.isArray(parsed)) {
				items = parsed;
			} else {
				layoutEngine.errorString = "Layout error: expected a JSON array, got: " + layoutEngine.layoutString;
			}
		} catch (e) {
			layoutEngine.errorString = "Layout error: " + e.message;
		}
		layoutEngine.layoutItems = items;
	}

	// Resolve a layout entry against the window's current folder, collapsing the
	// "." segments so "./" resolves to the base folder itself.
	function resolveEntryPath(itemSpec) {
		const base = layoutEngine.directory ? String(layoutEngine.directory.path) : "";
		let resolved = itemSpec;
		if (!itemSpec.startsWith("/")) {
			if (!base)
				return itemSpec;
			resolved = base + "/" + itemSpec;
		}
		return resolved.replace(/\/\.\//g, "/").replace(/\/\.$/, "").replace(/\/+$/, "") || "/";
	}

	function updateLayout() {
		for (let i = 0; i < layoutEngine._createdItems.length; i++) {
			layoutEngine._createdItems[i].destroy();
		}
		layoutEngine._createdItems = [];

		let errors = [];
		for (let j = 0; j < layoutEngine.layoutItems.length; j++) {
			const itemSpec = layoutEngine.layoutItems[j];
			if (typeof itemSpec !== "string") {
				errors.push("Layout error: entry " + j + " is not a path or component name.");
				continue;
			}

			const isPath = itemSpec.startsWith("/") || itemSpec.startsWith(".") || itemSpec.startsWith("~");
			const componentFile = isPath ? "FolderView.qml" : itemSpec + ".qml";

			const component = Qt.createComponent(componentFile);
			if (component.status === Component.Error) {
				errors.push("Failed to load '" + componentFile + "': " + component.errorString().trim());
				continue;
			}
			if (component.status !== Component.Ready) {
				errors.push("Failed to load '" + componentFile + "': component is not ready.");
				continue;
			}

			const obj = component.createObject(layoutEngine);
			if (!obj) {
				errors.push("Failed to instantiate '" + componentFile + "'.");
				continue;
			}

			if ("window" in obj) {
				obj.window = Qt.binding(() => layoutEngine.window);
			}
			if ("directory" in obj) {
				obj.directory = Qt.binding(() => layoutEngine.directory);
			}
			if ("paneCount" in obj) {
				obj.paneCount = layoutEngine.layoutItems.length;
			}

			if (isPath) {
				// A layout entry that resolves to the window's current folder shares its
				// Directory (and therefore its config), so view settings changed through
				// the menus apply to this pane immediately.
				const base = layoutEngine.directory ? String(layoutEngine.directory.path) : "";
				const isCurrentFolder = base !== "" && layoutEngine.resolveEntryPath(itemSpec) === layoutEngine.resolveEntryPath(base);
				if (!isCurrentFolder) {
					const customDir = Qt.createQmlObject('import Hishell; Directory {}', obj);
					if (customDir) {
						customDir.path = Qt.binding(() => layoutEngine.resolveEntryPath(itemSpec));
						obj.directory = customDir;
						layoutEngine._createdItems.push(customDir);
					}
				}
			}

			layoutEngine._createdItems.push(obj);
		}

		if (errors.length > 0)
			layoutEngine.errorString = errors.join("\n");
	}
}
