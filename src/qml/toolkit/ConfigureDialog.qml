import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Dialog {
	id: configure

	property var directory: null
	property string section: "layout"
	property bool local: directory ? directory.has_meta() : false
	readonly property var config: configure.directory ? configure.directory.config : null

	title: configure.section === "layout" ? "Layout"
		: configure.section === "window" ? "Window"
		: configure.section === "folder" ? "Folder"
		: configure.section === "radio" ? "Radio" : "Launch"
	parent: Overlay.overlay
	modal: true
	standardButtons: Dialog.Close
	width: Math.min(560, parent ? parent.width - 32 : 560)
	height: Math.min(640, parent ? parent.height - 32 : 640)
	x: parent ? Math.round((parent.width - width) / 2) : 0
	y: parent ? Math.max(0, Math.round((parent.height - height) / 2)) : 0

	function openSection(name) {
		configure.section = name
		configure.local = configure.directory ? configure.directory.has_meta() : false
		configure.open()
	}

	function setc(key, value) {
		if (!configure.directory)
			return
		configure.directory.set_config_scoped(key, String(value), configure.local)
		if (configure.config)
			configure.config.notify()
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
			width: configure.availableWidth
			spacing: Kirigami.Units.smallSpacing

			RowLayout {
				Layout.fillWidth: true
				Label {
					Layout.fillWidth: true
					text: "Apply To"
				}
				CheckBox {
					text: "This folder only"
					checked: configure.local
					onToggled: configure.local = checked
				}
			}

			SectionHeading { text: "Layout"; visible: true }
			TextRow {
				text: "Header layout (JSON)"
				value: configure.config ? configure.config.header_layout : "[]"
				visible: configure.section === "layout"
				onEdited: value => configure.setc("header_layout", value)
			}
			TextRow {
				text: "Top layout (JSON)"
				value: configure.config ? configure.config.top_layout : "[]"
				visible: configure.section === "layout"
				onEdited: value => configure.setc("top_layout", value)
			}
			TextRow {
				text: "Middle layout (JSON)"
				value: configure.config ? configure.config.middle_layout : "[]"
				visible: configure.section === "layout"
				onEdited: value => configure.setc("middle_layout", value)
			}
			TextRow {
				text: "Bottom layout (JSON)"
				value: configure.config ? configure.config.bottom_layout : "[]"
				visible: configure.section === "layout"
				onEdited: value => configure.setc("bottom_layout", value)
			}

			SectionHeading { text: "Window"; visible: configure.section === "window" }
			ToggleRow {
				text: "Native title bar"
				checked: configure.config ? configure.config.native_titlebar : true
				visible: configure.section === "window"
				onToggled: checked => configure.setc("native_titlebar", checked)
			}
			ToggleRow {
				text: "Native menu bar"
				checked: configure.config ? configure.config.native_menubar : false
				visible: configure.section === "window"
				onToggled: checked => configure.setc("native_menubar", checked)
			}
			ToggleRow {
				text: "Native menus"
				checked: configure.config ? configure.config.native_menus : false
				visible: configure.section === "window"
				onToggled: checked => configure.setc("native_menus", checked)
			}
			ToggleRow {
				text: "Show shortcuts"
				checked: configure.config ? configure.config.show_shortcuts : true
				visible: configure.section === "window"
				onToggled: checked => configure.setc("show_shortcuts", checked)
			}
			ToggleRow {
				text: "Maximized"
				checked: configure.config ? configure.config.maximized : false
				visible: configure.section === "window"
				onToggled: checked => configure.setc("maximized", checked)
			}

			SectionHeading { text: "Folder"; visible: configure.section === "folder" }
			TextRow {
				text: "Title"
				value: configure.config ? configure.config.title : ""
				visible: configure.section === "folder"
				onEdited: value => configure.setc("title", value)
			}
			TextRow {
				text: "Icon"
				value: configure.config ? configure.config.icon : ""
				visible: configure.section === "folder"
				onEdited: value => configure.setc("icon", value)
			}

			SectionHeading { text: "Radio"; visible: configure.section === "radio" }
			ToggleRow {
				text: "Enable radio groups"
				checked: configure.config ? configure.config.radio_enabled : false
				visible: configure.section === "radio"
				onToggled: checked => configure.setc("radio_enabled", checked)
			}
			ChoiceRow {
				text: "Radio scope"
				labels: ["All", "Directories", "Files"]
				values: ["ALL", "DIRECTORIES", "FILES"]
				value: configure.config ? configure.config.radio_only : "ALL"
				visible: configure.section === "radio"
				onSelected: value => configure.setc("radio_only", value)
			}
			TextRow {
				text: "Radio selected"
				value: configure.config ? configure.config.radio_selected : ""
				visible: configure.section === "radio"
				onEdited: value => configure.setc("radio_selected", value)
			}
			TextRow {
				text: "Radio exec"
				value: configure.config ? configure.config.radio_exec : ""
				visible: configure.section === "radio"
				onEdited: value => configure.setc("radio_exec", value)
			}

			SectionHeading { text: "Launch"; visible: configure.section === "launch" }
			TextRow {
				text: "Execution wrapper"
				value: configure.config ? configure.config.executionWrapper : ""
				visible: configure.section === "launch"
				onEdited: value => configure.setc("execution_wrapper", value)
			}
			TextRow {
				text: "Screen"
				value: configure.config ? configure.config.screen_name : ""
				visible: configure.section === "launch"
				onEdited: value => configure.setc("screen", value)
			}
		}
	}
}
