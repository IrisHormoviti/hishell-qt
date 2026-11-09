import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import hishell_qt

RowLayout {
	id: pathBar

	property var window
	readonly property var directory: pathBar.window ? pathBar.window.currentDirectory : null
	readonly property string currentPath: pathBar.directory ? String(pathBar.directory.path) : ""
	readonly property var crumbs: pathBar.directory
		? pathBar.window.segments(pathBar.directory.path) : []

	property bool editing: false

	spacing: Kirigami.Units.mediumSpacing
	Layout.fillWidth: true

	PathBridge { id: pathUtils }

	Shortcut {
		sequence: "Ctrl+L"
		onActivated: pathBar.startEditing()
	}

	function startEditing() {
		if (!pathBar.directory)
			return
		pathBar.editing = true
		editField.text = pathBar.currentPath
		Qt.callLater(function () {
			editField.forceActiveFocus()
			editField.cursorPosition = editField.text.length
		})
	}

	function dropUris(uris, dest) {
		const pane = pathBar.window ? pathBar.window.activePane : null
		if (!pane)
			return false
		return pane.directory.drop(uris, dest, "move")
	}

	function commit() {
		if (!pathBar.directory) {
			pathBar.editing = false
			return
		}
		const target = pathUtils.resolve_path(pathBar.currentPath, editField.text)
		pathBar.editing = false
		pathBar.directory.navigate(target)
	}

	TextField {
		id: editField
		visible: pathBar.editing
		Layout.fillWidth: true
		Layout.fillHeight: true
		placeholderText: pathBar.currentPath
		selectByMouse: true
		onAccepted: pathBar.commit()
		Keys.onEscapePressed: pathBar.editing = false
	}

	Connections {
		target: pathBar.directory
		function onPath_changed() {
			pathBar.editing = false
			if (pathBar.directory && pathBar.directory.config)
				pathBar.directory.config.notify()
		}
	}

	ListView {
		id: breadcrumbList
		visible: !pathBar.editing
		Layout.fillWidth: true
		Layout.fillHeight: true

		orientation: ListView.Horizontal
		interactive: true
		spacing: Kirigami.Units.smallSpacing
		model: pathBar.crumbs

		onCountChanged: Qt.callLater(breadcrumbList.positionViewAtEnd)

		delegate: RowLayout {
			id: crumb
			required property var modelData
			required property int index

			readonly property bool current: index === pathBar.crumbs.length - 1

			height: breadcrumbList.height
			spacing: Kirigami.Units.mediumSpacing

			Label {
				visible: crumb.index > 0
					&& (pathBar.crumbs[0].path !== "/" || crumb.index > 1)
				text: "/"
				font.pointSize: 12
				color: Kirigami.Theme.disabledTextColor
				Layout.alignment: Qt.AlignVCenter
			}

			Item {
				Layout.fillHeight: true
				Layout.preferredWidth: Math.max(40, crumbContent.implicitWidth)
				Layout.minimumWidth: 40
				implicitWidth: Math.max(40, crumbContent.implicitWidth)

				Rectangle {
					anchors.fill: parent
					z: -1
					radius: 4
					color: Kirigami.Theme.highlightColor
					opacity: crumbDrop.containsDrag ? 0.18 : 0
				}

				Timer {
					id: crumbSpring
					interval: 700
					onTriggered: if (pathBar.directory)
						pathBar.directory.navigate(crumb.modelData.path)
				}

				RowLayout {
					id: crumbContent
					anchors.fill: parent
					spacing: Kirigami.Units.smallSpacing

					Kirigami.Icon {
						visible: crumb.current
						source: pathUtils.folder_icon(crumb.modelData.path)
						Layout.preferredWidth: Kirigami.Units.iconSizes.small
						Layout.preferredHeight: Kirigami.Units.iconSizes.small
						Layout.alignment: Qt.AlignVCenter
					}

					Label {
						text: pathUtils.folder_title(crumb.modelData.path)
						Layout.alignment: Qt.AlignVCenter
					}

					MouseArea {
						anchors.fill: parent
						onClicked: {
							if (!pathBar.directory)
								return
							if (crumb.current)
								hereMenu.popup()
							else
								pathBar.directory.navigate(crumb.modelData.path)
						}
					}
				}

				DropArea {
					id: crumbDrop
					anchors.fill: parent
					onEntered: crumbSpring.restart()
					onExited: crumbSpring.stop()
					onDropped: function (drop) {
						crumbSpring.stop()
						const pane = pathBar.window ? pathBar.window.activePane : null
						if (!pane)
							return
						const uris = drop.urls && drop.urls.length > 0
							? drop.urls.join("\n") : drop.text
						pane.directory.drop(uris, crumb.modelData.path,
							pane.dropAction(drop))
						drop.acceptProposedAction()
					}
				}
			}
		}
	}

	Menu {
		id: hereMenu
		property var actions: []
		onAboutToShow: actions = pathBar.directory
			? JSON.parse(pathBar.directory.actions_json("context", "location")) : []

		Repeater {
			model: hereMenu.actions

			ShellMenuItem {
				required property var modelData
				text: pathBar.window.actionLabel(modelData.id)
				iconName: modelData.icon || ""
				shortcutText: modelData.shortcut || ""
				enabled: modelData.enabled
				onTriggered: pathBar.directory.invoke(modelData.id)
			}
		}

		MenuSeparator {}

		Menu {
			title: "Configure"
			icon.name: "preferences-system"

			ShellMenuItem {
				text: "Layout…"
				iconName: "view-list-details"
				onTriggered: configureDialog.openSection("layout")
			}
			ShellMenuItem {
				text: "Window…"
				iconName: "preferences-system-windows"
				onTriggered: configureDialog.openSection("window")
			}
			ShellMenuItem {
				text: "Folder…"
				iconName: "folder"
				onTriggered: configureDialog.openSection("folder")
			}
			ShellMenuItem {
				text: "Radio…"
				iconName: "radio-checked"
				onTriggered: configureDialog.openSection("radio")
			}
			ShellMenuItem {
				text: "Launch…"
				iconName: "system-run"
				onTriggered: configureDialog.openSection("launch")
			}
		}
	}

	ConfigureDialog {
		id: configureDialog
		directory: pathBar.directory
	}
}
