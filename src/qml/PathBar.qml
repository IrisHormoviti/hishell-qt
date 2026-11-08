import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import hishell_qt

RowLayout {
	id: bar

	property var window: null
	readonly property var directory: bar.window ? bar.window.currentDirectory : null
	readonly property var crumbs: bar.directory ? bar.window.segments(bar.directory.path) : []
	property bool editing: false

	spacing: Kirigami.Units.smallSpacing
	Layout.fillWidth: true

	PathBridge { id: pathUtils }

	Shortcut {
		sequence: "Ctrl+L"
		onActivated: bar.startEditing()
	}

	function startEditing() {
		if (!bar.directory)
			return
		bar.editing = true
		editField.text = String(bar.directory.path)
		Qt.callLater(function () { editField.forceActiveFocus() })
	}

	function commit() {
		if (!bar.directory) {
			bar.editing = false
			return
		}
		const target = pathUtils.resolve_path(String(bar.directory.path), editField.text)
		bar.editing = false
		bar.directory.navigate(target)
	}

	TextField {
		id: editField
		visible: bar.editing
		Layout.fillWidth: true
		onAccepted: bar.commit()
		Keys.onEscapePressed: bar.editing = false
	}

	Connections {
		target: bar.directory
		function onPath_changed() {
			bar.editing = false
		}
	}

	Repeater {
		model: bar.crumbs

		Button {
			id: crumbButton
			required property var modelData
			required property int index
			readonly property bool current: index === bar.crumbs.length - 1

			text: modelData.name
			flat: true
			visible: !bar.editing
			onClicked: {
				if (!bar.directory)
					return
				if (current)
					hereMenu.popup(crumbButton, 0, crumbButton.height)
				else
					bar.directory.navigate(modelData.path)
			}
		}
	}

	Menu {
		id: hereMenu
		property var actions: []
		onAboutToShow: actions = bar.directory
			? JSON.parse(bar.directory.actions_json("context", "location")) : []

		Repeater {
			model: hereMenu.actions

			MenuItem {
				required property var modelData
				text: bar.window.actionLabel(modelData.id)
				enabled: modelData.enabled
				onTriggered: bar.directory.invoke(modelData.id)
			}
		}
	}
}
