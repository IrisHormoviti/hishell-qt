// The selection toolbar: shown at the bottom of a pane while selection mode is
// active, with a select-all checkbox, the count and a deselect button. Split
// out of FolderView, which only wires it to the selection manager.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Rectangle {
	id: selectionBar

	property SelectionManager selectionManager
	// Number of items in the view, for the select-all checkbox state.
	property int itemCount: 0
	// The root window, for event sounds.
	property var window

	// Selecting all needs the view's item list, so the view performs it.
	signal selectAllRequested()

	function playSound(name) {
		if (selectionBar.window && selectionBar.window.sound)
			selectionBar.window.sound.play(name);
	}

	readonly property bool selectionActive: selectionBar.selectionManager ? selectionBar.selectionManager.selection_active : false
	// The labels are dropped so the buttons stay reachable in a narrow pane.
	readonly property bool compact: selectionBar.width < Kirigami.Units.largeSpacing * 50

	z: 2
	anchors.left: parent.left
	anchors.right: parent.right
	anchors.bottom: parent.bottom
	anchors.margins: Kirigami.Units.mediumSpacing

	height: selectionBar.selectionActive ? 48 : 0
	visible: selectionBar.selectionActive
	radius: 6

	Kirigami.Theme.colorSet: Kirigami.Theme.Header
	color: Kirigami.Theme.backgroundColor

	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.AllButtons
		onClicked: mouse => {
			mouse.accepted = true;
		}
		onPressed: mouse => {
			mouse.accepted = true;
		}
	}

	TextMetrics {
		id: countMetrics
		font: countLabel.font
		text: countLabel.text
	}

	Kirigami.Separator {
		anchors.top: parent.top
		anchors.left: parent.left
		anchors.right: parent.right
	}

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
			checked: selectionBar.selectionManager.selected_count > 0 && selectionBar.selectionManager.selected_count === selectionBar.itemCount
			tristate: selectionBar.selectionManager.selected_count > 0 && selectionBar.selectionManager.selected_count < selectionBar.itemCount
			checkState: tristate ? Qt.PartiallyChecked : (checked ? Qt.Checked : Qt.Unchecked)
			Layout.preferredWidth: Kirigami.Units.iconSizes.medium
			Layout.preferredHeight: Kirigami.Units.iconSizes.medium
			onClicked: {
				if (selectionBar.selectionManager.selected_count === selectionBar.itemCount)
					selectionBar.selectionManager.deselect_all();
				else
					selectionBar.selectAllRequested();
			}
		}

		Label {
			property string countText: selectionBar.selectionManager.selected_count + " " + (
				selectionBar.compact
					? ""
					: (selectionBar.selectionManager.selected_count > 1
						? qsTr("items selected")
						: qsTr("item selected"))
			)
			id: countLabel
			text: countText
			font.weight: Font.Medium
			elide: Text.ElideRight
			Layout.fillWidth: true
			Layout.minimumWidth: selectionBar.compact ? 0 : countMetrics.width
		}

		ToolButton {
			id: deselectAllButton
			text: qsTr("Deselect")
			icon.name: "edit-select-none"
			display: selectionBar.compact ? AbstractButton.IconOnly : AbstractButton.TextUnderIcon
			ToolTip.text: qsTr("Deselect")
			ToolTip.visible: hovered
			flat: true
			onPressed: selectionBar.playSound("button-pressed")
			onReleased: selectionBar.playSound("button-released")
			onClicked: selectionBar.selectionManager.deselect_all()
		}
	}
}
