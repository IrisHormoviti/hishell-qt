import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

// The selection toolbar: shown at the bottom of a pane while selection mode is
// active, with a select-all checkbox, the count and a deselect button.
Rectangle {
	id: selectionBar

	property var directory: null
	property var window: null

	readonly property bool selectionActive: selectionBar.directory
		? selectionBar.directory.selectionActive : false
	readonly property bool compact: selectionBar.width < Kirigami.Units.largeSpacing * 50

	z: 2
	anchors.left: parent.left
	anchors.right: parent.right
	anchors.bottom: parent.bottom
	anchors.margins: Kirigami.Units.mediumSpacing

	height: selectionBar.selectionActive ? 48 : 0
	visible: selectionBar.selectionActive
	radius: 6
	color: Kirigami.Theme.backgroundColor
	border.width: 1
	border.color: Kirigami.Theme.disabledTextColor

	Behavior on height {
		NumberAnimation {
			duration: 180
			easing.type: Easing.OutCubic
		}
	}

	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: Kirigami.Units.largeSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing

		CheckBox {
			id: selectAllCheckbox
			readonly property int selected: selectionBar.directory
				? selectionBar.directory.selectedCount : 0
			readonly property int total: selectionBar.directory
				? selectionBar.directory.itemCount : 0
			checked: selected > 0 && selected === total
			tristate: selected > 0 && selected < total
			checkState: tristate ? Qt.PartiallyChecked
				: (checked ? Qt.Checked : Qt.Unchecked)
			Layout.preferredWidth: Kirigami.Units.iconSizes.medium
			Layout.preferredHeight: Kirigami.Units.iconSizes.medium
			onClicked: {
				if (!selectionBar.directory)
					return
				if (selectAllCheckbox.selected === selectAllCheckbox.total)
					selectionBar.directory.clear_selection()
				else
					selectionBar.directory.select_all()
			}
		}

		Label {
			readonly property int count: selectionBar.directory
				? selectionBar.directory.selectedCount : 0
			text: count + " " + (selectionBar.compact ? ""
				: (count > 1 ? "items selected" : "item selected"))
			font.weight: Font.Medium
			elide: Text.ElideRight
			Layout.fillWidth: true
		}

		ToolButton {
			text: "Deselect"
			icon.name: "edit-select-none"
			display: selectionBar.compact
				? AbstractButton.IconOnly : AbstractButton.TextUnderIcon
			ToolTip.text: "Deselect"
			ToolTip.visible: hovered
			flat: true
			onClicked: if (selectionBar.directory) selectionBar.directory.clear_selection()
		}
	}
}
