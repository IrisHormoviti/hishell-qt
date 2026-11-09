import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
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
	property var completions: []
	property int completionIndex: -1
	property bool applyingCompletion: false
	property bool pathInvalid: false
	property bool editingButtonPressed: false
	property bool crumbMenuWasOpen: false
	property double crumbMenuOpenedAt: 0
	signal locationMenuRequested(var anchor)

	Timer {
		id: crumbMenuCloseTimer
		interval: 600
		onTriggered: pathBar.crumbMenuWasOpen = false
	}

	spacing: Kirigami.Units.mediumSpacing
	Layout.fillWidth: true

	PathBridge { id: pathUtils }

	Shortcut {
		sequence: "Ctrl+L"
		onActivated: pathBar.startEditing()
	}

	function startEditing(initialText) {
		if (!pathBar.directory)
			return
		pathBar.editing = true
		pathBar.editingButtonPressed = false
		editField.text = initialText === undefined
			? pathBar.currentPath : String(initialText)
		pathBar.pathInvalid = false
		pathBar.completions = []
		Qt.callLater(function () {
			editField.forceActiveFocus()
			editField.cursorPosition = editField.text.length
			pathBar.updateCompletions()
		})
	}

	function stopEditing() {
		if (!pathBar.editing)
			return
		pathBar.editing = false
		pathBar.completions = []
		pathBar.pathInvalid = false
		pathBar.editingButtonPressed = false
	}

	function updateCompletions() {
		let list = []
		try {
			list = JSON.parse(String(pathUtils.complete_path(
				pathBar.currentPath, editField.text, 8)))
		} catch (error) {
			list = []
		}
		pathBar.completions = list
	}

	function setEditText(text) {
		pathBar.applyingCompletion = true
		editField.text = text
		pathBar.applyingCompletion = false
		editField.cursorPosition = editField.text.length
	}

	function applyCompletion(index) {
		if (index < 0 || index >= pathBar.completions.length)
			return
		pathBar.setEditText(String(pathBar.completions[index].path))
		pathBar.completionIndex = -1
		pathBar.updateCompletions()
		editField.forceActiveFocus()
	}

	function acceptCompletion() {
		if (pathBar.completions.length === 0)
			return
		const index = pathBar.completionIndex >= 0
			&& pathBar.completionIndex < pathBar.completions.length
			? pathBar.completionIndex : 0
		pathBar.applyCompletion(index)
	}

	function cycleCompletion(delta) {
		if (pathBar.completions.length === 0)
			return
		const next = pathBar.completionIndex === -1
			? (delta > 0 ? 0 : pathBar.completions.length - 1)
			: pathBar.completionIndex + delta
		if (next < 0 || next >= pathBar.completions.length)
			return
		pathBar.completionIndex = next
		pathBar.setEditText(String(pathBar.completions[next].path))
	}

	function dropUris(uris, dest) {
		const pane = pathBar.window ? pathBar.window.activePane : null
		if (!pane)
			return false
		return pane.dropInto(uris, dest, "move")
	}

	function openConfigure(section) {
		configureDialog.openSection(section)
	}

	// The path bar can only choose a folder; the view owns the transition
	// into it and takes the keyboard back once the field closes.
	function focusFolderView() {
		const pane = pathBar.window ? pathBar.window.activePane : null
		if (pane && pane.focusView)
			pane.focusView()
	}

	function goTo(path) {
		const pane = pathBar.window ? pathBar.window.activePane : null
		if (pane && pane.navigateTo)
			return pane.navigateTo(path)
		return pathBar.directory ? pathBar.directory.navigate(path) : false
	}

	function commit() {
		if (!pathBar.directory) {
			pathBar.editing = false
			return
		}
		if (!pathUtils.path_exists(pathBar.currentPath, editField.text)) {
			pathBar.pathInvalid = true
			editField.forceActiveFocus()
			return
		}
		const target = pathUtils.resolve_path(pathBar.currentPath, editField.text)
		pathBar.editing = false
		pathBar.pathInvalid = false
		pathBar.completions = []
		pathBar.goTo(target)
		pathBar.focusFolderView()
	}

	TextField {
		id: editField
		visible: pathBar.editing
		Layout.fillWidth: true
		Layout.fillHeight: true
		placeholderText: pathBar.currentPath
		selectByMouse: true
		color: pathBar.pathInvalid
			? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
		background: Rectangle {
			implicitWidth: 200
			implicitHeight: 40
			color: Kirigami.Theme.backgroundColor
			radius: Kirigami.Units.cornerRadius
			border.width: pathBar.pathInvalid ? 2 : 1
			border.color: pathBar.pathInvalid
				? Kirigami.Theme.negativeTextColor
				: Kirigami.Theme.disabledTextColor
		}

		readonly property string completionSuffix: {
			if (!pathBar.editing || pathBar.completions.length === 0)
				return ""
			const index = pathBar.completionIndex >= 0
				&& pathBar.completionIndex < pathBar.completions.length
				? pathBar.completionIndex : 0
			const completion = String(pathBar.completions[index].path)
			if (completion.startsWith(text))
				return completion.substring(text.length)
			return completion.toLowerCase().startsWith(text.toLowerCase())
				? String(pathBar.completions[index].suffix) : ""
		}

		Text {
			visible: editField.completionSuffix.length > 0
				&& editField.cursorPosition === editField.length
			x: editField.cursorRectangle.x
			y: editField.cursorRectangle.y
			width: Math.max(0, editField.width - x)
			text: editField.completionSuffix
			font: editField.font
			color: editField.color
			opacity: 0.4
			elide: Text.ElideRight
		}

		onTextChanged: {
			if (pathBar.applyingCompletion)
				return
			pathBar.completionIndex = -1
			pathBar.pathInvalid = false
			pathBar.updateCompletions()
		}
		onActiveFocusChanged: {
			if (activeFocus || !pathBar.editing)
				return
			const next = pathBar.window ? pathBar.window.activeFocusItem : null
			if (next === goButton || next === cancelButton) {
				pathBar.editingButtonPressed = true
				return
			}
			pathBar.editing = false
		}
		onAccepted: pathBar.commit()
		Keys.onEscapePressed: {
			pathBar.stopEditing()
			pathBar.focusFolderView()
		}
		Keys.onUpPressed: pathBar.cycleCompletion(-1)
		Keys.onDownPressed: pathBar.cycleCompletion(1)
		Keys.onTabPressed: function (event) {
			if (pathBar.completions.length > 0)
				pathBar.acceptCompletion()
			else
				event.accepted = false
		}
	}

	ToolButton {
		id: goButton
		visible: pathBar.editing
		icon.name: "go-next-symbolic"
		Layout.preferredHeight: editField.height
		Layout.alignment: Qt.AlignVCenter
		onPressedChanged: if (pressed)
			pathBar.editingButtonPressed = true
		onPressed: if (pathBar.directory)
			pathBar.directory.play_sound("button-pressed")
		onReleased: if (pathBar.directory)
			pathBar.directory.play_sound("button-released")
		onClicked: {
			pathBar.editingButtonPressed = false
			pathBar.commit()
		}
	}

	ToolButton {
		id: cancelButton
		visible: pathBar.editing
		icon.name: "dialog-close"
		Layout.preferredHeight: editField.height
		Layout.alignment: Qt.AlignVCenter
		onPressedChanged: if (pressed)
			pathBar.editingButtonPressed = true
		onPressed: if (pathBar.directory)
			pathBar.directory.play_sound("button-pressed")
		onReleased: if (pathBar.directory)
			pathBar.directory.play_sound("button-released")
		onClicked: {
			pathBar.stopEditing()
			pathBar.focusFolderView()
		}
	}

	Popup {
		id: completionPopup
		parent: pathBar
		x: editField.x
		y: editField.y + editField.height
		width: Math.max(editField.width, Kirigami.Units.gridUnit * 16)
		height: Math.min(completionList.contentHeight, Kirigami.Units.gridUnit * 10)
		padding: 0
		focus: false
		closePolicy: Popup.NoAutoClose
		visible: pathBar.editing && pathBar.completions.length > 0

		ListView {
			id: completionList
			anchors.fill: parent
			clip: true
			model: pathBar.completions

			delegate: ItemDelegate {
				id: completionRow
				required property var modelData
				required property int index
				width: completionList.width
				focusPolicy: Qt.NoFocus
				highlighted: pathBar.completionIndex === completionRow.index
				icon.name: completionRow.modelData.is_dir
					? "folder" : "text-x-generic"
				text: String(completionRow.modelData.name)
				onClicked: pathBar.applyCompletion(completionRow.index)
			}
		}
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
				id: crumbSlot
				Layout.fillHeight: true
				Layout.preferredWidth: crumbContent.implicitWidth
					+ crumbSlot.sidePadding * 2
				implicitWidth: crumbContent.implicitWidth
					+ crumbSlot.sidePadding * 2
				// Match the old breadcrumb FileSlot, which padded every crumb
				// and gave the current one the larger padding.
				readonly property real sidePadding: crumb.current
					? Kirigami.Units.largeSpacing : Kirigami.Units.smallSpacing

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
					onTriggered: {
						const pane = pathBar.window ? pathBar.window.activePane : null
						if (pathBar.directory && pane
								&& pane.dragPath !== crumb.modelData.path)
							pathBar.goTo(crumb.modelData.path)
					}
				}

				RowLayout {
					id: crumbContent
					anchors.verticalCenter: parent.verticalCenter
					x: crumbSlot.sidePadding
					spacing: Kirigami.Units.smallSpacing

					Kirigami.Icon {
						visible: crumb.current
						source: pathUtils.folder_icon(crumb.modelData.path)
						Layout.preferredWidth: Kirigami.Units.iconSizes.medium
						Layout.preferredHeight: Kirigami.Units.iconSizes.medium
						Layout.alignment: Qt.AlignVCenter
					}

					Label {
						text: pathUtils.folder_title(crumb.modelData.path)
						Layout.alignment: Qt.AlignVCenter
					}
				}

				MouseArea {
					anchors.fill: parent
					onDoubleClicked: if (crumb.current) {
						pathBar.crumbMenuWasOpen = false
						crumbMenuCloseTimer.stop()
						pathBar.startEditing("")
					}
					onClicked: {
						if (!pathBar.directory)
							return
						if (crumb.current) {
							// A second click on the current crumb edits the
							// location instead of reopening the folder menu.
							if (pathBar.crumbMenuWasOpen
									&& Date.now() - pathBar.crumbMenuOpenedAt < 800) {
								pathBar.crumbMenuWasOpen = false
								crumbMenuCloseTimer.stop()
								Qt.callLater(function () {
									pathBar.startEditing("")
								})
							} else {
								pathBar.crumbMenuWasOpen = true
								pathBar.crumbMenuOpenedAt = Date.now()
								crumbMenuCloseTimer.restart()
								pathBar.locationMenuRequested(crumbSlot)
							}
						} else {
							pathBar.goTo(crumb.modelData.path)
						}
					}
				}

				DropArea {
					id: crumbDrop
					anchors.fill: parent
					onEntered: {
						const pane = pathBar.window ? pathBar.window.activePane : null
						if (!pane || pane.dragPath !== crumb.modelData.path)
							crumbSpring.restart()
					}
					onExited: crumbSpring.stop()
					onDropped: function (drop) {
						crumbSpring.stop()
						const pane = pathBar.window ? pathBar.window.activePane : null
						if (!pane)
							return
						const uris = drop.urls && drop.urls.length > 0
							? drop.urls.join("\n") : drop.text
						pane.dropInto(uris, crumb.modelData.path,
							pane.dropAction(drop))
						drop.acceptProposedAction()
					}
				}
			}
		}
	}



	Dialog {
		id: configureDialog

		property var directory: pathBar.directory
		property string section: "layout"
		property bool local: directory ? directory.has_meta() : false
		readonly property var config: configureDialog.directory ? configureDialog.directory.config : null

		title: configureDialog.section === "view" ? "View"
			: configureDialog.section === "layout" ? "Layout"
			: configureDialog.section === "window" ? "Window"
			: configureDialog.section === "folder" ? "Folder"
			: configureDialog.section === "radio" ? "Radio" : "Launch"
		parent: Overlay.overlay
		modal: true
		standardButtons: Dialog.Close
		width: Math.min(560, parent ? parent.width - 32 : 560)
		height: Math.min(640, parent ? parent.height - 32 : 640)
		x: parent ? Math.round((parent.width - width) / 2) : 0
		y: parent ? Math.max(0, Math.round((parent.height - height) / 2)) : 0

		function openSection(name) {
			configureDialog.section = name
			configureDialog.local = configureDialog.directory ? configureDialog.directory.has_meta() : false
			configureDialog.open()
		}

		function setc(key, value) {
			if (!configureDialog.directory)
				return
			configureDialog.directory.set_config_scoped(key, String(value), configureDialog.local)
			if (configureDialog.config)
				configureDialog.config.notify()
		}

		component SectionHeading: Label {
			Layout.fillWidth: true
			Layout.topMargin: Kirigami.Units.largeSpacing
			font.bold: true
			font.capitalization: Font.AllUppercase
			opacity: 0.65
			visible: false
		}

		component ToggleRow: RowLayout {
			id: row
			property alias text: label.text
			property bool checked: false
			signal toggled(bool checked)
			Layout.fillWidth: true
			Label {
				id: label
				Layout.fillWidth: true
				wrapMode: Text.WordWrap
			}
			Switch {
				id: toggle
				onToggled: row.toggled(checked)
				Binding {
					target: toggle
					property: "checked"
					value: row.checked
					restoreMode: Binding.RestoreNone
				}
			}
		}

		component ChoiceRow: RowLayout {
			id: row
			property alias text: label.text
			property var labels: []
			property var values: []
			property string value: ""
			signal selected(string value)
			Layout.fillWidth: true
			Label {
				id: label
				Layout.fillWidth: true
			}
			ComboBox {
				id: combo
				Layout.preferredWidth: 180
				model: row.labels
				onActivated: row.selected(row.values[index])
				Binding {
					target: combo
					property: "currentIndex"
					value: Math.max(0, row.values.indexOf(row.value))
					restoreMode: Binding.RestoreNone
				}
			}
		}

		component TextRow: RowLayout {
			id: row
			property alias text: label.text
			property string value: ""
			signal edited(string value)
			Layout.fillWidth: true
			Label {
				id: label
				Layout.fillWidth: true
			}
			TextField {
				id: field
				Layout.preferredWidth: 260
				onEditingFinished: row.edited(text)
				Binding {
					target: field
					property: "text"
					value: row.value
					restoreMode: Binding.RestoreNone
				}
			}
		}

		ScrollView {
			anchors.fill: parent
			clip: true

			ColumnLayout {
				width: configureDialog.availableWidth
				spacing: Kirigami.Units.smallSpacing

				RowLayout {
					Layout.fillWidth: true
					Label {
						Layout.fillWidth: true
						text: "Apply To"
					}
					CheckBox {
						text: "This folder only"
						checked: configureDialog.local
						onToggled: configureDialog.local = checked
					}
				}

				SectionHeading {
					text: "View"
					visible: configureDialog.section === "view"
				}
				ChoiceRow {
					text: "View mode"
					labels: ["Grid", "List"]
					values: ["GRID", "LIST"]
					value: configureDialog.config ? configureDialog.config.view_mode : "GRID"
					visible: configureDialog.section === "view"
					onSelected: value => configureDialog.setc("view_mode", value)
				}
				ChoiceRow {
					text: "Icon sizing"
					labels: ["By lines", "By icon size"]
					values: ["LINES", "SIZE"]
					value: configureDialog.config ? configureDialog.config.grid_mode : "LINES"
					visible: configureDialog.section === "view"
					onSelected: value => configureDialog.setc("grid_mode", value)
				}
				TextRow {
					text: "Lines (1-8)"
					value: configureDialog.config ? String(configureDialog.config.grid_lines) : "4"
					visible: configureDialog.section === "view"
					onEdited: value => configureDialog.setc("lines", value)
				}
				TextRow {
					text: "Icon size in pixels"
					value: configureDialog.config ? String(configureDialog.config.grid_size) : "72"
					visible: configureDialog.section === "view"
					onEdited: value => configureDialog.setc("grid_size", value)
				}
				ChoiceRow {
					text: "Horizontal alignment"
					labels: ["Fill", "Left", "Center", "Right"]
					values: ["FILL", "LEFT", "CENTER", "RIGHT"]
					value: configureDialog.config ? configureDialog.config.gridHorizontalAlign : "FILL"
					visible: configureDialog.section === "view"
					onSelected: value => configureDialog.setc("grid_horizontal_align", value)
				}
				ChoiceRow {
					text: "Vertical alignment"
					labels: ["Fill", "Top", "Center", "Bottom"]
					values: ["FILL", "TOP", "CENTER", "BOTTOM"]
					value: configureDialog.config ? configureDialog.config.gridVerticalAlign : "TOP"
					visible: configureDialog.section === "view"
					onSelected: value => configureDialog.setc("grid_vertical_align", value)
				}
				ToggleRow {
					text: "Show labels"
					checked: configureDialog.config ? configureDialog.config.show_labels : true
					visible: configureDialog.section === "view"
					onToggled: checked => configureDialog.setc("show_labels", checked)
				}
				ToggleRow {
					text: "Labels beside icons"
					checked: configureDialog.config ? configureDialog.config.gridLabelsBesidesIcons : false
					visible: configureDialog.section === "view"
					onToggled: checked => configureDialog.setc("grid_labels_beside_icons", checked)
				}
				ChoiceRow {
					text: "Label text"
					labels: ["Title", "File name"]
					values: ["TITLE", "FILENAME"]
					value: configureDialog.config ? configureDialog.config.label_text : "TITLE"
					visible: configureDialog.section === "view"
					onSelected: value => configureDialog.setc("label_text", value)
				}
				ToggleRow {
					text: "List header"
					checked: configureDialog.config ? configureDialog.config.list_header : false
					visible: configureDialog.section === "view"
					onToggled: checked => configureDialog.setc("list_header", checked)
				}
				ChoiceRow {
					text: "Sort"
					labels: ["Newest", "Oldest", "Alphabetical", "Free placement"]
					values: ["NEWEST", "OLDEST", "ALPHABETICAL", "FREE"]
					value: configureDialog.config ? configureDialog.config.sort : "NEWEST"
					visible: configureDialog.section === "view"
					onSelected: value => configureDialog.setc("sort", value)
				}
				ChoiceRow {
					text: "Group"
					labels: ["None", "Date", "Letters", "Type", "Custom"]
					values: ["NONE", "DATE", "LETTERS", "TYPE", "CUSTOM"]
					value: configureDialog.config ? configureDialog.config.group_mode : "NONE"
					visible: configureDialog.section === "view"
					onSelected: value => configureDialog.setc("group_mode", value)
				}
				ToggleRow {
					text: "Smooth scrolling"
					checked: configureDialog.config ? configureDialog.config.smoothScrolling : true
					visible: configureDialog.section === "view"
					onToggled: checked => configureDialog.setc("smooth_scrolling", checked)
				}
				ToggleRow {
					text: "Open on click"
					checked: configureDialog.config ? configureDialog.config.open_on_click : true
					visible: configureDialog.section === "view"
					onToggled: checked => configureDialog.setc("open_on_click", checked)
				}
				ToggleRow {
					text: "Focus empty slots"
					checked: configureDialog.config ? configureDialog.config.focusEmptySlots : false
					visible: configureDialog.section === "view"
					onToggled: checked => configureDialog.setc("focus_empty_slots", checked)
				}
				TextRow {
					text: "Wallpaper"
					value: configureDialog.config ? configureDialog.config.wallpaper : ""
					visible: configureDialog.section === "view"
					onEdited: value => configureDialog.setc("wallpaper", value)
				}
				Button {
					text: "Reset manual placement"
					visible: configureDialog.section === "view"
					onClicked: if (configureDialog.directory)
						configureDialog.directory.reset_free_positions()
				}

				SectionHeading { text: "Layout"; visible: true }
				TextRow {
					text: "Header layout (JSON)"
					value: configureDialog.config ? configureDialog.config.header_layout : "[]"
					visible: configureDialog.section === "layout"
					onEdited: value => configureDialog.setc("header_layout", value)
				}
				TextRow {
					text: "Top layout (JSON)"
					value: configureDialog.config ? configureDialog.config.top_layout : "[]"
					visible: configureDialog.section === "layout"
					onEdited: value => configureDialog.setc("top_layout", value)
				}
				TextRow {
					text: "Middle layout (JSON)"
					value: configureDialog.config ? configureDialog.config.middle_layout : "[]"
					visible: configureDialog.section === "layout"
					onEdited: value => configureDialog.setc("middle_layout", value)
				}
				TextRow {
					text: "Bottom layout (JSON)"
					value: configureDialog.config ? configureDialog.config.bottom_layout : "[]"
					visible: configureDialog.section === "layout"
					onEdited: value => configureDialog.setc("bottom_layout", value)
				}

				SectionHeading { text: "Window"; visible: configureDialog.section === "window" }
				ToggleRow {
					text: "Native title bar"
					checked: configureDialog.config ? configureDialog.config.native_titlebar : true
					visible: configureDialog.section === "window"
					onToggled: checked => configureDialog.setc("native_titlebar", checked)
				}
				ToggleRow {
					text: "Native menu bar"
					checked: configureDialog.config ? configureDialog.config.native_menubar : false
					visible: configureDialog.section === "window"
					onToggled: checked => configureDialog.setc("native_menubar", checked)
				}
				ToggleRow {
					text: "Native menus"
					checked: configureDialog.config ? configureDialog.config.native_menus : false
					visible: configureDialog.section === "window"
					onToggled: checked => configureDialog.setc("native_menus", checked)
				}
				ToggleRow {
					text: "Show shortcuts"
					checked: configureDialog.config ? configureDialog.config.show_shortcuts : true
					visible: configureDialog.section === "window"
					onToggled: checked => configureDialog.setc("show_shortcuts", checked)
				}
				ToggleRow {
					text: "Maximized"
					checked: configureDialog.config ? configureDialog.config.maximized : false
					visible: configureDialog.section === "window"
					onToggled: checked => configureDialog.setc("maximized", checked)
				}

				SectionHeading { text: "Folder"; visible: configureDialog.section === "folder" }
				TextRow {
					text: "Title"
					value: configureDialog.config ? configureDialog.config.title : ""
					visible: configureDialog.section === "folder"
					onEdited: value => configureDialog.setc("title", value)
				}
				TextRow {
					text: "Icon"
					value: configureDialog.config ? configureDialog.config.icon : ""
					visible: configureDialog.section === "folder"
					onEdited: value => configureDialog.setc("icon", value)
				}

				SectionHeading { text: "Radio"; visible: configureDialog.section === "radio" }
				ToggleRow {
					text: "Enable radio groups"
					checked: configureDialog.config ? configureDialog.config.radio_enabled : false
					visible: configureDialog.section === "radio"
					onToggled: checked => configureDialog.setc("radio_enabled", checked)
				}
				ChoiceRow {
					text: "Radio scope"
					labels: ["All", "Directories", "Files"]
					values: ["ALL", "DIRECTORIES", "FILES"]
					value: configureDialog.config ? configureDialog.config.radio_only : "ALL"
					visible: configureDialog.section === "radio"
					onSelected: value => configureDialog.setc("radio_only", value)
				}
				TextRow {
					text: "Radio selected"
					value: configureDialog.config ? configureDialog.config.radio_selected : ""
					visible: configureDialog.section === "radio"
					onEdited: value => configureDialog.setc("radio_selected", value)
				}
				TextRow {
					text: "Radio exec"
					value: configureDialog.config ? configureDialog.config.radio_exec : ""
					visible: configureDialog.section === "radio"
					onEdited: value => configureDialog.setc("radio_exec", value)
				}

				SectionHeading { text: "Launch"; visible: configureDialog.section === "launch" }
				TextRow {
					text: "Execution wrapper"
					value: configureDialog.config ? configureDialog.config.executionWrapper : ""
					visible: configureDialog.section === "launch"
					onEdited: value => configureDialog.setc("execution_wrapper", value)
				}
				TextRow {
					text: "Screen"
					value: configureDialog.config ? configureDialog.config.screen_name : ""
					visible: configureDialog.section === "launch"
					onEdited: value => configureDialog.setc("screen", value)
				}
			}
		}
	}
}
