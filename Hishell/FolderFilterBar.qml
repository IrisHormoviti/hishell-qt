// The type-to-filter bar: shown above the grid while a filter is active, with
// the typed text, the match count and a clear button. Split out of FolderView,
// which only wires it to the directory and the keyboard.

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import Hishell

Rectangle {
	id: filterBar

	property Directory directory
	// Number of items the filter currently matches.
	property int matchCount: 0
	property bool filterActive: false
	// The root window, for event sounds.
	property var window

	// The view owns the directory and the keyboard, so it performs these.
	signal focusRequested()
	signal clearRequested()

	function playSound(name) {
		if (filterBar.window && filterBar.window.sound)
			filterBar.window.sound.play(name);
	}

	z: 3
	anchors.top: parent.top
	anchors.left: parent.left
	anchors.right: parent.right
	anchors.margins: Kirigami.Units.mediumSpacing
	height: Kirigami.Units.gridUnit * 2
	radius: Kirigami.Units.cornerRadius

	visible: opacity > 0
	opacity: filterBar.filterActive ? 1 : 0
	Behavior on opacity {
		NumberAnimation {
			duration: 120
			easing.type: Easing.OutCubic
		}
	}

	Kirigami.Theme.colorSet: Kirigami.Theme.Header
	color: Kirigami.Theme.backgroundColor
	border.width: 1
	border.color: Kirigami.Theme.highlightColor

	MouseArea {
		anchors.fill: parent
		acceptedButtons: Qt.AllButtons
		onPressed: mouse => {
			mouse.accepted = true;
			filterBar.focusRequested();
		}
	}

	RowLayout {
		anchors.fill: parent
		anchors.leftMargin: Kirigami.Units.largeSpacing
		anchors.rightMargin: Kirigami.Units.smallSpacing
		spacing: Kirigami.Units.smallSpacing

		Kirigami.Icon {
			source: "search"
			Layout.preferredWidth: Kirigami.Units.iconSizes.small
			Layout.preferredHeight: Kirigami.Units.iconSizes.small
		}

		Label {
			text: filterBar.directory ? String(filterBar.directory.filter) : ""
			font.weight: Font.Medium
			elide: Text.ElideRight
			Layout.fillWidth: true
		}

		Label {
			text: filterBar.matchCount === 1 ? qsTr("1 match") : qsTr("%1 matches").arg(filterBar.matchCount)
			opacity: 0.7
			elide: Text.ElideRight
		}

		ToolButton {
			icon.name: "edit-clear"
			focusPolicy: Qt.NoFocus
			flat: true
			ToolTip.text: qsTr("Clear filter")
			ToolTip.visible: hovered
			onPressed: filterBar.playSound("button-pressed")
			onReleased: filterBar.playSound("button-released")
			onClicked: filterBar.clearRequested()
		}
	}
}
